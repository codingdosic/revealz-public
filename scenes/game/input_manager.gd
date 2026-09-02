extends Node2D

signal left_mouse_button_clicked
signal left_mouse_button_released

var card_manager_reference
var phase_manager_reference
var game_ui_reference
## RMB는 환경에 따라 InputEvent가 안 오고 Input 폴링만 되는 경우가 있음(에디터 임베드 등).
var _rmb_was_down: bool = false
var _rmb_handled_this_press: bool = false


func _ready() -> void:
	card_manager_reference = $"../CardManager"
	phase_manager_reference = $"../PhaseManager"
	game_ui_reference = $"../GameUILayer"
	if card_manager_reference.has_method("connect_card_signals_to_ui"):
		card_manager_reference.connect_card_signals_to_ui(game_ui_reference)
	set_process_input(true)
	set_process_unhandled_input(true)
	set_process(true)


## RMB press 엣지: 이벤트 경로가 막혀도 폴링으로 처리한다.
func _process(_delta: float) -> void:
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if down and not _rmb_was_down:
		_rmb_handled_this_press = false
		_handle_right_click()
	if not down:
		_rmb_handled_this_press = false
	_rmb_was_down = down


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_pointer_over_blocking_ui():
					return
				emit_signal("left_mouse_button_clicked")
				if not _try_zone_click_at_cursor():
					_try_start_drag_at_cursor()
			else:
				emit_signal("left_mouse_button_released")
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click()


## 폴링이 이미 처리했으면 스킵. 이벤트만 오는 빌드용 백업.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click()


## 우클릭 한 번(press): 미확정 패 복귀 우선, 아니면 사이드바 닫기.
func _handle_right_click() -> void:
	if _rmb_handled_this_press:
		return
	if _is_pointer_over_blocking_ui():
		_rmb_handled_this_press = true
		return
	_rmb_handled_this_press = true

	if _try_return_card_to_hand_at_cursor():
		_try_hide_card_sidebar()
		get_viewport().set_input_as_handled()
		return
	if _try_hide_sidebars_on_right_click():
		get_viewport().set_input_as_handled()


func _try_zone_click_at_cursor() -> bool:
	if _try_graveyard_click_at_cursor():
		return true
	return _try_banish_click_at_cursor()


func _try_graveyard_click_at_cursor() -> bool:
	var graveyard: GraveyardArea = card_manager_reference.raycast_check_for_graveyard()
	if graveyard == null:
		return false

	var em: Node = phase_manager_reference.get_node_or_null("../EffectManager")
	if em and em.has_method("show_graveyard_view"):
		em.show_graveyard_view(graveyard.owner_side)
		get_viewport().set_input_as_handled()
		return true
	return false


func _try_banish_click_at_cursor() -> bool:
	var banish: BanishArea = card_manager_reference.raycast_check_for_banish()
	if banish == null:
		return false

	var em: Node = phase_manager_reference.get_node_or_null("../EffectManager")
	if em and em.has_method("show_banish_view"):
		em.show_banish_view(banish.owner_side)
		get_viewport().set_input_as_handled()
		return true
	return false


func _try_start_drag_at_cursor() -> void:
	if _is_effect_selecting():
		return
	if not phase_manager_reference.is_player_setting_turn():
		return

	var card_found: Node2D = card_manager_reference.raycast_check_for_card()
	if card_found and _is_playable_card(card_found):
		if card_found.get("is_interactive") != false:
			if phase_manager_reference.can_drag_card(card_found):
				card_manager_reference.prepare_drag(card_found)


## 커서 아래 미확정 카드를 패로 되돌린다. 성공 시 true.
func _try_return_card_to_hand_at_cursor() -> bool:
	if _is_effect_selecting():
		return false
	if not phase_manager_reference.is_player_setting_turn():
		return false

	if card_manager_reference.card_being_dragged:
		card_manager_reference.cancel_drag_to_hand()
		return true

	var card_found: Node2D = card_manager_reference.raycast_check_for_card()
	if card_found == null:
		var slot: CardSlot = card_manager_reference.raycast_check_for_card_slot()
		if slot != null and slot.card_in_slot != null:
			card_found = slot.card_in_slot
	if card_found == null or not _is_playable_card(card_found):
		return false
	if card_found.get("is_interactive") == false:
		return false
	if not phase_manager_reference.can_return_to_hand(card_found):
		return false
	phase_manager_reference.on_player_drag_cancelled(card_found)
	return true


func _is_playable_card(node: Node2D) -> bool:
	return node != null and node.has_method("init_from_data")


func _is_effect_selecting() -> bool:
	var em: Node = phase_manager_reference.get_node_or_null("../EffectManager")
	if em and em.has_method("is_selecting"):
		return em.is_selecting() or em.is_busy
	return false


func _try_hide_card_sidebar() -> bool:
	if game_ui_reference == null:
		return false
	if game_ui_reference.has_method("consume_card_info_back"):
		return game_ui_reference.consume_card_info_back()
	if game_ui_reference.has_method("is_card_sidebar_visible") and game_ui_reference.is_card_sidebar_visible():
		game_ui_reference.hide_card_sidebar()
		return true
	return false


func _try_hide_sidebars_on_right_click() -> bool:
	if _try_hide_match_menu():
		return true
	if _try_hide_card_sidebar():
		return true
	return _try_hide_zone_browse_sidebar()


func _try_hide_match_menu() -> bool:
	if game_ui_reference == null:
		return false
	if game_ui_reference.has_method("is_match_menu_visible") and game_ui_reference.is_match_menu_visible():
		game_ui_reference.hide_match_menu()
		return true
	return false


func _try_hide_zone_browse_sidebar() -> bool:
	if game_ui_reference == null:
		return false
	if game_ui_reference.has_method("is_zone_browse_visible") and game_ui_reference.is_zone_browse_visible():
		game_ui_reference.hide_zone_browse_sidebar()
		return true
	return false


func _is_pointer_over_blocking_ui() -> bool:
	if game_ui_reference == null:
		return false
	if game_ui_reference.has_method("is_pointer_over_blocking_ui"):
		return game_ui_reference.is_pointer_over_blocking_ui()
	return false
