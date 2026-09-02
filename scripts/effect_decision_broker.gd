## MP 결정·pending·로컬/원격 분기 (EffectManager Decision 책임 분리 — S5 / B-EM-03).
## EM facade가 setup에서 생성·주입하고 공개 API를 위임한다.
## UI(ask_*/select_*)는 host EM 공개 API → SelectionPresenter(S6). 창 오케스트레이션은 WindowCoordinator.
## network_constants 이벤트·intent 타입은 변경하지 않는다. SELECT_TARGETS payload 키(variableMaxCount)만 가산.
## 왜 RefCounted: Node 트리 수명과 무관한 상태 머신; await는 host Node의 process_frame을 사용.
class_name EffectDecisionBroker
extends RefCounted

## EffectManager 호스트 — UI(ask_*/select_*)·카드 조회·session/PM·notice·window_id 접근.
## Node로 두는 이유: PipelineRunner와 같이 class_name 순환 참조를 피함. ask_*/select_* 계약은 EM facade에 유지.
var _host: Node

## window_id → intent|null. authority remote await; late intent는 silent drop (C §5.2).
var _pending_decision: Dictionary = {}
## Dedicated INTENT 가드·상대 notice용. ServerAuthority는 get_decision_gate_state()만 사용.
var _waiting_remote_decision: bool = false
## 현재 결정 소유 network seat. turn glow·notice·INTENT seat 가드.
var _decision_owner_net_side: int = -1


## EM.setup에서 호출. host는 UI·존 조회·broadcast 콜백 제공자(EffectManager).
func setup(host: Node) -> void:
	_host = host


## Dedicated INTENT 가드용 스냅샷. Session이 private 필드 `.get()` 하지 않도록 공개 계약 유지.
## waiting=true이고 owner_net_side>=0이면 peer seat가 일치할 때만 수락.
func get_decision_gate_state() -> Dictionary:
	return {
		"waiting": _waiting_remote_decision,
		"owner_net_side": _decision_owner_net_side,
	}


## turn glow·opponent notice가 읽는 결정 소유 network seat. -1이면 비활성.
func get_decision_owner_net_side() -> int:
	return _decision_owner_net_side


## authority가 원격 INTENT를 기다리는지. notice 문구·glow 분기용.
func is_waiting_remote_decision() -> bool:
	return _waiting_remote_decision


## busy 해제 시 gate 플래그만 리셋. pending은 건드리지 않음(기존 EM._set_busy와 동일).
func clear_gate() -> void:
	_decision_owner_net_side = -1
	_waiting_remote_decision = false


## Session→PM→EM 경로로 도착한 INTENT를 pending에 채운다. 키 없으면 late → drop.
func deliver_effect_decision(intent: Dictionary) -> void:
	var window_id := int(intent.get("windowId", -1))
	if not _pending_decision.has(window_id):
		return
	_pending_decision[window_id] = intent


## forfeit 등으로 대기 중 결정을 cancel 응답으로 깨뜨린다.
func abort_pending_decisions() -> void:
	var keys := _pending_decision.keys()
	for window_id in keys:
		if _pending_decision.get(window_id) == null:
			_pending_decision[window_id] = {
				"confirmed": false,
				"takePriority": false,
				"targetUuids": [],
				"slots": [],
				"aborted": true,
			}
	_waiting_remote_decision = false
	_decision_owner_net_side = -1


## EFFECT_DECISION_REQUEST 수신. local owner만 UI → submit; 비-owner는 notice/glow만.
## 왜 presenter도 로컬 resolve: 비-authority 클라는 파이프라인을 안 돌리지만 REQUEST UI는 소유자가 처리.
func handle_decision_request(event: Dictionary) -> void:
	var window_id := int(event.get("windowId", -1))
	var owner_net_side := int(event.get("ownerSide", -1))
	_decision_owner_net_side = owner_net_side
	var kind := String(event.get("kind", ""))
	var payload: Dictionary = event.get("payload", {})
	var notice_card: Node2D = _host._resolve_notice_card_from_payload(kind, payload)
	if notice_card:
		_host._notice_card = notice_card
	_host._notify_turn_indicators()
	if not _host._is_local_decision_owner(owner_net_side):
		return
	match kind:
		NetworkConstants.EFFECT_KIND_CONFIRM:
			var card: Node2D = _host._find_card_by_uuid(int(payload.get("cardUuid", 0)))
			if card == null and not bool(payload.get("choiceDialog", false)):
				return
			var ok := false
			if bool(payload.get("choiceDialog", false)):
				ok = await _host.ask_choice_dialog(
					String(payload.get("title", "추가 효과")),
					String(payload.get("message", "")),
					String(payload.get("confirmText", "예")),
					String(payload.get("cancelText", "아니오"))
				)
			else:
				if card == null:
					return
				ok = await _host.ask_effect_confirm(card)
			_submit_effect_decision(window_id, kind, {"confirmed": ok})
		NetworkConstants.EFFECT_KIND_PRIORITY:
			var uuids: Array = payload.get("cardUuids", [])
			var card: Node2D = _host._find_card_by_uuid(int(uuids[0])) if not uuids.is_empty() else null
			if card == null:
				return
			var take_priority: bool = await _host.ask_priority_popup(card)
			_submit_effect_decision(window_id, kind, {"takePriority": take_priority})
		NetworkConstants.EFFECT_KIND_SELECT_TARGETS:
			await _handle_remote_target_decision(window_id, payload)
		NetworkConstants.EFFECT_KIND_SELECT_SLOTS:
			await _handle_remote_slot_decision(window_id, payload)


## INTENT_EFFECT_DECISION을 GameSession.submit_intent로 보낸다. 클라 owner UI 완료 후 호출.
func _submit_effect_decision(window_id: int, kind: String, response: Dictionary) -> void:
	var intent := {
		"type": NetworkConstants.INTENT_EFFECT_DECISION,
		"windowId": window_id,
		"kind": kind,
	}
	for key in response:
		intent[key] = response[key]
	_host._session().submit_intent(intent)


## 원격 SELECT_TARGETS REQUEST: payload UUID/entries → select_cards → targetUuids INTENT.
## activationPick=true 이면 발동 sheet(취소=빈 배열).
func _handle_remote_target_decision(window_id: int, payload: Dictionary) -> void:
	var candidate_uuids: Array = payload.get("selectableUuids", payload.get("candidateUuids", []))
	var display_uuids: Array = payload.get("displayUuids", candidate_uuids)
	var candidate_entries: Array = payload.get("candidateEntries", [])
	var display_entries: Array = payload.get("displayEntries", candidate_entries)
	var count := int(payload.get("count", 1))
	var source: Node2D = _host._find_card_by_uuid(int(payload.get("sourceUuid", 0)))
	var owner_net := int(payload.get("ownerSide", -1))
	if owner_net < 0 and source:
		owner_net = _host._net_side_for_card(source)
	var local_side := GameSession.get_active().network_side_to_local(owner_net)
	var candidates: Array = _host._resolve_cards_from_entries(candidate_entries, candidate_uuids, local_side)
	var display_candidates: Array = _host._resolve_cards_from_entries(display_entries, display_uuids, local_side)
	if display_candidates.is_empty():
		display_candidates = candidates.duplicate()

	if bool(payload.get("activationPick", false)):
		var title := String(payload.get("title", "효과 발동"))
		var pick: Node = await _host.ask_activation_pick_local(candidates, title)
		var act_uuids: Array = []
		if pick:
			act_uuids.append(int(pick.network_uuid))
		_submit_effect_decision(
			window_id, NetworkConstants.EFFECT_KIND_SELECT_TARGETS, {"targetUuids": act_uuids}
		)
		return

	var hint := {
		"targetLocation": int(payload.get("targetLocation", -1)),
		"displayUuids": display_uuids,
		"selectableUuids": candidate_uuids,
	}
	if payload.has("variableMaxCount"):
		hint["variableMaxCount"] = int(payload["variableMaxCount"])
	var picked: Array = await _host.select_cards(candidates, count, source, hint, display_candidates)
	var target_uuids: Array = []
	for card in picked:
		target_uuids.append(int(card.network_uuid))
	_submit_effect_decision(window_id, NetworkConstants.EFFECT_KIND_SELECT_TARGETS, {"targetUuids": target_uuids})


## 원격 SELECT_SLOTS REQUEST: network slot payload → select_slots → slots INTENT.
func _handle_remote_slot_decision(window_id: int, payload: Dictionary) -> void:
	var source: Node2D = _host._find_card_by_uuid(int(payload.get("sourceUuid", 0)))
	var slot_payloads: Array = payload.get("slots", [])
	var candidates: Array = []
	var pm: Node = _host._phase_manager()
	for slot_data in slot_payloads:
		if not slot_data is Dictionary:
			continue
		if pm and pm.has_method("resolve_field_slot_from_network"):
			var slot: CardSlot = pm.resolve_field_slot_from_network(
				int(slot_data.get("side", 0)),
				int(slot_data.get("line", 0)),
				int(slot_data.get("slotIndex", 0))
			)
			if slot:
				candidates.append(slot)
	var slot_count := int(payload.get("count", 1))
	var picked: Array = await _host.select_slots(candidates, slot_count, source)
	var slots_out: Array = []
	for slot in picked:
		if slot is CardSlot and pm and pm.has_method("encode_field_slot_for_network"):
			slots_out.append(pm.encode_field_slot_for_network(slot))
	_submit_effect_decision(window_id, NetworkConstants.EFFECT_KIND_SELECT_SLOTS, {"slots": slots_out})


## 파이프라인/창에서 플레이어 결정을 기다린다. 싱글·로컬 owner·비권위 → 로컬 UI; authority 원격 → REQUEST+pending.
## 왜 presenter branch가 로컬 resolve: DECISION_REQUEST를 받은 비-authority 클라는 파이프라인 없이 UI만 수행.
func await_player_decision(
	kind: String,
	card: Node,
	payload: Dictionary,
	local_candidates: Array = [],
	local_count: int = 0
) -> Variant:
	if not _host._is_mp_effects():
		return await _resolve_decision_locally(kind, card, payload, local_candidates, local_count)

	var net_owner: int = _host._net_side_for_card(card)
	if _host._is_local_decision_owner(net_owner):
		return await _resolve_decision_locally(kind, card, payload, local_candidates, local_count)

	if not _host.is_logic_authority():
		return await _resolve_decision_locally(kind, card, payload, local_candidates, local_count)

	var window_id: int = _host._current_window_id
	_pending_decision[window_id] = null
	_decision_owner_net_side = net_owner
	_host._notice_card = card as Node2D if card is Node2D else null
	_waiting_remote_decision = true
	_host._notify_turn_indicators()
	var pm: Node = _host._phase_manager()
	if pm and pm.has_method("broadcast_effect_decision_request"):
		pm.broadcast_effect_decision_request(window_id, kind, net_owner, payload)

	while _pending_decision.get(window_id) == null:
		if _is_match_aborted():
			_pending_decision[window_id] = {
				"confirmed": false,
				"takePriority": false,
				"targetUuids": [],
				"slots": [],
				"aborted": true,
			}
			break
		await _host.get_tree().process_frame

	_waiting_remote_decision = false
	_decision_owner_net_side = -1
	_host._notice_card = null
	_host._notify_turn_indicators()
	var intent: Dictionary = _pending_decision.get(window_id, {})
	_pending_decision.erase(window_id)
	return _parse_decision_response(kind, intent, local_candidates, local_count, payload)


## 세션/PM이 매치 종료를 알렸는지 (forfeit 등).
func _is_match_aborted() -> bool:
	if _host == null or not is_instance_valid(_host):
		return true
	if not _host.has_method("_session"):
		return false
	var session: Variant = _host._session()
	if session != null and session.has_method("is_match_aborted"):
		return bool(session.is_match_aborted())
	return false


## INTENT 응답을 kind별 bool/Array로 변환. SELECT_TARGETS는 local_candidates 우선 매칭(공개 후보/뤼트).
## request_payload: 보낸 DECISION_REQUEST. 가변 선택 상한(variableMaxCount) 클램프에 사용.
func _parse_decision_response(
	kind: String,
	intent: Dictionary,
	local_candidates: Array,
	_local_count: int,
	request_payload: Dictionary = {}
) -> Variant:
	match kind:
		NetworkConstants.EFFECT_KIND_CONFIRM:
			return bool(intent.get("confirmed", false))
		NetworkConstants.EFFECT_KIND_PRIORITY:
			return bool(intent.get("takePriority", false))
		NetworkConstants.EFFECT_KIND_SELECT_TARGETS:
			var uuids: Array = intent.get("targetUuids", [])
			var picked: Array = []
			for uuid_v in uuids:
				var uuid := int(uuid_v)
				# 공개 후보 등 find_card 범위 밖 노드는 local_candidates로 매칭 (뤼트)
				var card: Node = _host._find_card_in_candidates_by_uuid(local_candidates, uuid)
				if card == null:
					card = _host._find_card_by_uuid(uuid)
				if card:
					picked.append(card)
			return _clamp_selected_cards(picked, request_payload)
		NetworkConstants.EFFECT_KIND_SELECT_SLOTS:
			var slots_data: Array = intent.get("slots", [])
			var pm: Node = _host._phase_manager()
			var picked: Array = []
			for slot_data in slots_data:
				if not slot_data is Dictionary:
					continue
				if pm and pm.has_method("resolve_field_slot_from_network"):
					var slot: CardSlot = pm.resolve_field_slot_from_network(
						int(slot_data.get("side", 0)),
						int(slot_data.get("line", 0)),
						int(slot_data.get("slotIndex", 0))
					)
					if slot:
						picked.append(slot)
			return picked
	return null


## SELECT_TARGETS 픽을 요청 상한으로 자른다. count=-2면 variableMaxCount, 양수면 count.
func _clamp_selected_cards(picked: Array, payload: Dictionary) -> Array:
	if picked.is_empty() or payload.is_empty():
		return picked
	var count := int(payload.get("count", 0))
	var cap := picked.size()
	if count == -2:
		if not payload.has("variableMaxCount"):
			return picked
		cap = mini(cap, maxi(0, int(payload["variableMaxCount"])))
	elif count > 0:
		cap = mini(cap, count)
	if picked.size() <= cap:
		return picked
	return picked.slice(0, cap)


## SELECT_TARGETS payload → select_cards hint (variableMaxCount 포함).
func _select_hint_from_payload(payload: Dictionary) -> Dictionary:
	var hint := {}
	if payload.has("targetLocation"):
		hint["targetLocation"] = int(payload.get("targetLocation", -1))
	if payload.has("variableMaxCount"):
		hint["variableMaxCount"] = int(payload["variableMaxCount"])
	if payload.has("displayUuids"):
		hint["displayUuids"] = payload["displayUuids"]
	if payload.has("selectableUuids"):
		hint["selectableUuids"] = payload["selectableUuids"]
	return hint


## 로컬/COM/싱글 결정 UI. kind에 따라 host ask_*/select_* 위임 (EM→SelectionPresenter).
func _resolve_decision_locally(
	kind: String,
	card: Node,
	_payload: Dictionary,
	local_candidates: Array,
	local_count: int
) -> Variant:
	match kind:
		NetworkConstants.EFFECT_KIND_CONFIRM:
			if bool(_payload.get("choiceDialog", false)):
				return await _host.ask_choice_dialog(
					String(_payload.get("title", "추가 효과")),
					String(_payload.get("message", "")),
					String(_payload.get("confirmText", "예")),
					String(_payload.get("cancelText", "아니오"))
				)
			return await _host.ask_effect_confirm(card)
		NetworkConstants.EFFECT_KIND_PRIORITY:
			return await _host.ask_priority_popup(card)
		NetworkConstants.EFFECT_KIND_SELECT_TARGETS:
			if bool(_payload.get("activationPick", false)):
				var title := String(_payload.get("title", "효과 발동"))
				var pick: Node = await _host.ask_activation_pick_local(local_candidates, title)
				if pick == null:
					return []
				return [pick]
			return await _host.select_cards(
				local_candidates, local_count, card, _select_hint_from_payload(_payload)
			)
		NetworkConstants.EFFECT_KIND_SELECT_SLOTS:
			return await _host.select_slots(local_candidates, local_count, card)
	return null
