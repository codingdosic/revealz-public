## 효과 선택·다이얼로그 UI (EffectManager Selection 책임 분리 — S6 / B-EM-02).
## EM facade가 setup에서 생성·주입. GameUILayer 연결·raycast·select/ask UI만 담당.
## DecisionBroker는 host EM의 select_*/ask_* 공개 API를 호출하고, EM이 여기로 위임한다.
## 왜 RefCounted: 선택 상태 머신; await/input은 host Node의 process_frame·_input 경유.
class_name EffectSelectionPresenter
extends RefCounted

## EffectManager 호스트 — context·MP·await_target/slot·tree 접근.
var _host: Node

## GameUILayer 참조. bind_game_ui로 주입. null이면 headless → dialog cancel.
var _game_ui: Node

## 다이얼로그/타깃 선택 minimize 플래그. EM 공개 var와 동기화(호환).
var is_effect_dialog_minimized: bool = false
var is_target_select_minimized: bool = false

## 카드/슬롯 선택 상태 머신.
var _select_mode: bool = false
var _slot_select_mode: bool = false
var _graveyard_select_mode: bool = false
var _field_select_mode: bool = false
var _select_candidates: Array = []
var _slot_candidates: Array = []
var _select_resolved: Array = []
var _select_pending: Array = []
var _slot_resolved: Array = []
var _slot_pending: Array = []
var _select_needed: int = 0
var _select_min: int = 0
var _select_variable_mode: bool = false
var _select_source: Node = null
var _select_waiting: bool = false
var _graveyard_display_cards: Array = []
var _graveyard_selectable_cards: Array = []

## 싱글 효과 발동 sheet 선택 상태 (TargetListSheet + 취소).
var _activation_waiting: bool = false
var _activation_candidates: Array = []
var _activation_pending: Node = null
var _activation_result: Node = null


## EM.setup에서 호출. host는 await_*/MP·context·tree 제공자(EffectManager).
func setup(host: Node) -> void:
	_host = host


## GameUILayer 바인딩 + 타깃/필드 선택 시그널 연결. finish_setup → EM.bind_game_ui 경로.
func bind_game_ui(game_ui: Node) -> void:
	_game_ui = game_ui
	if _game_ui:
		_game_ui.connect_target_select_card(_on_target_select_card_pressed)
		_game_ui.connect_target_select_confirmed(_on_target_select_confirmed)
		_game_ui.connect_target_select_minimized(_on_target_select_minimized)
		if _game_ui.has_method("connect_target_select_canceled"):
			_game_ui.connect_target_select_canceled(_on_target_select_canceled)
		_game_ui.connect_field_target_confirmed(_on_target_select_confirmed)
		_game_ui.connect_field_target_minimized(_on_target_select_minimized)


## GameUILayer 또는 씬 상대 경로 폴백. dialog/selection/turn indicator가 공유.
func get_game_ui() -> Node:
	if _game_ui:
		return _game_ui
	if _host:
		return _host.get_node_or_null("../GameUILayer")
	return null


## 카드 또는 슬롯 선택 중인지. InputManager 폴링.
func is_selecting() -> bool:
	return _select_mode or _slot_select_mode or _activation_waiting


## 싱글: TargetListSheet에서 발동할 카드 1장 선택. 확인 시 카드, 취소 시 null.
func ask_activation_pick(cards: Array, title: String = "효과 발동") -> Node:
	var valid: Array = []
	for card in cards:
		if is_instance_valid(card):
			valid.append(card)
	if valid.is_empty():
		return null

	_activation_waiting = true
	_activation_candidates = valid.duplicate()
	_activation_pending = null
	_activation_result = null
	is_target_select_minimized = false
	_sync_target_minimized_to_host()

	var ui := get_game_ui()
	if ui == null:
		push_warning("[Effect] no GameUI for activation sheet — cancel")
		_activation_waiting = false
		return null

	if ui.has_method("begin_activation_card_selection"):
		ui.begin_activation_card_selection(title, valid, valid)
	else:
		ui.begin_target_card_selection(title, valid, valid, 1, true)
	_update_activation_confirm_state()

	while _activation_waiting:
		await _host.get_tree().process_frame

	_clear_target_selection_visuals(valid)
	if ui:
		ui.end_target_card_selection()
	is_target_select_minimized = false
	_sync_target_minimized_to_host()
	_activation_candidates.clear()
	_activation_pending = null
	return _activation_result


## 존 browse를 카드 클릭으로 유지할지. 필드 선택 후보 클릭 시 true.
func should_keep_zone_browse_on_card_click(card: Node) -> bool:
	if not _select_mode or is_target_select_minimized:
		return false
	if _field_select_mode and card != null and is_instance_valid(card) and _is_select_candidate(card):
		return true
	return false


## 슬롯 선택 중이면 사이드바 차단.
func blocks_sidebar() -> bool:
	if _slot_select_mode:
		return true
	return false


## 선택 hint 정규화(targetLocation·uuids). await_target_decision payload 조립에도 사용.
func resolve_selection_hint(candidates: Array, hint: Dictionary = {}) -> Dictionary:
	return _resolve_selection_hint(candidates, hint)


## 효과 발동 confirm 다이얼로그. DecisionBroker/로컬 confirm 콜백.
func ask_effect_confirm(card: Node) -> bool:
	#return await _wait_effect_dialog(
		#"효과 발동",
		#"%s의 효과를 발동하시겠습니까?" % card.card_data.card_name,
		#"확인",
		#"취소"
	#)
	return await _wait_effect_dialog(
		"%s" % card.card_data.card_name,
		"카드의 효과를 발동하시겠습니까?" ,
		"확인",
		"취소"
	)


## SPD 동률 우선권 팝업.
func ask_priority_popup(card: Node) -> bool:
	return await _wait_effect_dialog(
		"우선권",
		"%s — SPD 동일. 먼저 발동하시겠습니까?" % card.card_data.card_name,
		"확인",
		"취소"
	)


## 임의 yes/no 다이얼로그 (title-first 오버로드).
func ask_choice_dialog(
	title: String,
	message: String,
	confirm_text: String = "예",
	cancel_text: String = "아니오"
) -> bool:
	return await _wait_effect_dialog(title, message, confirm_text, cancel_text)


## GameUILayer effect dialog를 띄우고 confirmed/canceled까지 await.
## 왜 UI 없으면 false: Headless authority는 confirm 불가 — 카드는 preflight/비대화 경로를 써야 함 (B-EM-12).
func _wait_effect_dialog(
	title: String, message: String, confirm_text: String, cancel_text: String
) -> bool:
	var ui := get_game_ui()
	if ui == null:
		push_warning("[Effect] no GameUI for dialog '%s' — cancel" % title)
		return false

	ui.hide_card_sidebar()
	var panel: PanelContainer = ui.get_effect_dialog()
	panel.configure(title, message, confirm_text, cancel_text)

	var state := {"done": false, "ok": false}

	var finish := func(ok: bool) -> void:
		if state["done"]:
			return
		state["ok"] = ok
		state["done"] = true
		is_effect_dialog_minimized = false
		_sync_dialog_minimized_to_host()
		panel.hide_dialog()
		ui.hide_effect_restore_button()

	var on_confirmed := func() -> void:
		finish.call(true)
	var on_canceled := func() -> void:
		finish.call(false)
	var on_minimized := func() -> void:
		is_effect_dialog_minimized = true
		_sync_dialog_minimized_to_host()
		panel.hide_dialog()
		ui.show_effect_restore_button(func() -> void:
			is_effect_dialog_minimized = false
			_sync_dialog_minimized_to_host()
			panel.show_dialog()
		)

	panel.confirmed.connect(on_confirmed, CONNECT_ONE_SHOT)
	panel.canceled.connect(on_canceled, CONNECT_ONE_SHOT)
	panel.minimized.connect(on_minimized)
	panel.show_dialog()

	while not state["done"]:
		await _host.get_tree().process_frame

	if panel.minimized.is_connected(on_minimized):
		panel.minimized.disconnect(on_minimized)

	panel.hide_dialog()
	ui.hide_effect_restore_button()
	var viewport := panel.get_viewport()
	if viewport:
		viewport.gui_release_focus()
	await _host.get_tree().process_frame

	return state["ok"]


## 대상 카드 선택. 원격 owner면 host.await_target_decision으로 MP REQUEST.
## 왜 authority가 remote owner용 grave hint를 주입: owner UI가 본 display/selectable과 일치해야 함.
func select_cards(
	candidates: Array,
	count: int,
	source: Node,
	selection_hint: Dictionary = {},
	display_override: Array = []
) -> Array:
	if candidates.is_empty():
		return []
	var hint := _resolve_selection_hint(candidates, selection_hint)
	_select_variable_mode = count == -2
	var max_count := candidates.size() if _select_variable_mode else count
	if _select_variable_mode and hint.has("variableMaxCount"):
		max_count = mini(max_count, maxi(0, int(hint["variableMaxCount"])))
	_select_min = 0 if _select_variable_mode else max_count
	if (
		_host._is_mp_effects()
		and _host.is_logic_authority()
		and not _host._is_local_decision_owner(_host._net_side_for_card(source))
	):
		if not _graveyard_display_cards.is_empty():
			hint["displayUuids"] = _host._card_uuids(_graveyard_display_cards)
			hint["selectableUuids"] = _host._card_uuids(
				_graveyard_selectable_cards if not _graveyard_selectable_cards.is_empty() else candidates
			)
			hint["targetLocation"] = EffectTypes.Location.GRAVE
		return await _host.await_target_decision(source, candidates, count, hint)
	if _host.context.is_com_side(source.owner_side):
		await _host.get_tree().create_timer(0.3).timeout
		var picked: Array = []
		var pool := candidates.duplicate()
		var pick_count := randi() % (pool.size() + 1) if _select_variable_mode else mini(max_count, pool.size())
		for i in range(pick_count):
			var idx := randi() % pool.size()
			picked.append(pool[idx])
			pool.remove_at(idx)
		_select_variable_mode = false
		return picked

	_select_mode = true
	_select_candidates = candidates.duplicate()
	_select_resolved = []
	_select_pending = []
	_select_needed = max_count if _select_variable_mode else mini(max_count, candidates.size())
	_select_source = source
	_select_waiting = _select_variable_mode or _select_needed > 0
	if not _select_waiting:
		_select_mode = false
		_select_variable_mode = false
		return []

	var display_cards := (
		display_override.duplicate()
		if not display_override.is_empty()
		else _graveyard_display_cards.duplicate()
		if not _graveyard_display_cards.is_empty()
		else _select_candidates.duplicate()
	)
	var selectable_cards := (
		_graveyard_selectable_cards.duplicate()
		if not _graveyard_selectable_cards.is_empty()
		else _select_candidates.duplicate()
	)
	var ui_mode := _resolve_selection_ui_mode(_select_candidates, hint)
	_field_select_mode = ui_mode == "field"
	if ui_mode == "graveyard" and _graveyard_display_cards.is_empty():
		show_graveyard_selection(display_cards, selectable_cards)
	var ui := get_game_ui()
	if ui:
		if _field_select_mode:
			_begin_field_target_selection(_select_candidates, _select_needed)
		else:
			ui.begin_target_card_selection(
				_selection_title_text(),
				display_cards,
				selectable_cards,
				_select_needed
			)
			_update_target_confirm_state()
	while _select_waiting:
		await _host.get_tree().process_frame
	if _field_select_mode:
		_end_field_target_selection(_select_candidates)
	else:
		_clear_target_selection_visuals(display_cards)
		if ui:
			ui.end_target_card_selection()
	_select_mode = false
	_field_select_mode = false
	_select_pending.clear()
	_graveyard_display_cards.clear()
	_graveyard_selectable_cards.clear()
	_graveyard_select_mode = false
	is_target_select_minimized = false
	_sync_target_minimized_to_host()
	_select_variable_mode = false
	return _select_resolved.duplicate()


## 슬롯 선택. 원격 owner면 host.await_slot_decision.
func select_slots(candidates: Array, count: int, source: Node) -> Array:
	if candidates.is_empty():
		return []
	if (
		_host._is_mp_effects()
		and _host.is_logic_authority()
		and not _host._is_local_decision_owner(_host._net_side_for_card(source))
	):
		return await _host.await_slot_decision(source, candidates, count)
	if _host.context.is_com_side(source.owner_side):
		await _host.get_tree().create_timer(0.3).timeout
		var picked: Array = []
		var pool := candidates.duplicate()
		for i in range(mini(count, pool.size())):
			var idx := randi() % pool.size()
			picked.append(pool[idx])
			pool.remove_at(idx)
		return picked

	_slot_select_mode = true
	_slot_candidates = candidates.duplicate()
	_slot_resolved = []
	_slot_pending = []
	_select_needed = mini(count, candidates.size())
	_select_source = source
	_select_waiting = _select_needed > 0
	if _select_needed <= 0:
		_slot_select_mode = false
		return []
	_begin_slot_selection(_slot_candidates, _select_needed, source)
	while _select_waiting:
		await _host.get_tree().process_frame
	_end_slot_selection(_slot_candidates)
	_slot_select_mode = false
	_slot_pending.clear()
	is_target_select_minimized = false
	_sync_target_minimized_to_host()
	return _slot_resolved.duplicate()


## 묘지 선택용 display/selectable 스냅샷. Context/step가 선택 전에 호출.
func show_graveyard_selection(display_cards: Array, selectable_cards: Array = []) -> void:
	_graveyard_select_mode = true
	_graveyard_display_cards = display_cards.duplicate()
	_graveyard_selectable_cards = (
		selectable_cards.duplicate() if not selectable_cards.is_empty() else display_cards.duplicate()
	)


## 묘지 선택 UI/상태 해제 + zone browse sidebar 숨김.
func hide_graveyard_panel() -> void:
	_graveyard_select_mode = false
	_graveyard_display_cards.clear()
	_graveyard_selectable_cards.clear()
	var ui := get_game_ui()
	if ui and ui.has_method("hide_zone_browse_sidebar"):
		ui.hide_zone_browse_sidebar()


## 필드 카드 클릭 → 필드 타깃 토글. DeckZone card_clicked 연결.
func on_card_clicked(card: Node) -> void:
	if _can_toggle_field_target_now():
		_toggle_target_pending(card)


## EM._input에서 위임. 필드 카드/슬롯 raycast 토글.
func handle_input(event: InputEvent) -> bool:
	if _can_toggle_field_target_now():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _is_pointer_over_blocking_ui():
				return false
			var card := _raycast_card_at_cursor()
			if card and _is_select_candidate(card):
				_toggle_target_pending(card)
				return true
	if _can_toggle_slot_now():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _is_pointer_over_blocking_ui():
				return false
			var slot := _raycast_slot_at_cursor()
			if slot and slot in _slot_candidates:
				_toggle_slot_pending(slot)
				return true
	return false


## EM._unhandled_input에서 위임. 필드 타깃만 재시도(UI가 선점한 클릭 보완).
func handle_unhandled_input(event: InputEvent) -> bool:
	if not _can_toggle_field_target_now():
		return false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_pointer_over_blocking_ui():
			return false
		var card := _raycast_card_at_cursor()
		if card and _is_select_candidate(card):
			_toggle_target_pending(card)
			return true
	return false


## 묘지 browse 뷰를 GameUILayer에 표시.
func show_graveyard_view(side: GameConstants.Side) -> void:
	var ui := get_game_ui()
	if _host.context == null or ui == null:
		return
	var cards: Array = _host.context.get_graveyard_card_nodes(side)
	var deck: DeckZone = _host.context.get_deck(side)
	var count := cards.size() if not cards.is_empty() else deck.graveyard.size()
	var side_label := "플레이어" if side == GameConstants.Side.PLAYER else "상대"
	ui.show_graveyard_view(side, cards, "%s 묘지 (%d장)" % [side_label, count])


## banishzone browse 뷰를 GameUILayer에 표시.
func show_banish_view(side: GameConstants.Side) -> void:
	var ui := get_game_ui()
	if _host.context == null or ui == null:
		return
	var side_label := "플레이어" if side == GameConstants.Side.PLAYER else "상대"
	var cards: Array = _host.context.get_banishzone_card_nodes(side)
	var deck: DeckZone = _host.context.get_deck(side)
	var count := cards.size() if not cards.is_empty() else deck.banishzone.size()
	ui.show_banish_view(side, cards, "%s banishzone (%d장)" % [side_label, count])


## EM 공개 var와 dialog minimize 플래그 동기화.
func _sync_dialog_minimized_to_host() -> void:
	if _host:
		_host.is_effect_dialog_minimized = is_effect_dialog_minimized


## EM 공개 var와 target minimize 플래그 동기화.
func _sync_target_minimized_to_host() -> void:
	if _host:
		_host.is_target_select_minimized = is_target_select_minimized


## 필드 타깃 토글 가능 여부(최소화 제외).
func _can_toggle_field_target_now() -> bool:
	return _field_select_mode and _select_mode and not is_target_select_minimized


## 대기 목록에 카드 토글 후 비주얼/confirm 갱신.
func _toggle_target_pending(card: Node) -> void:
	if not _is_select_candidate(card):
		return
	var pending: Node = _find_card_in_array(_select_pending, card)
	if _select_needed == 1:
		if pending == card:
			_select_pending.clear()
		else:
			_select_pending = [card]
	elif pending:
		_select_pending.erase(pending)
	elif _select_pending.size() < _select_needed:
		_select_pending.append(card)
	else:
		if not _select_pending.is_empty():
			_select_pending.remove_at(_select_pending.size() - 1)
		_select_pending.append(card)
	if _field_select_mode:
		_sync_field_selection_visuals()
		_update_field_confirm_state()
		var ui := get_game_ui()
		if ui and ui.has_method("show_card_info") and CardInfoRules.is_sidebar_eligible(card):
			ui.show_card_info(card)
	else:
		_sync_target_selection_visuals()
		_update_target_confirm_state()


## 슬롯 토글 가능 여부.
func _can_toggle_slot_now() -> bool:
	return _slot_select_mode and not is_target_select_minimized


## 대기 슬롯 토글 후 비주얼/confirm 갱신.
func _toggle_slot_pending(slot: CardSlot) -> void:
	if not _slot_select_mode or slot not in _slot_candidates:
		return
	if _select_needed == 1:
		if slot in _slot_pending:
			_slot_pending.clear()
		else:
			_slot_pending = [slot]
	elif slot in _slot_pending:
		_slot_pending.erase(slot)
	elif _slot_pending.size() < _select_needed:
		_slot_pending.append(slot)
	else:
		if not _slot_pending.is_empty():
			_slot_pending.remove_at(_slot_pending.size() - 1)
		_slot_pending.append(slot)
	_sync_slot_selection_visuals()
	_update_slot_confirm_state()


## 선택 후보 배열에 카드(또는 동일 instance_id)가 있는지.
func _is_select_candidate(card: Node) -> bool:
	for candidate in _select_candidates:
		if candidate == card:
			return true
		if (
			is_instance_valid(candidate)
			and is_instance_valid(card)
			and candidate.get("instance_id") != null
			and candidate.instance_id == card.instance_id
		):
			return true
	return false


## 묘지 selectable 목록(없으면 select 후보)에 있는지.
func _is_graveyard_selectable(card: Node) -> bool:
	if _graveyard_selectable_cards.is_empty():
		return _is_select_candidate(card)
	for candidate in _graveyard_selectable_cards:
		if candidate == card:
			return true
		if (
			is_instance_valid(candidate)
			and is_instance_valid(card)
			and candidate.get("instance_id") != null
			and card.get("instance_id") != null
			and candidate.instance_id == card.instance_id
		):
			return true
	return false


## CardManager raycast로 커서 아래 카드.
func _raycast_card_at_cursor() -> Node2D:
	if _host.context and _host.context.card_manager and _host.context.card_manager.has_method("raycast_check_for_card"):
		return _host.context.card_manager.raycast_check_for_card()
	return null


## CardManager raycast로 커서 아래 슬롯.
func _raycast_slot_at_cursor() -> CardSlot:
	if _host.context and _host.context.card_manager and _host.context.card_manager.has_method("raycast_check_for_card_slot"):
		return _host.context.card_manager.raycast_check_for_card_slot()
	return null


## GameUILayer가 포인터를 가로채는지.
func _is_pointer_over_blocking_ui() -> bool:
	var ui := get_game_ui()
	if ui and ui.has_method("is_pointer_over_blocking_ui"):
		return ui.is_pointer_over_blocking_ui()
	return false


## 타깃 바 카드 클릭. 비선택 카드면 사이드바 info만.
func _on_target_select_card_pressed(card: Node) -> void:
	if _activation_waiting:
		_toggle_activation_pending(card)
		var ui_act := get_game_ui()
		if ui_act and ui_act.has_method("show_card_info") and CardInfoRules.is_sidebar_eligible(card):
			ui_act.show_card_info(card)
		return
	if not _select_mode or _field_select_mode:
		return
	if not _is_graveyard_selectable(card):
		var ui := get_game_ui()
		if ui and ui.has_method("show_card_info") and CardInfoRules.is_sidebar_eligible(card):
			ui.show_card_info(card)
		return
	_toggle_target_pending(card)
	var ui_info := get_game_ui()
	if ui_info and ui_info.has_method("show_card_info") and CardInfoRules.is_sidebar_eligible(card):
		ui_info.show_card_info(card)


## confirm — 필요 장수/슬롯 충족 시 select_waiting 해제.
func _on_target_select_confirmed() -> void:
	if _activation_waiting:
		if _activation_pending == null or not is_instance_valid(_activation_pending):
			return
		_activation_result = _activation_pending
		_activation_waiting = false
		return
	if _slot_select_mode:
		if _slot_pending.size() < _select_needed:
			return
		_slot_resolved = _slot_pending.duplicate()
		_select_waiting = false
		return
	if not _select_mode:
		return
	if _select_variable_mode:
		if _select_pending.size() < _select_min:
			return
	else:
		if _select_pending.size() < _select_needed:
			return
	_select_resolved = _select_pending.duplicate()
	_select_waiting = false


## 발동 sheet 취소 — 표시 후보 전부 미발동(A1은 coordinator가 remaining에서 제거).
func _on_target_select_canceled() -> void:
	if not _activation_waiting:
		return
	_activation_result = null
	_activation_waiting = false


## minimize — restore 버튼으로 프롬프트 복귀. 최소화 중에는 패를 다시 보이게 한다.
func _on_target_select_minimized() -> void:
	if _activation_waiting:
		is_target_select_minimized = true
		_sync_target_minimized_to_host()
		var ui_act := get_game_ui()
		if ui_act:
			ui_act.minimize_target_select_bar()
			# 발동 확인 sheet도 타겟 선택과 같이 최소화 시 패 표시.
			ui_act.set_player_hand_hidden_for_selection(false)
			ui_act.show_effect_restore_button(func() -> void:
				is_target_select_minimized = false
				_sync_target_minimized_to_host()
				ui_act.restore_target_select_bar()
				ui_act.set_player_hand_hidden_for_selection(true)
			, "효과 발동")
		return
	if _slot_select_mode:
		is_target_select_minimized = true
		_sync_target_minimized_to_host()
		var ui_slot := get_game_ui()
		if ui_slot:
			ui_slot.minimize_field_target_prompt()
			ui_slot.show_effect_restore_button(func() -> void:
				is_target_select_minimized = false
				_sync_target_minimized_to_host()
				ui_slot.restore_field_target_prompt()
			, "슬롯 선택")
		return
	if not _select_mode:
		return
	is_target_select_minimized = true
	_sync_target_minimized_to_host()
	var ui := get_game_ui()
	if ui == null:
		return
	if _field_select_mode:
		ui.minimize_field_target_prompt()
	else:
		ui.minimize_target_select_bar()
		ui.set_player_hand_hidden_for_selection(false)
	ui.show_effect_restore_button(func() -> void:
		is_target_select_minimized = false
		_sync_target_minimized_to_host()
		if _field_select_mode:
			ui.restore_field_target_prompt()
		else:
			ui.restore_target_select_bar()
			ui.set_player_hand_hidden_for_selection(true)
	, "카드 선택")


## 발동 sheet: 카드 1장 토글 선택.
func _toggle_activation_pending(card: Node) -> void:
	if not _is_activation_candidate(card):
		return
	if _activation_pending == card:
		_activation_pending = null
	else:
		_activation_pending = card
	_sync_activation_selection_visuals()
	_update_activation_confirm_state()


func _is_activation_candidate(card: Node) -> bool:
	return _find_card_in_array(_activation_candidates, card) != null


func _sync_activation_selection_visuals() -> void:
	var ui := get_game_ui()
	var selected: Array = []
	if _activation_pending != null and is_instance_valid(_activation_pending):
		selected.append(_activation_pending)
	if ui and ui.has_method("set_target_selected_cards"):
		ui.set_target_selected_cards(selected)
	for card in _activation_candidates:
		if not is_instance_valid(card):
			continue
		if not card.has_method("set_selection_chosen"):
			continue
		card.set_selection_chosen(card == _activation_pending)


func _update_activation_confirm_state() -> void:
	var ui := get_game_ui()
	if ui == null:
		return
	var selected := 1 if _activation_pending != null and is_instance_valid(_activation_pending) else 0
	ui.update_target_selection_count(selected, 1)


## 타깃 바/카드 chosen 비주얼 동기화.
func _sync_target_selection_visuals() -> void:
	var ui := get_game_ui()
	if ui and ui.has_method("set_target_selected_cards"):
		ui.set_target_selected_cards(_select_pending)
	var display_cards := (
		_graveyard_display_cards
		if not _graveyard_display_cards.is_empty()
		else _select_candidates
	)
	for card in display_cards:
		if not is_instance_valid(card):
			continue
		if not card.has_method("set_selection_chosen"):
			continue
		var chosen := _find_card_in_array(_select_pending, card) != null
		card.set_selection_chosen(chosen)


## 배열에서 동일 카드 또는 instance_id 매칭.
func _find_card_in_array(arr: Array, card: Node) -> Node:
	for candidate in arr:
		if candidate == card:
			return candidate
		if (
			is_instance_valid(candidate)
			and is_instance_valid(card)
			and candidate.get("instance_id") != null
			and card.get("instance_id") != null
			and candidate.instance_id == card.instance_id
		):
			return candidate
	return null


## 타깃 바 선택 개수 UI 갱신.
func _update_target_confirm_state() -> void:
	var ui := get_game_ui()
	if ui and ui.has_method("update_target_selection_count"):
		if _select_variable_mode:
			ui.update_target_selection_count(_select_pending.size(), _select_needed, _select_min)
		else:
			ui.update_target_selection_count(_select_pending.size(), _select_needed)


## hint에 targetLocation·uuid 기본값을 채운다.
func _resolve_selection_hint(candidates: Array, hint: Dictionary = {}) -> Dictionary:
	var resolved := hint.duplicate(true)
	if not resolved.has("targetLocation") or int(resolved.get("targetLocation", -1)) < 0:
		resolved["targetLocation"] = _infer_target_location_from_candidates(candidates)
	var uuids: Array = _host._card_uuids(candidates)
	if not resolved.has("selectableUuids"):
		resolved["selectableUuids"] = uuids
	if not resolved.has("displayUuids"):
		resolved["displayUuids"] = uuids
	return resolved


## 후보 zone에서 대표 Location 추론 (GRAVE > BANISH > HAND > DECK > STACK > FIELD).
func _infer_target_location_from_candidates(candidates: Array) -> int:
	if candidates.is_empty():
		return EffectTypes.Location.FIELD
	var zones: Dictionary = {}
	for card in candidates:
		if not is_instance_valid(card):
			continue
		var zone = card.get("zone")
		if zone != null:
			zones[int(zone)] = true
	if zones.has(EffectTypes.Location.GRAVE):
		return EffectTypes.Location.GRAVE
	if zones.has(EffectTypes.Location.BANISH):
		return EffectTypes.Location.BANISH
	if zones.has(EffectTypes.Location.HAND):
		return EffectTypes.Location.HAND
	if zones.has(EffectTypes.Location.DECK):
		return EffectTypes.Location.DECK
	if zones.has(EffectTypes.Location.STACK):
		return EffectTypes.Location.STACK
	return EffectTypes.Location.FIELD


## hint location → UI 모드 문자열(field/graveyard/hand_bar).
func _resolve_selection_ui_mode(candidates: Array, hint: Dictionary) -> String:
	var loc := int(hint.get("targetLocation", -1))
	if loc == EffectTypes.Location.GRAVE:
		return "graveyard"
	if loc == EffectTypes.Location.BANISH:
		return "graveyard"
	if loc == EffectTypes.Location.HAND:
		return "hand_bar"
	if loc == EffectTypes.Location.DECK:
		return "hand_bar"
	if loc == EffectTypes.Location.STACK:
		return "hand_bar"
	if loc == EffectTypes.Location.FIELD or loc >= EffectTypes.Location.FIELD_L:
		return "field"
	return _resolve_selection_ui_mode_from_candidates(candidates)


## 후보만으로 UI 모드 추론.
func _resolve_selection_ui_mode_from_candidates(candidates: Array) -> String:
	if candidates.is_empty():
		return "field"
	var loc := _infer_target_location_from_candidates(candidates)
	if loc == EffectTypes.Location.GRAVE:
		return "graveyard"
	if loc == EffectTypes.Location.BANISH:
		return "graveyard"
	if loc == EffectTypes.Location.HAND:
		return "hand_bar"
	if loc == EffectTypes.Location.DECK:
		return "hand_bar"
	return "field"


## 필드 타깃 선택 시작 — selection rect + 프롬프트.
func _begin_field_target_selection(candidates: Array, needed: int) -> void:
	for c in candidates:
		if is_instance_valid(c) and c.has_method("toggle_selection_rect"):
			c.toggle_selection_rect(true)
	var ui := get_game_ui()
	if ui:
		var message := "필드 카드를 클릭해 대상을 지정하세요."
		if needed > 1:
			message += " (%d장)" % needed
		var anchor_top := _infer_prompt_anchor_top(candidates)
		ui.begin_field_target_selection("대상 선택", message, needed, anchor_top)
		_update_field_confirm_state()


## 필드 타깃 선택 종료 — rect/chosen 해제 + 프롬프트 end.
func _end_field_target_selection(candidates: Array) -> void:
	for c in candidates:
		if not is_instance_valid(c):
			continue
		if c.has_method("toggle_selection_rect"):
			c.toggle_selection_rect(false)
		if c.has_method("set_selection_chosen"):
			c.set_selection_chosen(false)
	var ui := get_game_ui()
	if ui:
		ui.end_field_target_selection()


## 필드 카드 chosen 비주얼.
func _sync_field_selection_visuals() -> void:
	for card in _select_candidates:
		if not is_instance_valid(card):
			continue
		if not card.has_method("set_selection_chosen"):
			continue
		var chosen := _find_card_in_array(_select_pending, card) != null
		card.set_selection_chosen(chosen)


## 필드 타깃 개수 UI.
func _update_field_confirm_state() -> void:
	var ui := get_game_ui()
	if ui and ui.has_method("update_field_target_selection_count"):
		ui.update_field_target_selection_count(_select_pending.size(), _select_needed)


## 슬롯 선택 시작 — candidate 표시 + 프롬프트.
func _begin_slot_selection(candidates: Array, needed: int, source: Node) -> void:
	for slot in candidates:
		if slot is CardSlot:
			slot.set_slot_select_candidate(true)
	var ui := get_game_ui()
	if ui:
		var message := "슬롯을 선택하세요."
		if needed > 1:
			message += " (%d곳)" % needed
		var anchor_top: bool = (
			is_instance_valid(source)
			and int(source.get("owner_side")) == GameConstants.Side.PLAYER
		)
		ui.begin_field_target_selection("필드 — 슬롯 선택", message, needed, anchor_top)
		_update_slot_confirm_state()


## 슬롯 선택 종료.
func _end_slot_selection(candidates: Array) -> void:
	for slot in candidates:
		if slot is CardSlot:
			slot.set_slot_select_candidate(false)
			slot.set_slot_selection_chosen(false)
	var ui := get_game_ui()
	if ui:
		ui.end_field_target_selection()


## 슬롯 chosen 비주얼.
func _sync_slot_selection_visuals() -> void:
	for slot in _slot_candidates:
		if slot is CardSlot:
			slot.set_slot_selection_chosen(slot in _slot_pending)


## 슬롯 개수 UI.
func _update_slot_confirm_state() -> void:
	var ui := get_game_ui()
	if ui and ui.has_method("update_field_target_selection_count"):
		ui.update_field_target_selection_count(_slot_pending.size(), _select_needed)


## 타깃 선택 비주얼 전부 해제.
func _clear_target_selection_visuals(display_cards: Array) -> void:
	var ui := get_game_ui()
	if ui and ui.has_method("set_target_selected_cards"):
		ui.set_target_selected_cards([])
	for card in display_cards:
		if is_instance_valid(card) and card.has_method("set_selection_chosen"):
			card.set_selection_chosen(false)


## 타깃 바 제목 문자열.
func _selection_title_text() -> String:
	if _graveyard_select_mode or not _graveyard_display_cards.is_empty():
		return "묘지 — 대상 선택"
	if _infer_target_location_from_candidates(_select_candidates) == EffectTypes.Location.HAND:
		return "패 — 대상 선택"
	if _infer_target_location_from_candidates(_select_candidates) == EffectTypes.Location.DECK:
		return "덱 — 카드 선택"
	return "필드 — 대상 선택"


## 자신 필드/패면 상단 앵커, 상대면 하단.
func _infer_prompt_anchor_top(candidates: Array) -> bool:
	# 상대 필드·패 → 하단(false) / 자신 필드·패 → 상단(true)
	for card in candidates:
		if is_instance_valid(card) and card.owner_side == GameConstants.Side.PLAYER:
			return true
	return false
