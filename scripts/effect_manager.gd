## 효과 창·선택·결정 facade (S6).
## EffectContext·DecisionBroker·WindowCoordinator·SelectionPresenter를 setup에서 생성·주입하고 공개 API를 위임한다.
## S5: MP 결정·pending은 EffectDecisionBroker. S6: 창=WindowCoordinator, 선택/UI=SelectionPresenter.
## MP 프로토콜·intent 스키마는 변경하지 않음. 카드 트리거·passive·recording lifecycle은 EM에 유지.
extends Node
class_name EffectManager

signal effect_busy_changed(busy: bool)
signal graveyard_content_changed(side: GameConstants.Side)

var context: EffectContext
var is_busy: bool = false
## SelectionPresenter와 동기화. UI/폴링 호환용 공개 플래그.
var is_effect_dialog_minimized: bool = false
var is_target_select_minimized: bool = false

var _change_recorder: EffectChangeRecorder
var _change_applier: EffectChangeApplier
var _pipeline_runner: EffectPipelineRunner
## S5: MP 결정·pending·gate 상태 소유. 공개 API는 EM이 위임.
var _decision_broker: EffectDecisionBroker
## S6: OPEN/BIND/TRASH/LIFE 창·presenter window·priority 정렬.
var _window_coordinator: EffectWindowCoordinator
## S6: select/ask/dialog·raycast·GameUILayer 연결.
var _selection_presenter: EffectSelectionPresenter
## DecisionBroker·recording·window begin이 공유. WindowCoordinator가 증가.
var _current_window_id: int = 0
## Presenter window 카드 스냅샷. glow/notice·_set_busy(false) 시 clear.
var _presenter_window_cards: Array = []
var _notice_card: Node2D = null
## sheet에서 발동 확정 후 trigger 시 중앙 confirm 스킵.
var _skip_effect_confirm: bool = false


## 입력 처리 활성화 + 카드 등 leaf 노드가 context를 찾을 그룹 등록.
func _ready() -> void:
	add_to_group("effect_manager")
	set_process_input(true)


## GameUILayer 바인딩을 SelectionPresenter에 위임 (C §5.6).
func bind_game_ui(game_ui: Node) -> void:
	if _selection_presenter:
		_selection_presenter.bind_game_ui(game_ui)


## SelectionPresenter 또는 씬 폴백으로 GameUILayer 조회. turn indicator·broker notice용.
func _get_game_ui() -> Node:
	if _selection_presenter:
		return _selection_presenter.get_game_ui()
	return get_node_or_null("../GameUILayer")


## 카드/슬롯 선택 중인지. SelectionPresenter 위임.
func is_selecting() -> bool:
	return _selection_presenter.is_selecting() if _selection_presenter else false


## 효과 busy면 플레이어 액션 차단.
func blocks_player_actions() -> bool:
	return is_busy


## 필드 선택 후보 클릭 시 zone browse 유지. SelectionPresenter 위임.
func should_keep_zone_browse_on_card_click(card: Node) -> bool:
	if _selection_presenter == null:
		return false
	return _selection_presenter.should_keep_zone_browse_on_card_click(card)


## 슬롯 선택 중 사이드바 차단. SelectionPresenter 위임.
func blocks_sidebar() -> bool:
	if _selection_presenter == null:
		return false
	return _selection_presenter.blocks_sidebar()


## 매치 Context·Broker·Window·Selection을 생성·소유하고 Runner/Applier에 주입한다.
## PhaseManager.start_match 경로에서 호출. 왜 static instance 금지: 리매치·테스트 stale 참조 (B-EC-03).
func setup(
	phase_manager: Node,
	field_manager: FieldManager,
	player_deck: DeckZone,
	opponent_deck: DeckZone,
	player_hand: Node,
	opponent_hand: Node,
	card_manager: Node
) -> void:
	context = EffectContext.new()
	context.setup(
		phase_manager,
		field_manager,
		player_deck,
		opponent_deck,
		player_hand,
		opponent_hand,
		card_manager,
		self
	)
	_change_recorder = EffectChangeRecorder.new()
	_change_applier = EffectChangeApplier.new()
	_change_applier.setup(context)
	_pipeline_runner = EffectPipelineRunner.new()
	_pipeline_runner.setup(self, context)
	context.set_recorder(_change_recorder)
	_decision_broker = EffectDecisionBroker.new()
	_decision_broker.setup(self)
	_window_coordinator = EffectWindowCoordinator.new()
	_window_coordinator.setup(self)
	_selection_presenter = EffectSelectionPresenter.new()
	_selection_presenter.setup(self)


## 턴 효과 이력 리셋. 페이즈/턴 경계에서 호출.
func reset_turn_history() -> void:
	context.reset_turn_history()


## 카드 파괴 후 PASSIVE 재계산 스케줄.
func on_card_destroyed(_card: Node, _suppress_trash: bool) -> void:
	schedule_passive_refresh()


## 묘지 변경 시그널 중계. Context/DeckZone 경로.
func notify_graveyard_changed(side: GameConstants.Side) -> void:
	graveyard_content_changed.emit(side)


## 필드 PASSIVE·STACK 전량 재계산 후 라인 파워 UI 갱신.
func _run_passive_refresh() -> void:
	# 필드 PASSIVE·STACK은 매 갱신마다 재계산(누적 방지)
	if _pipeline_runner == null or context == null:
		return
	var bonus_before := _snapshot_passive_line_bonuses()
	_clear_field_passive_modifiers()
	_clear_field_stack_effect_flags()
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for card in context.get_field_cards(side, false):
			if not _is_passive_eligible_card(card) or not card.card_data:
				continue
			for p in card.card_data.pipelines:
				if p and p.trigger == "PASSIVE":
					await _pipeline_runner.run_passive_for_card(card)
					break
	await _apply_field_stack_effects()
	await _play_passive_bonus_change_fx(bonus_before)
	# clear 직후 일시 음수는 위에서 보류 — 재적용 끝난 뒤 최종 LP로 처치
	_check_field_destroy_after_passive_refresh()
	context._refresh_line_power_ui()


## 필드 카드별 _passive_line_bonus 스냅샷 (변동 시에만 EffectFx).
func _snapshot_passive_line_bonuses() -> Dictionary:
	var snap: Dictionary = {}
	if context == null:
		return snap
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for card in context.get_field_cards(side, false):
			if not is_instance_valid(card):
				continue
			snap[card] = int(card.get("_passive_line_bonus"))
	return snap


## 보너스 증가=상승기류 · 감소=하강기류. 초단갭으로 여러 장.
func _play_passive_bonus_change_fx(bonus_before: Dictionary) -> void:
	if context == null or not EffectFx.is_active():
		return
	var ups: Array = []
	var downs: Array = []
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for card in context.get_field_cards(side, false):
			if not is_instance_valid(card):
				continue
			var after := int(card.get("_passive_line_bonus"))
			var before := int(bonus_before.get(card, 0))
			if after == before:
				continue
			if after > before:
				ups.append(card)
			else:
				downs.append(card)
	if not ups.is_empty():
		await EffectFx.await_aura_batch(ups, 1)
	if not downs.is_empty():
		await EffectFx.await_aura_batch(downs, -1)

## PASSIVE 재적용 후 스탯 파괴 검사.
func _check_field_destroy_after_passive_refresh() -> void:
	if context == null:
		return
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for card in context.get_field_cards(side, false):
			if is_instance_valid(card) and card.has_method("check_destroy_from_stats"):
				card.check_destroy_from_stats()


## 스택 효과 플래그 클리어 (재적용 전).
func _clear_field_stack_effect_flags() -> void:
	if context == null:
		return
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for card in context.get_field_cards(side, false):
			if is_instance_valid(card) and card.has_method("clear_stack_effect_flags"):
				card.clear_stack_effect_flags()


## 필드 호스트별 STACK 파이프라인 실행.
func _apply_field_stack_effects() -> void:
	if _pipeline_runner == null or context == null:
		return
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for host in context.get_field_cards(side, false):
			if not _is_passive_eligible_card(host):
				continue
			if not host.get("stack_cards") or host.stack_cards.is_empty():
				continue
			for stacked in host.stack_cards:
				if not is_instance_valid(stacked):
					continue
				await _pipeline_runner.run_stack_for_host(host, stacked)


## 필드 PASSIVE 수정치 클리어 (재적용 전).
func _clear_field_passive_modifiers() -> void:
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for card in context.get_field_cards(side, false):
			if is_instance_valid(card) and card.has_method("clear_passive_field_modifiers"):
				card.clear_passive_field_modifiers()


var _passive_refresh_pending: bool = false
var _passive_refresh_running: bool = false
## schedule가 대기·실행 중일 때 재요청 — WINDOW_START와 SPAWN RESULT가 겹치면
## 코얼레스로 재스케줄이 버려져 클라 이즈라엘 +2가 빠지는 문제 방지
var _passive_refresh_rerun: bool = false


## PASSIVE 갱신을 deferred로 스케줄. 실행 중 재요청은 rerun 플래그로 보존.
func schedule_passive_refresh() -> void:
	if context == null:
		return
	if _passive_refresh_pending or _passive_refresh_running:
		_passive_refresh_rerun = true
		return
	_passive_refresh_pending = true
	call_deferred("_deferred_passive_refresh")


## PASSIVE를 스케줄하고 완료까지 대기. 전투 직전 등 clear→재적용 레이스 방지.
func await_passive_refresh() -> void:
	schedule_passive_refresh()
	while _passive_refresh_pending or _passive_refresh_running or _passive_refresh_rerun:
		await get_tree().process_frame


## REVEALED 카드만 PASSIVE/STACK 대상.
func _is_passive_eligible_card(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	return int(card.get("reveal_state")) == GameConstants.RevealState.REVEALED


## deferred PASSIVE 실행. rerun이면 한 번 더 스케줄.
func _deferred_passive_refresh() -> void:
	_passive_refresh_pending = false
	_passive_refresh_running = true
	await _run_passive_refresh()
	_passive_refresh_running = false
	if _passive_refresh_rerun:
		_passive_refresh_rerun = false
		schedule_passive_refresh()


## 활성 GameSessionBase.
func _session() -> GameSessionBase:
	return GameSession.get_active()


## 온라인 플레이 모드인지.
func _is_online_mp() -> bool:
	return _session().play_mode == GameSessionBase.PlayMode.ONLINE


## 온라인 + effects_enabled (창 broadcast·recording 조건).
func _is_mp_effects() -> bool:
	return _is_online_mp() and _session().effects_enabled


## 싱글/Host/Dedicated authority면 true. 파이프라인·recording 주체.
func is_logic_authority() -> bool:
	return not _is_online_mp() or _session().is_authoritative()


## 온라인 비권위 클라. 창 로직 대신 present_* 미러만.
func is_presenter_only() -> bool:
	return _is_online_mp() and not _session().is_authoritative()


## Context가 가리키는 PhaseManager.
func _phase_manager() -> Node:
	return context.phase_manager if context else null


## 카드 owner_side → network seat.
func _net_side_for_card(card: Node) -> int:
	return _session().local_side_to_network(card.owner_side)


## net_owner가 이 피어의 로컬 입력 seat인지. Dedicated는 항상 false(INTENT만).
func _is_local_decision_owner(net_owner_side: int) -> bool:
	if not _session().has_local_player_input():
		return false
	return net_owner_side == int(_session().my_network_side)


## busy 중 결정 소유자(또는 창 카드)의 로컬 side. Phase 버튼 턴 색 등에 사용.
func get_turn_glow_local_side() -> int:
	if is_busy:
		var owner_net := _decision_broker.get_decision_owner_net_side() if _decision_broker else -1
		if owner_net >= 0:
			return int(_session().network_side_to_local(owner_net))
		var window_card := _get_primary_window_card()
		if window_card:
			return int(window_card.owner_side)
		if not _is_online_mp():
			return int(GameConstants.Side.PLAYER)
	var pm := _phase_manager()
	if pm and pm.get("current_phase") == GameConstants.Phase.SETTING:
		return int(pm.active_side)
	return -1


## MP busy 중 상대 효과 notice 패널용 스냅샷. 로컬 결정 owner면 숨김.
func get_opponent_effect_notice() -> Dictionary:
	if not is_busy or not _is_online_mp():
		return {"visible": false}
	var owner_net := _decision_broker.get_decision_owner_net_side() if _decision_broker else -1
	var waiting_remote := _decision_broker.is_waiting_remote_decision() if _decision_broker else false
	if owner_net >= 0 and _is_local_decision_owner(owner_net):
		return {"visible": false}

	var card: Node2D = _notice_card
	if card == null:
		card = _get_opponent_window_card()

	if card == null:
		if waiting_remote or owner_net >= 0:
			return {"visible": true, "card_name": "효과 처리 중", "trigger": "", "card": null}
		return {"visible": false}

	if owner_net >= 0 and _is_local_decision_owner(owner_net):
		return {"visible": false}
	if card.owner_side == GameConstants.Side.PLAYER and not waiting_remote:
		if not is_presenter_only() or owner_net < 0:
			return {"visible": false}

	return {
		"visible": true,
		"card_name": str(card.card_name),
		"trigger": _trigger_label_for_card(card),
		"card": card,
	}


## 카드 trigger_type 또는 첫 bundle trigger 라벨.
func _trigger_label_for_card(card: Node) -> String:
	if card == null or not card.card_data:
		return ""
	var trigger_type := str(card.card_data.trigger_type)
	if not trigger_type.is_empty():
		return trigger_type
	if not card.card_data.effects.is_empty():
		return str(card.card_data.effects[0].trigger)
	return ""


## notice 우선, 없으면 presenter window 카드.
func _get_primary_window_card() -> Node2D:
	if _notice_card and is_instance_valid(_notice_card):
		return _notice_card
	return _get_opponent_window_card()


## presenter window 카드 중 상대 우선, 없으면 첫 유효 카드.
func _get_opponent_window_card() -> Node2D:
	for card in _presenter_window_cards:
		if is_instance_valid(card) and card.owner_side == GameConstants.Side.OPPONENT:
			return card
	for card in _presenter_window_cards:
		if is_instance_valid(card):
			return card
	return null


## DECISION_REQUEST payload에서 notice용 카드 해석. DecisionBroker가 호출.
func _resolve_notice_card_from_payload(kind: String, payload: Dictionary) -> Node2D:
	match kind:
		NetworkConstants.EFFECT_KIND_CONFIRM:
			return _find_card_by_uuid(int(payload.get("cardUuid", 0)))
		NetworkConstants.EFFECT_KIND_PRIORITY:
			var uuids: Array = payload.get("cardUuids", [])
			if not uuids.is_empty():
				return _find_card_by_uuid(int(uuids[0]))
		NetworkConstants.EFFECT_KIND_SELECT_TARGETS, NetworkConstants.EFFECT_KIND_SELECT_SLOTS:
			return _find_card_by_uuid(int(payload.get("sourceUuid", 0)))
	return null


## GameUILayer turn indicator 갱신.
func _notify_turn_indicators() -> void:
	var ui := _get_game_ui()
	if ui and ui.has_method("refresh_turn_indicators"):
		ui.refresh_turn_indicators()


## 카드 배열 → network_uuid 배열. broker/window payload용.
func _card_uuids(cards: Array) -> Array:
	var uuids: Array = []
	for card in cards:
		if is_instance_valid(card):
			uuids.append(int(card.network_uuid))
	return uuids


## 카드 배열 → {uuid,cardId,name,rarity} entries. MP SELECT payload용.
func _card_entries(cards: Array) -> Array:
	var entries: Array = []
	for card in cards:
		if not is_instance_valid(card):
			continue
		var rarity := CardRarity.Tier.N
		var raw: Variant = card.get("instance_rarity")
		if raw != null:
			rarity = clampi(int(raw), CardRarity.Tier.N, CardRarity.Tier.UR)
		var cid := 0
		var cd: CardData = card.get("card_data") as CardData
		if cd != null and int(cd.id) > 0:
			cid = int(cd.id)
		entries.append({
			"uuid": int(card.network_uuid),
			"cardId": cid,
			"name": String(card.card_name),
			"rarity": rarity,
		})
	return entries


## 후보 배열에서 uuid로 카드 검색.
func _find_card_in_candidates_by_uuid(candidates: Array, uuid: int) -> Node:
	if uuid <= 0:
		return null
	for card in candidates:
		if is_instance_valid(card) and int(card.network_uuid) == uuid:
			return card
	return null


## entries/uuids로 카드 해석. 없으면 reveal_select 스폰. cardId 우선.
func _resolve_cards_from_entries(entries: Array, uuids_fallback: Array, local_side: GameConstants.Side) -> Array:
	var cards: Array = []
	var seen: Dictionary = {}
	if not entries.is_empty():
		for entry in entries:
			if not entry is Dictionary:
				continue
			var uuid := int(entry.get("uuid", 0))
			var card_id := int(entry.get("cardId", 0))
			var card_name := String(entry.get("name", ""))
			var rarity := int(entry.get("rarity", CardRarity.Tier.N))
			var card := _find_card_by_uuid(uuid)
			if card == null and uuid > 0:
				card = _spawn_reveal_select_card(uuid, card_name, local_side, rarity, card_id)
			if card and not seen.has(uuid):
				seen[uuid] = true
				cards.append(card)
		return cards
	for uuid_v in uuids_fallback:
		var uuid := int(uuid_v)
		var card := _find_card_by_uuid(uuid)
		if card and not seen.has(uuid):
			seen[uuid] = true
			cards.append(card)
	return cards


## MP SELECT용 일시 reveal_select 카드 스폰. 왜: 덱탑 등 아직 hand/field에 없는 노드 참조.
## card_id > 0이면 spawn_card_by_id 우선, 없으면 spawn_card_by_name.
func _spawn_reveal_select_card(
	uuid: int,
	card_name: String,
	local_side: GameConstants.Side,
	rarity: int = CardRarity.Tier.N,
	card_id: int = 0
) -> Node:
	var pm := _phase_manager()
	if pm == null or uuid <= 0:
		return null
	var deck: DeckZone = (
		pm.player_deck if local_side == GameConstants.Side.PLAYER else pm.opponent_deck
	)
	var reveal := local_side == GameConstants.Side.PLAYER
	var card: Node2D = null
	if card_id > 0:
		card = deck.spawn_card_by_id(card_id, reveal, uuid, rarity)
	elif not card_name.is_empty():
		card = deck.spawn_card_by_name(card_name, reveal, uuid, rarity)
	if card == null:
		return null
	card.owner_side = local_side
	card.set("zone", EffectTypes.Location.DECK)
	card.visible = false
	CardHelpers.disable_interaction(card)
	if context:
		context.register_reveal_select_card(card)
	return card


## Presenter: EFFECT_WINDOW_START — WindowCoordinator 위임 (발동 FX await).
func present_window_start(event: Dictionary) -> void:
	if _window_coordinator:
		await _window_coordinator.present_window_start(event)


## Presenter: EFFECT_WINDOW_END — WindowCoordinator 위임.
func present_window_end(_event: Dictionary) -> void:
	if _window_coordinator:
		_window_coordinator.present_window_end(_event)


## Presenter: EFFECT_RESULT changes 적용 후 LP/라인 파워 UI를 공개 API로 동기화한다.
func apply_result_changes(changes: Array, window_id: int = 0) -> void:
	if _change_applier == null:
		_change_applier = EffectChangeApplier.new()
		_change_applier.setup(context)
	await _change_applier.apply_changes(changes, _phase_manager(), window_id)
	var pm := _phase_manager()
	if pm and pm.has_method("refresh_match_ui"):
		pm.refresh_match_ui()


## PhaseManager uuid 조회로 카드 찾기. DecisionBroker·window present가 사용.
func _find_card_by_uuid(uuid: int) -> Node2D:
	var pm := _phase_manager()
	if pm and pm.has_method("_find_card_by_uuid"):
		return pm._find_card_by_uuid(uuid)
	return null


## recorder end → EFFECT_RESULT broadcast. authority + mp_effects만.
func _flush_recorded_changes() -> void:
	if not _is_mp_effects() or not is_logic_authority():
		return
	if not _change_recorder.is_recording():
		return
	var session := _session()
	_change_recorder.record_zone_snapshot(
		session.local_side_to_network(GameConstants.Side.PLAYER),
		context.player_deck
	)
	_change_recorder.record_zone_snapshot(
		session.local_side_to_network(GameConstants.Side.OPPONENT),
		context.opponent_deck
	)
	var changes := _change_recorder.end()
	if changes.is_empty():
		return
	var pm := _phase_manager()
	if pm and pm.has_method("broadcast_effect_result"):
		pm.broadcast_effect_result(_current_window_id, changes)


## confirm/시트 픽 직후 클라에 ActivationFx를 보낸다. EVENT는 EFFECT_RESULT, op=ACTIVATE.
func broadcast_activation_fx(card: Node, trigger: String) -> void:
	if not _is_mp_effects() or not is_logic_authority():
		return
	if card == null or not is_instance_valid(card):
		return
	var uuid := int(card.get("network_uuid"))
	if uuid <= 0:
		return
	if _change_recorder.is_recording():
		_change_recorder.record_activate(uuid, trigger)
		return
	_change_recorder.begin()
	_change_recorder.record_activate(uuid, trigger)
	_flush_recorded_changes()


## MP 변이 스텝을 recorder로 감싼다. PipelineRunner·레거시 bundle이 호출.
## 왜: authority만 begin/flush → EFFECT_RESULT. presenter·비MP는 callable만 실행.
func run_recorded_action(action_callable: Callable) -> void:
	if not is_logic_authority():
		await action_callable.call()
		return
	_change_recorder.begin()
	await action_callable.call()
	_flush_recorded_changes()


## Dedicated INTENT 가드용 스냅샷. DecisionBroker에 위임 (S4 계약 유지 / S5).
func get_decision_gate_state() -> Dictionary:
	if _decision_broker == null:
		return {"waiting": false, "owner_net_side": -1}
	return _decision_broker.get_decision_gate_state()


## Session→PM 경로 INTENT 수신. broker pending에 위임 (late → silent drop).
func deliver_effect_decision(intent: Dictionary) -> void:
	if _decision_broker:
		_decision_broker.deliver_effect_decision(intent)


## forfeit 시 원격 결정 await를 취소 응답으로 깨뜨린다.
func abort_pending_decisions() -> void:
	if _decision_broker:
		_decision_broker.abort_pending_decisions()
	_notice_card = null
	_notify_turn_indicators()


## EFFECT_DECISION_REQUEST → broker (local owner UI / notice). PM이 await.
func handle_decision_request(event: Dictionary) -> void:
	if _decision_broker:
		await _decision_broker.handle_decision_request(event)


## 파이프라인 confirm. broker.await_player_decision(CONFIRM) 위임.
func await_effect_confirm(card: Node) -> bool:
	if _skip_effect_confirm:
		return true
	return bool(await _decision_broker.await_player_decision(
		NetworkConstants.EFFECT_KIND_CONFIRM,
		card,
		{"cardUuid": int(card.network_uuid), "cardName": String(card.card_name)}
	))


## Optional mid-pipeline yes/no (e.g. Elina stack+draw). Synced over MP like CONFIRM.
func await_choice_dialog(
	card: Node,
	title: String,
	message: String,
	confirm_text: String = "예",
	cancel_text: String = "아니오"
) -> bool:
	return bool(await _decision_broker.await_player_decision(
		NetworkConstants.EFFECT_KIND_CONFIRM,
		card,
		{
			"cardUuid": int(card.network_uuid) if card else 0,
			"cardName": String(card.card_name) if card else "",
			"choiceDialog": true,
			"title": title,
			"message": message,
			"confirmText": confirm_text,
			"cancelText": cancel_text,
		}
	))


## SPD 동률 우선권 팝업. broker PRIORITY 위임.
func await_priority_decision(card: Node, group_cards: Array) -> bool:
	return bool(await _decision_broker.await_player_decision(
		NetworkConstants.EFFECT_KIND_PRIORITY,
		card,
		{"cardUuids": _card_uuids(group_cards), "spd": int(card.stat_spd)}
	))


## 대상 카드 선택. hint/entries 조립 후 broker SELECT_TARGETS 위임.
func await_target_decision(source: Node, candidates: Array, count: int, hint: Dictionary = {}) -> Array:
	var resolved_hint := (
		_selection_presenter.resolve_selection_hint(candidates, hint)
		if _selection_presenter
		else hint
	)
	var candidate_uuids: Array = _card_uuids(candidates)
	var display_uuids: Array = resolved_hint.get("displayUuids", candidate_uuids)
	var display_cards: Array = []
	for uuid_v in display_uuids:
		var found := _find_card_in_candidates_by_uuid(candidates, int(uuid_v))
		if found:
			display_cards.append(found)
	if display_cards.is_empty():
		display_cards = candidates
	var payload := {
		"sourceUuid": int(source.network_uuid),
		"candidateUuids": candidate_uuids,
		"selectableUuids": resolved_hint.get("selectableUuids", candidate_uuids),
		"displayUuids": display_uuids,
		"candidateEntries": _card_entries(candidates),
		"displayEntries": _card_entries(display_cards),
		"count": count,
		"targetLocation": resolved_hint.get("targetLocation", -1),
		"ownerSide": int(_net_side_for_card(source)),
	}
	if resolved_hint.has("variableMaxCount"):
		payload["variableMaxCount"] = int(resolved_hint["variableMaxCount"])
	var result = await _decision_broker.await_player_decision(
		NetworkConstants.EFFECT_KIND_SELECT_TARGETS,
		source,
		payload,
		candidates,
		count
	)
	return result if result is Array else []


## 슬롯 선택. network slot payload 조립 후 broker SELECT_SLOTS 위임.
func await_slot_decision(source: Node, candidates: Array, count: int) -> Array:
	var slots_payload: Array = []
	var pm := _phase_manager()
	for slot in candidates:
		if slot is CardSlot and pm and pm.has_method("encode_field_slot_for_network"):
			slots_payload.append(pm.encode_field_slot_for_network(slot))
	var result = await _decision_broker.await_player_decision(
		NetworkConstants.EFFECT_KIND_SELECT_SLOTS,
		source,
		{"sourceUuid": int(source.network_uuid), "slots": slots_payload, "count": count},
		candidates,
		count
	)
	return result if result is Array else []


## net_side가 로컬 입력 seat인지. Context/UI 폴링용 공개 래퍼.
func is_decision_owner_for_net_side(net_side: int) -> bool:
	return _is_local_decision_owner(net_side)


## OPEN 창 오케스트레이션. WindowCoordinator 위임.
func run_open_window(cards: Array) -> void:
	if _window_coordinator:
		await _window_coordinator.run_open_window(cards)


## BIND/TRASH 교차 웨이브. WindowCoordinator 위임.
func run_bind_trash_waves() -> void:
	if _window_coordinator:
		await _window_coordinator.run_bind_trash_waves()


## LIFE 창. WindowCoordinator 위임.
func run_life_check(loser_side: GameConstants.Side, card_node: Node) -> void:
	if _window_coordinator:
		await _window_coordinator.run_life_check(loser_side, card_node)


## 로컬 confirm UI. DecisionBroker·remote REQUEST 콜백. SelectionPresenter 위임.
func ask_effect_confirm(card: Node) -> bool:
	if _skip_effect_confirm:
		return true
	if _selection_presenter == null:
		return false
	return await _selection_presenter.ask_effect_confirm(card)


## 싱글: TargetListSheet에서 발동할 카드 선택. 취소 시 null.
## MP: SELECT_TARGETS + activationPick (빈 배열=취소).
func await_activation_pick(cards: Array, title: String = "효과 발동") -> Node:
	var valid: Array = []
	for card in cards:
		if is_instance_valid(card):
			valid.append(card)
	if valid.is_empty():
		return null

	if _is_mp_effects():
		var source: Node = valid[0]
		var candidate_uuids: Array = _card_uuids(valid)
		var picked_variant: Variant = await _decision_broker.await_player_decision(
			NetworkConstants.EFFECT_KIND_SELECT_TARGETS,
			source,
			{
				"sourceUuid": int(source.network_uuid),
				"candidateUuids": candidate_uuids,
				"selectableUuids": candidate_uuids,
				"displayUuids": candidate_uuids,
				"candidateEntries": _card_entries(valid),
				"displayEntries": _card_entries(valid),
				"count": 1,
				"activationPick": true,
				"title": title,
				"ownerSide": int(_net_side_for_card(source)),
			},
			valid,
			1
		)
		if picked_variant is Array:
			var arr: Array = picked_variant
			if arr.is_empty():
				return null
			return arr[0]
		return null

	if _selection_presenter == null:
		return null
	return await _selection_presenter.ask_activation_pick(cards, title)


## 로컬 priority UI. COM(싱글 선공)은 UI 없이 우선권 수락(EffectContext와 동일).
func ask_priority_popup(card: Node) -> bool:
	if card != null and context != null and context.is_com_side(card.owner_side):
		return true
	if _selection_presenter == null:
		return false
	return await _selection_presenter.ask_priority_popup(card)


## 로컬 choice dialog UI. SelectionPresenter 위임.
func ask_choice_dialog(
	title: String,
	message: String,
	confirm_text: String = "예",
	cancel_text: String = "아니오"
) -> bool:
	if _selection_presenter == null:
		return false
	return await _selection_presenter.ask_choice_dialog(title, message, confirm_text, cancel_text)


## 로컬 sheet만 (MP REQUEST/로컬 owner UI). await_activation_pick 의 MP 분기를 타지 않음.
func ask_activation_pick_local(cards: Array, title: String = "효과 발동") -> Node:
	if _selection_presenter == null:
		return null
	return await _selection_presenter.ask_activation_pick(cards, title)


## 대상 카드 선택 UI. DecisionBroker 콜백. SelectionPresenter 위임.
func select_cards(
	candidates: Array,
	count: int,
	source: Node,
	selection_hint: Dictionary = {},
	display_override: Array = []
) -> Array:
	if _selection_presenter == null:
		return []
	return await _selection_presenter.select_cards(
		candidates, count, source, selection_hint, display_override
	)


## 슬롯 선택 UI. DecisionBroker 콜백. SelectionPresenter 위임.
func select_slots(candidates: Array, count: int, source: Node) -> Array:
	if _selection_presenter == null:
		return []
	return await _selection_presenter.select_slots(candidates, count, source)


## 묘지 선택 스냅샷. Context/step → SelectionPresenter.
func show_graveyard_selection(display_cards: Array, selectable_cards: Array = []) -> void:
	if _selection_presenter:
		_selection_presenter.show_graveyard_selection(display_cards, selectable_cards)


## 묘지 선택/browse 해제. SelectionPresenter 위임.
func hide_graveyard_panel() -> void:
	if _selection_presenter:
		_selection_presenter.hide_graveyard_panel()


## 필드 카드 클릭. DeckZone → SelectionPresenter.
func on_card_clicked(card: Node) -> void:
	if _selection_presenter:
		_selection_presenter.on_card_clicked(card)


## 필드/슬롯 선택 raycast. SelectionPresenter가 처리하면 handled.
func _input(event: InputEvent) -> void:
	if _selection_presenter and _selection_presenter.handle_input(event):
		get_viewport().set_input_as_handled()


## 필드 타깃 unhandled 보완. SelectionPresenter 위임.
func _unhandled_input(event: InputEvent) -> void:
	if _selection_presenter and _selection_presenter.handle_unhandled_input(event):
		get_viewport().set_input_as_handled()


## 묘지 browse 뷰. SelectionPresenter 위임.
func show_graveyard_view(side: GameConstants.Side) -> void:
	if _selection_presenter:
		_selection_presenter.show_graveyard_view(side)


## banish browse 뷰. SelectionPresenter 위임.
func show_banish_view(side: GameConstants.Side) -> void:
	if _selection_presenter:
		_selection_presenter.show_banish_view(side)


## 효과 busy 플래그·gate/notice 리셋·UI 신호. 창 시작/종료·presenter window에서 호출.
func _set_busy(busy: bool) -> void:
	is_busy = busy
	if not busy:
		if _decision_broker:
			_decision_broker.clear_gate()
		_notice_card = null
		_presenter_window_cards.clear()
	emit_signal("effect_busy_changed", busy)
	_notify_turn_indicators()


## OPEN/TRASH/BIND 트리거 가능 여부 (legacy + pipeline). WindowCoordinator가 호출.
func _check_trigger(card: Node, trigger: String) -> bool:
	if trigger == "OPEN" and _is_effect_set_blocked(card):
		return false
	var data: CardData = card.card_data
	if data == null:
		return false
	if _pipeline_runner.card_uses_pipelines(card):
		return _check_pipeline_trigger(card, trigger)
	if data.effects.is_empty():
		return false
	if data.oncePerTurn:
		var hist: Dictionary = context.turn_effect_history[card.owner_side]
		if hist.has(data.id):
			return false
	match trigger:
		"OPEN":
			if data.effects[0].trigger != "OPEN":
				return false
		"TRASH":
			var has_trigger := false
			for bundle in data.effects:
				if bundle.trigger == "TRASH" or bundle.trigger == "LIFE":
					has_trigger = true
					break
			if not has_trigger:
				return false
		"BIND":
			var has_bind := false
			for bundle in data.effects:
				if bundle.trigger == "BIND":
					has_bind = true
					break
			if not has_bind:
				return false
		_:
			return false
	for bundle in data.effects:
		if bundle.trigger != trigger:
			if trigger == "TRASH" and bundle.trigger == "LIFE":
				pass
			else:
				continue
		if bundle.condition and not bundle.condition.isMet(card, context.current_phase(), bundle.cost, context):
			return false
		if not _bundle_supply_met(card, bundle, trigger):
			return false
	return true


## effect_set 카드는 OPEN 차단.
func _is_effect_set_blocked(card: Node) -> bool:
	return card != null and bool(card.get("effect_set"))


## pipeline 카드 트리거 가능 여부.
func _check_pipeline_trigger(card: Node, trigger: String) -> bool:
	if trigger == "OPEN" and _is_effect_set_blocked(card):
		return false
	var data: CardData = card.card_data
	if data.oncePerTurn:
		var hist: Dictionary = context.turn_effect_history[card.owner_side]
		if hist.has(data.id):
			return false
	if not _pipeline_runner.has_trigger_pipeline(card, trigger):
		return false
	return _pipeline_runner.can_trigger(card, trigger)


## legacy bundle supply(deck trash/draw) 충족 여부.
func _bundle_supply_met(card: Node, bundle: EffectBundle, trigger: String) -> bool:
	if bundle.action == null:
		return true
	if trigger == "TRASH" and bundle.trigger not in ["TRASH", "LIFE"]:
		return true
	if trigger == "BIND" and bundle.trigger != "BIND":
		return true
	if trigger == "OPEN" and bundle.trigger != "OPEN":
		return true
	if bundle.action is TrashDeck:
		return context.can_supply(card.owner_side, bundle.value)
	if bundle.action is Draw:
		return context.can_supply(card.owner_side, bundle.value)
	if bundle.action is TrashOpponentDeck:
		return context.can_supply(GameConstants.opposite_side(card.owner_side), bundle.value)
	return true


## 카드 효과 실행 (pipeline 또는 legacy bundle). WindowCoordinator 웨이브가 호출.
## skip_confirm=true: sheet에서 이미 발동 확정한 경우 중앙 confirm 생략.
func _trigger_card_effects(card: Node, trigger: String, skip_confirm: bool = false) -> void:
	var data: CardData = card.card_data
	if data == null:
		return
	_skip_effect_confirm = skip_confirm
	if _pipeline_runner.card_uses_pipelines(card):
		context.reset_pipeline_state()
		await _pipeline_runner.run_card(card, trigger, skip_confirm)
		_skip_effect_confirm = false
		return
	var phase := context.current_phase()
	var allowed := false
	var is_active := false
	var execution_context: Array = []

	for bundle in data.effects:
		if bundle.trigger != trigger:
			if trigger == "TRASH" and bundle.trigger == "LIFE":
				pass
			else:
				continue
		if bundle.condition and not bundle.condition.isMet(card, phase, bundle.cost, context):
			_skip_effect_confirm = false
			return
		if not _bundle_supply_met(card, bundle, trigger):
			_skip_effect_confirm = false
			return
		if not is_active:
			allowed = true if skip_confirm else await await_effect_confirm(card)
			is_active = true
			# 발동 연출: confirm(또는 sheet skip) 직후 · 액션 전 (필드/존).
			if allowed:
				if has_method("broadcast_activation_fx"):
					broadcast_activation_fx(card, trigger)
				await ActivationFx.await_play_for_source(card, trigger)
		if not allowed:
			_skip_effect_confirm = false
			return
		if data.oncePerTurn:
			context.turn_effect_history[card.owner_side][data.id] = true
		context.current_effect_trigger = bundle.trigger
		context.current_effect_all_line = bundle.allLine
		context.current_effect_action = bundle.action
		var targets: Array = []
		if bundle.targeter:
			targets = await bundle.targeter.getTarget(
				card,
				phase,
				bundle.targetNum,
				bundle.target,
				bundle.targetLocation,
				bundle.cost,
				execution_context,
				context
			)
			execution_context = targets.duplicate()
		if bundle.action:
			if bundle.targeter and targets.is_empty():
				continue
			await run_recorded_action(func() -> void:
				await bundle.action.execute(card, targets, bundle.value, context)
			)
			var milled: Array = context.take_milled_cards()
			for milled_card in milled:
				if milled_card not in execution_context:
					execution_context.append(milled_card)
	_skip_effect_confirm = false
