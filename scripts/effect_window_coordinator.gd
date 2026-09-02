## OPEN/BIND/TRASH/LIFE 효과 창 오케스트레이션 (EffectManager Window 책임 분리 — S6 / B-EM-01).
## EM facade가 setup에서 생성·주입하고 공개 API를 위임한다. 카드 트리거·recording·busy는 host EM 콜백.
## network_constants 이벤트·intent 스키마는 변경하지 않는다.
## 왜 RefCounted: Node 트리 수명과 무관; await는 host의 process_frame·priority/confirm을 사용.
class_name EffectWindowCoordinator
extends RefCounted

## EffectManager 호스트 — busy·context·trigger·MP broadcast·priority 결정 접근.
## Node로 두는 이유: PipelineRunner/DecisionBroker와 같이 class_name 순환 참조를 피함.
var _host: Node


## EM.setup에서 호출. host는 busy/context/trigger/broadcast 제공자(EffectManager).
func setup(host: Node) -> void:
	_host = host


## OPEN 창: 후보 필터→우선권→카드 효과→bind/trash→deferred life. presenter-only면 no-op.
## 왜 busy를 창 전후에만 걸음: 파이프라인 중 입력을 막고, presenter는 present_window_*로 busy를 받음.
func run_open_window(cards: Array) -> void:
	if _host.is_presenter_only():
		return
	_host._set_busy(true)
	_begin_effect_window("OPEN", cards)
	_host.context.is_in_open_window = true
	_host.context.reset_open_relocate_flags()
	_host.context.reset_trash_wave()
	_host.context.reset_bind_wave()

	var queue: Array = _filter_open_candidates(cards)
	if _use_sheet_activation():
		await _resolve_spd_groups_with_sheet(queue, "OPEN")
	else:
		queue = await _sort_and_resolve_priority(queue)
		for card in queue:
			if not _is_card_on_field(card):
				continue
			if _host._is_effect_set_blocked(card):
				continue
			if not _host._check_trigger(card, "OPEN"):
				continue
			await _host._trigger_card_effects(card, "OPEN")

	_host.context.is_in_open_window = false
	_host.context.reset_open_relocate_flags()
	await run_bind_trash_waves()
	await _host.context.flush_deferred_life_checks()
	_end_effect_window()
	_host._set_busy(false)


## BIND·TRASH 웨이브를 교차 반복(최대 20). 둘 다 후보 없으면 종료. presenter-only면 no-op.
func run_bind_trash_waves() -> void:
	if _host.is_presenter_only():
		return
	var iteration := 0
	while iteration < 20:
		iteration += 1
		var had_bind := await _run_single_bind_wave()
		var had_trash := await _run_single_trash_wave()
		if not had_bind and not had_trash:
			break


## LIFE 트리거 창. 패배 side LP가 더 적을 때만 restore를 recorded action으로 적용.
func run_life_check(loser_side: GameConstants.Side, card_node: Node) -> void:
	if _host.is_presenter_only():
		return
	_host._set_busy(true)
	if _host._is_mp_effects() and card_node:
		_begin_effect_window("LIFE", [card_node])
	_host.context.is_life_check = true
	if card_node and card_node.card_data:
		var has_life := false
		for bundle in card_node.card_data.effects:
			if bundle.trigger == "LIFE":
				has_life = true
				break
		if has_life:
			var loser_deck: DeckZone = _host.context.get_deck(loser_side)
			var winner_deck: DeckZone = _host.context.get_deck(GameConstants.opposite_side(loser_side))
			if loser_deck.get_life_count() < winner_deck.get_life_count():
				await _host.run_recorded_action(func() -> void:
					_host.context.apply_life_restore(loser_side)
				)
	_host.context.is_life_check = false
	if _host._is_mp_effects():
		_end_effect_window()
	_host._set_busy(false)


## Presenter: EFFECT_WINDOW_START 수신. 카드 reveal + match UI 갱신 + PASSIVE 스케줄.
## 왜: presenter는 run_open_window를 안 탐 — 공개 직후 PASSIVE를 권위와 같이 재계산.
## 발동 FX는 여기가 아님(오픈 전원에 붙으면 무효과 카드에도 재생). confirm/시트 픽 후 ACTIVATE op.
func present_window_start(event: Dictionary) -> void:
	_host._set_busy(true)
	_host._presenter_window_cards.clear()
	var uuids: Array = event.get("cardUuids", [])
	for uuid in uuids:
		var card: Node2D = _host._find_card_by_uuid(int(uuid))
		if card:
			_host._presenter_window_cards.append(card)
			if card.has_method("reveal"):
				card.reveal()
	var pm: Node = _host._phase_manager()
	if pm and pm.has_method("refresh_match_ui"):
		pm.refresh_match_ui()
	_host._notify_turn_indicators()
	_host.schedule_passive_refresh()


## Presenter: EFFECT_WINDOW_END. busy 해제 후 PASSIVE를 한 번 더 스케줄한다.
## 왜 busy를 여기서 끔: presenter는 run_open_window busy 경로를 안 탐 — present_window_start가 켠 busy를 창 종료로 해제.
func present_window_end(_event: Dictionary) -> void:
	_host._set_busy(false)
	# OPEN RESULT·토큰 SPAWN 반영 후 한 번 더 (창 중 판정이 어긋난 경우)
	_host.schedule_passive_refresh()


## windowId를 증가시키고 authority면 EFFECT_WINDOW_START broadcast. DecisionBroker가 host._current_window_id를 읽음.
func _begin_effect_window(trigger: String, cards: Array = []) -> int:
	_host._current_window_id += 1
	if _host._is_mp_effects() and _host.is_logic_authority():
		var pm: Node = _host._phase_manager()
		if pm and pm.has_method("broadcast_effect_window_start"):
			pm.broadcast_effect_window_start(
				_host._current_window_id, trigger, _host._card_uuids(cards)
			)
	return _host._current_window_id


## authority면 EFFECT_WINDOW_END broadcast. presenter-only는 busy를 여기서 해제(권위 OPEN 경로와 비대칭).
func _end_effect_window() -> void:
	if _host._is_mp_effects() and _host.is_logic_authority():
		var pm: Node = _host._phase_manager()
		if pm and pm.has_method("broadcast_effect_window_end"):
			pm.broadcast_effect_window_end(_host._current_window_id)
	if _host.is_presenter_only():
		_host._set_busy(false)


## BIND 후보 1웨이브. MP면 웨이브마다 window begin/end. 후보 없으면 false.
func _run_single_bind_wave() -> bool:
	_host.context.reset_bind_wave()
	var candidates := _collect_bind_candidates()
	if candidates.is_empty():
		return false
	if _host._is_mp_effects():
		_begin_effect_window("BIND", candidates)
	if _use_sheet_activation():
		await _resolve_spd_groups_with_sheet(candidates, "BIND")
	else:
		candidates = await _sort_and_resolve_priority(candidates)
		for card in candidates:
			if not _is_card_in_banishzone(card):
				continue
			if _host.context.was_bind_processed_this_wave(card.instance_id):
				continue
			_host.context.mark_bind_processed(card.instance_id)
			if not _host._check_trigger(card, "BIND"):
				continue
			await _host._trigger_card_effects(card, "BIND")
	if _host._is_mp_effects():
		_end_effect_window()
	return true


## TRASH 후보 1웨이브. MP면 웨이브마다 window begin/end. 후보 없으면 false.
func _run_single_trash_wave() -> bool:
	_host.context.reset_trash_wave()
	var candidates := _collect_trash_candidates()
	if candidates.is_empty():
		return false
	if _host._is_mp_effects():
		_begin_effect_window("TRASH", candidates)
	if _use_sheet_activation():
		await _resolve_spd_groups_with_sheet(candidates, "TRASH")
	else:
		candidates = await _sort_and_resolve_priority(candidates)
		for card in candidates:
			if not _is_card_in_graveyard(card):
				continue
			if _host.context.was_trash_processed_this_wave(card.instance_id):
				continue
			_host.context.mark_trash_processed(card.instance_id)
			if not _host._check_trigger(card, "TRASH"):
				continue
			await _host._trigger_card_effects(card, "TRASH")
	if _host._is_mp_effects():
		_end_effect_window()
	return true


## OPEN 트리거를 통과한 카드만 큐에 남긴다.
func _filter_open_candidates(cards: Array) -> Array:
	var result: Array = []
	for card in cards:
		if _host._check_trigger(card, "OPEN"):
			result.append(card)
	return result


## context drain 후 pipeline/legacy BIND 트리거가 있는 카드만 수집.
func _collect_bind_candidates() -> Array:
	var batch: Array = _host.context.drain_bind_candidates()
	var result: Array = []
	var runner: EffectPipelineRunner = _host._pipeline_runner
	for card in batch:
		if not is_instance_valid(card):
			continue
		if not card.card_data:
			continue
		if runner.card_uses_pipelines(card):
			if runner.has_trigger_pipeline(card, "BIND"):
				result.append(card)
			continue
		for bundle in card.card_data.effects:
			if bundle.trigger == "BIND":
				result.append(card)
				break
	return result


## context drain 후 pipeline/legacy TRASH 트리거가 있는 카드만 수집.
func _collect_trash_candidates() -> Array:
	var batch: Array = _host.context.drain_trash_candidates()
	var result: Array = []
	var runner: EffectPipelineRunner = _host._pipeline_runner
	for card in batch:
		if not is_instance_valid(card):
			continue
		if not card.card_data:
			continue
		if runner.card_uses_pipelines(card):
			if runner.has_trigger_pipeline(card, "TRASH"):
				result.append(card)
			continue
		for bundle in card.card_data.effects:
			if bundle.trigger == "TRASH":
				result.append(card)
				break
	return result


## 싱글·MP 모두 sheet 발동. MP는 SELECT_TARGETS(activationPick)로 동기화.
func _use_sheet_activation() -> bool:
	return true


## SPD 오름차순 그룹별: 우선권 → 선후 교대 1장씩 sheet/랜덤 발동.
func _resolve_spd_groups_with_sheet(cards: Array, trigger: String) -> void:
	if cards.is_empty():
		return
	var groups: Dictionary = {}
	for card in cards:
		if not is_instance_valid(card):
			continue
		var spd: int = int(card.stat_spd) if card.get("stat_spd") != null else 0
		if not groups.has(spd):
			groups[spd] = []
		groups[spd].append(card)
	var spd_keys: Array = groups.keys()
	spd_keys.sort()
	for spd in spd_keys:
		await _resolve_spd_group_with_sheet(groups[spd], trigger, int(spd))


## 한 SPD 그룹: side_order 교대로 1장씩 즉시 처리. 취소 시 해당 side 표시 후보 전부 제거(A1).
func _resolve_spd_group_with_sheet(group: Array, trigger: String, spd: int) -> void:
	var side_order: Array = await _side_order_for_group(group)
	if side_order.is_empty():
		return
	var remaining: Array = group.duplicate()
	while true:
		var progressed := false
		for side in side_order:
			var side_cards: Array = _filter_side_remaining(remaining, side, trigger)
			if side_cards.is_empty():
				continue
			progressed = true
			if _host.context.is_com_side(side):
				var pick: Node = side_cards[randi() % side_cards.size()]
				_erase_card(remaining, pick)
				await _trigger_picked_card(pick, trigger)
			else:
				var title := "%s 효과 발동 (SPD %d)" % [_trigger_label(trigger), spd]
				var pick: Node = await _host.await_activation_pick(side_cards, title)
				if pick == null:
					for c in side_cards:
						_erase_card(remaining, c)
						_mark_wave_processed_if_needed(c, trigger)
					continue
				_erase_card(remaining, pick)
				await _trigger_picked_card(pick, trigger)
		if not progressed:
			break
		# 효과 처리 후 존/조건 변화 반영
		remaining = _filter_still_eligible(remaining, trigger)
		if remaining.is_empty():
			break


## 동속 그룹의 선후 side 순서. 복수 side면 first_player 측에 우선권 결정권.
## 싱글 COM 선공: COM 카드로 물어 COM 자동 결정. MP: first_player seat UI/REQUEST.
func _side_order_for_group(group: Array) -> Array:
	var sides: Array = []
	var seen: Dictionary = {}
	var cards: Array = []
	for card in group:
		if not is_instance_valid(card):
			continue
		cards.append(card)
		var side: GameConstants.Side = card.owner_side
		var key := int(side)
		if not seen.has(key):
			seen[key] = true
			sides.append(side)

	if sides.size() <= 1:
		return sides

	var fp: GameConstants.Side = _host.context.first_player()
	var first_sides: Array = []
	var second_sides: Array = []
	for side in sides:
		if side == fp:
			first_sides.append(side)
		else:
			second_sides.append(side)
	if first_sides.is_empty() or second_sides.is_empty():
		return sides

	var priority_card: Node = cards[0]
	for card in cards:
		if card.owner_side == fp:
			priority_card = card
			break
	var wants_priority: bool = await _host.await_priority_decision(priority_card, cards)
	if wants_priority:
		return first_sides + second_sides
	return second_sides + first_sides


## remaining 중 해당 side·트리거 유효 카드만.
func _filter_side_remaining(remaining: Array, side: GameConstants.Side, trigger: String) -> Array:
	var result: Array = []
	for card in remaining:
		if not is_instance_valid(card):
			continue
		if card.owner_side != side:
			continue
		if not _is_card_eligible_for_trigger(card, trigger):
			continue
		result.append(card)
	return result


func _filter_still_eligible(remaining: Array, trigger: String) -> Array:
	var result: Array = []
	for card in remaining:
		if is_instance_valid(card) and _is_card_eligible_for_trigger(card, trigger):
			result.append(card)
	return result


func _is_card_eligible_for_trigger(card: Node, trigger: String) -> bool:
	match trigger:
		"OPEN":
			if not _is_card_on_field(card):
				return false
			if _host._is_effect_set_blocked(card):
				return false
			if _host.context.was_relocated_during_open(card):
				return false
			return _host._check_trigger(card, "OPEN")
		"BIND":
			if not _is_card_in_banishzone(card):
				return false
			if _host.context.was_bind_processed_this_wave(card.instance_id):
				return false
			return _host._check_trigger(card, "BIND")
		"TRASH":
			if not _is_card_in_graveyard(card):
				return false
			if _host.context.was_trash_processed_this_wave(card.instance_id):
				return false
			return _host._check_trigger(card, "TRASH")
		_:
			return false


func _trigger_picked_card(card: Node, trigger: String) -> void:
	if not is_instance_valid(card):
		return
	if not _is_card_eligible_for_trigger(card, trigger):
		return
	_mark_wave_processed_if_needed(card, trigger)
	await _host._trigger_card_effects(card, trigger, true)


func _mark_wave_processed_if_needed(card: Node, trigger: String) -> void:
	if not is_instance_valid(card):
		return
	match trigger:
		"BIND":
			if not _host.context.was_bind_processed_this_wave(card.instance_id):
				_host.context.mark_bind_processed(card.instance_id)
		"TRASH":
			if not _host.context.was_trash_processed_this_wave(card.instance_id):
				_host.context.mark_trash_processed(card.instance_id)


func _erase_card(arr: Array, card: Node) -> void:
	for i in range(arr.size() - 1, -1, -1):
		var other: Node = arr[i]
		if other == card:
			arr.remove_at(i)
			return
		if (
			is_instance_valid(other)
			and is_instance_valid(card)
			and other.get("instance_id") != null
			and card.get("instance_id") != null
			and other.instance_id == card.instance_id
		):
			arr.remove_at(i)
			return


func _trigger_label(trigger: String) -> String:
	match trigger:
		"OPEN":
			return "OPEN"
		"BIND":
			return "BIND"
		"TRASH":
			return "TRASH"
		_:
			return trigger


## SPD 오름차순·같은 SPD면 owner_side 오름차순.
func _sort_by_spd(cards: Array) -> Array:
	var sorted_cards := cards.duplicate()
	sorted_cards.sort_custom(func(a, b):
		var spd_a: int = a.stat_spd if a.get("stat_spd") != null else 0
		var spd_b: int = b.stat_spd if b.get("stat_spd") != null else 0
		if spd_a != spd_b:
			return spd_a < spd_b
		return int(a.owner_side) < int(b.owner_side)
	)
	return sorted_cards


## SPD 그룹별 우선권 해석. 동속·복수 side면 first_player 측에 결정권.
## 싱글 COM 선공: COM 자동. MP PvP: first_player seat 팝업/REQUEST.
func _sort_and_resolve_priority(cards: Array) -> Array:
	if cards.is_empty():
		return []
	var sorted_cards := _sort_by_spd(cards)
	var groups: Dictionary = {}
	for card in sorted_cards:
		var spd: int = card.stat_spd
		if not groups.has(spd):
			groups[spd] = []
		groups[spd].append(card)

	var result: Array = []
	var spd_keys: Array = groups.keys()
	spd_keys.sort()
	# 낮은 SPD부터 처리 (effect.txt · HANDOFF §3.31 B5). 동속만 우선권.
	for spd in spd_keys:
		var group: Array = groups[spd]
		var sides_present: Dictionary = {}
		for card in group:
			if is_instance_valid(card):
				sides_present[int(card.owner_side)] = true
		if sides_present.size() <= 1:
			result.append_array(group)
			continue

		var fp: GameConstants.Side = _host.context.first_player()
		var first_cards: Array = []
		var second_cards: Array = []
		for card in group:
			if not is_instance_valid(card):
				continue
			if card.owner_side == fp:
				first_cards.append(card)
			else:
				second_cards.append(card)
		if first_cards.is_empty() or second_cards.is_empty():
			result.append_array(group)
			continue

		var wants_priority: bool = await _host.await_priority_decision(first_cards[0], group)
		if wants_priority:
			result.append_array(first_cards)
			result.append_array(second_cards)
		else:
			result.append_array(second_cards)
			result.append_array(first_cards)
	return result


## 필드 슬롯에 올라간 카드인지.
func _is_card_on_field(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	return card.card_slot_card_is_in != null


## 묘지 존에 있는지.
func _is_card_in_graveyard(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	return card.zone == EffectTypes.Location.GRAVE


## banishzone에 있는지.
func _is_card_in_banishzone(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	return card.zone == EffectTypes.Location.BANISH
