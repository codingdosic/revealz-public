extends Node2D

const COLLISION_MASK_CARD = GameConstants.COLLISION_LAYER_CARD
const COLLISION_MASK_CARD_SLOT = GameConstants.COLLISION_LAYER_CARD_SLOT
const COLLISION_MASK_GRAVEYARD = GameConstants.COLLISION_LAYER_GRAVEYARD
const DEFAULT_CARD_MOVE_SPEED = 0.1
const DEFAULT_CARD_SCALE = 0.4
const CARD_BIGGER_SCALE = 0.6
const DRAG_CLICK_THRESHOLD := 10.0

var screen_size
var card_being_dragged
var is_hovering_on_card: bool = false
## 현재 호버 중인 카드. bool만 있으면 exit 미발생 시 이후 호버가 영구 차단됨.
var _hovered_card: Node2D = null
var player_hand_reference
var phase_manager_reference
var _drag_start_mouse: Vector2
var _drag_moved: bool = false
var _pending_drag_card: Node2D = null


func _ready() -> void:
	add_to_group("card_manager")
	_refresh_screen_size()
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)
	player_hand_reference = $"../PlayerHand"
	phase_manager_reference = $"../PhaseManager"
	$"../InputManager".connect("left_mouse_button_released", on_left_click_released)


## 해상도/창 변경 후 드래그 clamp용 화면 크기를 갱신한다.
func _on_viewport_size_changed() -> void:
	_refresh_screen_size()


## viewport 가시 영역을 screen_size에 반영한다.
func _refresh_screen_size() -> void:
	screen_size = get_viewport_rect().size


func _process(_delta: float) -> void:
	if _pending_drag_card and card_being_dragged == null:
		if get_global_mouse_position().distance_to(_drag_start_mouse) > DRAG_CLICK_THRESHOLD:
			var card: Node2D = _pending_drag_card
			_pending_drag_card = null
			_begin_drag(card)
	if card_being_dragged:
		if get_global_mouse_position().distance_to(_drag_start_mouse) > DRAG_CLICK_THRESHOLD:
			_drag_moved = true
		var mouse_position = get_global_mouse_position()
		card_being_dragged.global_position = Vector2(
			clamp(mouse_position.x, 0, screen_size.x),
			clamp(mouse_position.y, 0, screen_size.y)
		)


func prepare_drag(card: Node2D) -> void:
	if not phase_manager_reference.can_drag_card(card):
		return
	_pending_drag_card = card
	_drag_start_mouse = get_global_mouse_position()
	_drag_moved = false


func start_drag(card: Node2D) -> void:
	prepare_drag(card)


## 드래그 시작. 손패 부채 회전을 풀어 바로 세운다.
func _begin_drag(card: Node2D) -> void:
	if not phase_manager_reference.can_drag_card(card):
		return

	_drag_moved = true
	card_being_dragged = card
	clear_hover_state(card)
	card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card.rotation = 0.0
	card.z_index = 100

	if card.card_slot_card_is_in:
		var slot: CardSlot = card.card_slot_card_is_in
		slot.release()

	# 슬롯에서 끌어올 때 즉시 앞면으로 — 드롭 취소 시 apply_hand_visual과 동일 상태
	if card.reveal_state == GameConstants.RevealState.SETTING_PREVIEW:
		card.apply_hand_visual()


func cancel_drag_to_hand() -> void:
	if card_being_dragged == null:
		return
	if not phase_manager_reference.is_player_setting_turn():
		return

	var card: Node2D = card_being_dragged
	card_being_dragged = null
	card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card.z_index = 1
	phase_manager_reference.on_player_drag_cancelled(card)
	_resync_hover_after_pointer_up()


func finish_drag() -> void:
	if card_being_dragged == null:
		return

	var dragged_card: Node2D = card_being_dragged
	card_being_dragged = null

	if phase_manager_reference.is_player_setting_turn():
		_finish_setting_drag(dragged_card)
		return

	dragged_card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	dragged_card.z_index = 1
	player_hand_reference.add_card_to_hand(dragged_card, DEFAULT_CARD_MOVE_SPEED)


## 세팅 턴 드래그 종료: 슬롯 배치 / 미확정 취소 / 손패 재정렬.
func _finish_setting_drag(card: Node2D) -> void:
	card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card.z_index = 1

	var card_slot_found: CardSlot = raycast_check_for_card_slot()
	if card_slot_found and phase_manager_reference.can_drop_on_slot(card_slot_found, card):
		phase_manager_reference.on_player_pending_place(card, card_slot_found)
		return
	if phase_manager_reference.can_return_to_hand(card):
		phase_manager_reference.on_player_drag_cancelled(card)
		return
	if player_hand_reference and card in player_hand_reference.get_hand_cards():
		player_hand_reference.reorder_card_by_x(card, get_global_mouse_position().x)
		return
	phase_manager_reference.on_player_drag_cancelled(card)


func raycast_check_for_card() -> Node2D:
	var space_state = get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD

	var result = space_state.intersect_point(parameters)
	if result.is_empty():
		return _field_card_from_slot_raycast()

	var best_card: Node2D = null
	var best_z := -999999
	for hit in result:
		var collider = hit.collider
		if collider == null:
			continue
		var card: Node2D = collider.get_parent() as Node2D
		if not _is_valid_card_raycast_target(card):
			continue
		if card.get("stack_host") != null and is_instance_valid(card.stack_host):
			card = card.stack_host
		if card.z_index > best_z:
			best_card = card
			best_z = card.z_index
	return best_card if best_card else _field_card_from_slot_raycast()


func _field_card_from_slot_raycast() -> Node2D:
	var slot := raycast_check_for_card_slot()
	if slot == null or slot.card_in_slot == null:
		return null
	var card: Node2D = slot.card_in_slot
	if _is_valid_card_raycast_target(card):
		return card
	return null


func _is_valid_card_raycast_target(card: Node2D) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if not card.visible:
		return false
	if not card.has_method("init_from_data"):
		return false
	var zone: int = card.get("zone") if card.get("zone") != null else -1
	if zone == EffectTypes.Location.GRAVE:
		return false
	if zone == EffectTypes.Location.BANISH:
		return false
	return true


func raycast_check_for_card_slot() -> CardSlot:
	var space_state = get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT

	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		var node = get_card_with_highest_z_index(result)
		if node is CardSlot:
			return node
	return null


func raycast_check_for_graveyard() -> GraveyardArea:
	var space_state = get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_GRAVEYARD

	var result = space_state.intersect_point(parameters)
	if result.is_empty():
		return null

	for hit in result:
		var collider = hit.collider
		if collider == null:
			continue
		var parent = collider.get_parent()
		if parent is GraveyardArea:
			return parent
	return null


func raycast_check_for_banish() -> BanishArea:
	var space_state = get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_GRAVEYARD

	var result = space_state.intersect_point(parameters)
	if result.is_empty():
		return null

	for hit in result:
		var collider = hit.collider
		if collider == null:
			continue
		var parent = collider.get_parent()
		if parent is BanishArea:
			return parent
	return null


func connect_card_signals(card: Node2D) -> void:
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)


func connect_card_signals_to_ui(_game_ui: Node) -> void:
	pass


func on_left_click_released() -> void:
	var should_toggle_sidebar := false
	if card_being_dragged:
		should_toggle_sidebar = not _drag_moved
		finish_drag()
	elif _pending_drag_card:
		should_toggle_sidebar = true
		_pending_drag_card = null
	else:
		should_toggle_sidebar = true
	if should_toggle_sidebar:
		_try_close_match_menu_on_outside_click()
		_try_close_zone_browse_on_outside_click()
		_try_toggle_card_sidebar()
	_resync_hover_after_pointer_up()


func _try_close_match_menu_on_outside_click() -> void:
	var game_ui: Node = get_node_or_null("../GameUILayer")
	if game_ui and game_ui.has_method("try_close_match_menu_on_outside_click"):
		game_ui.try_close_match_menu_on_outside_click()


func _try_close_zone_browse_on_outside_click() -> void:
	var game_ui: Node = get_node_or_null("../GameUILayer")
	if game_ui == null:
		return
	var card: Node2D = raycast_check_for_card()
	var em: Node = get_node_or_null("../EffectManager")
	if em and em.has_method("should_keep_zone_browse_on_card_click"):
		if em.should_keep_zone_browse_on_card_click(card):
			return
	if game_ui.has_method("should_keep_zone_browse_on_field_card_click"):
		if game_ui.should_keep_zone_browse_on_field_card_click(card):
			return
	if game_ui.has_method("try_close_zone_browse_on_outside_click"):
		game_ui.try_close_zone_browse_on_outside_click()


func _try_toggle_card_sidebar() -> void:
	var game_ui: Node = get_node_or_null("../GameUILayer")
	if game_ui == null:
		return
	if game_ui.has_method("should_skip_field_sidebar_toggle") and game_ui.should_skip_field_sidebar_toggle():
		return
	var card: Node2D = raycast_check_for_card()
	if game_ui.has_method("toggle_card_info"):
		game_ui.toggle_card_info(card)


func on_hovered_over_card(card: Node2D) -> void:
	if not _can_hover_tilt_card(card):
		return
	# 이전 호버가 exit 없이 남았어도 새 카드로 전환
	if _hovered_card != null and is_instance_valid(_hovered_card) and _hovered_card != card:
		_unhighlight_card(_hovered_card)
	_hovered_card = card
	is_hovering_on_card = true
	highlight_card(card, true)


func on_hovered_off_card(card: Node2D) -> void:
	if card_being_dragged:
		return
	# 락된 뒤에도 축소·플래그 클리어 (확정 직후 mouse_exit 스킵/무시 방지)
	if is_instance_valid(card):
		_unhighlight_card(card)
		if _hovered_card == card:
			_hovered_card = null
	var new_card_hovered := raycast_check_for_card()
	if _can_hover_tilt_card(new_card_hovered):
		_hovered_card = new_card_hovered
		is_hovering_on_card = true
		highlight_card(new_card_hovered, true)
	else:
		is_hovering_on_card = false
		_hovered_card = null


## 배치 확정·제거·UI 차단 시 호버 스케일/틸트/플래그 강제 해제.
func clear_hover_state(card: Node2D = null) -> void:
	var targets: Array[Node2D] = []
	if card != null and is_instance_valid(card):
		targets.append(card)
	if _hovered_card != null and is_instance_valid(_hovered_card) and not targets.has(_hovered_card):
		targets.append(_hovered_card)
	is_hovering_on_card = false
	_hovered_card = null
	for c in targets:
		_unhighlight_card(c)
		CardHoverTilt.snap_flat(c)


## 포인터 업/드래그 종료 후 커서 아래 카드와 호버 상태를 다시 맞춘다.
func _resync_hover_after_pointer_up() -> void:
	if card_being_dragged != null:
		return
	if _is_pointer_over_blocking_ui():
		clear_hover_state()
		return
	var under := raycast_check_for_card()
	if _can_hover_tilt_card(under):
		if _hovered_card != under:
			clear_hover_state()
			_hovered_card = under
			is_hovering_on_card = true
			highlight_card(under, true)
	else:
		clear_hover_state()


## 앞면으로 보이는 카드면 호버 틸트를 허용한다.
## 필드 확정 카드는 is_interactive=false지만 앞면이면 틸트 허용.
func _can_hover_tilt_card(card: Node2D) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if card_being_dragged:
		return false
	if not card.visible:
		return false
	if _is_pointer_over_blocking_ui():
		return false
	var zone: int = card.get("zone") if card.get("zone") != null else -1
	if zone == EffectTypes.Location.GRAVE \
		or zone == EffectTypes.Location.BANISH \
		or zone == EffectTypes.Location.DECK:
		return false
	if card.has_method("_is_showing_card_back") and card._is_showing_card_back():
		return false
	var rs = card.get("reveal_state")
	if rs != null:
		# 손패 앞면(HAND·SETTING_PREVIEW) 또는 필드 앞면(REVEALED)만 허용
		var allowed := [
			GameConstants.RevealState.HAND,
			GameConstants.RevealState.SETTING_PREVIEW,
			GameConstants.RevealState.REVEALED,
		]
		if rs not in allowed:
			return false
	return true


func _is_pointer_over_blocking_ui() -> bool:
	var game_ui: Node = get_node_or_null("../GameUILayer")
	if game_ui and game_ui.has_method("is_pointer_over_blocking_ui"):
		return game_ui.is_pointer_over_blocking_ui()
	return false


## 카드 호버 시 확대/축소 + 강체 기울임. 손패면 부채 z 를 유지·복구한다.
func highlight_card(card: Node2D, hovered: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	if hovered:
		card.scale = Vector2(CARD_BIGGER_SCALE, CARD_BIGGER_SCALE)
		card.z_index = 80
		CardHoverTilt.set_hovering(card, true)
	else:
		_unhighlight_card(card)


func _unhighlight_card(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	_restore_hand_z(card)
	CardHoverTilt.set_hovering(card, false)


## 손패에 있으면 부채 z 를 복구하고, 아니면 기본 1.
func _restore_hand_z(card: Node2D) -> void:
	if player_hand_reference and player_hand_reference.has_method("restore_card_z"):
		if card in player_hand_reference.get_hand_cards():
			player_hand_reference.restore_card_z(card)
			return
	card.z_index = 1


func get_card_with_highest_z_index(cards: Array) -> Node2D:
	var highest_z_card: Node2D = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index

	for i in range(1, cards.size()):
		var current_card: Node2D = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card
