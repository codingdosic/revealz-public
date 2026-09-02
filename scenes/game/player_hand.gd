extends Node2D
## 플레이어 손패. 배치=HandFanLayout (정적 부채꼴).
## 튜닝: scripts/ui/hand_fan_layout.gd 의 PLAYER_* 상수.

const CARD_SCENE_PATH = "res://scenes/card_slot/card/card.tscn"
const DEFAULT_CARD_MOVE_SPEED = 0.1

var player_hand: Array = []
var _hidden_for_target_select: bool = false


## 부트 시 뷰포트 리사이즈에 손패를 다시 맞춘다.
func _ready() -> void:
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)


## 창 크기 변경 시 부채 위치를 즉시 갱신한다.
func _on_viewport_size_changed() -> void:
	update_hand_positions(0.0)


## 타겟 선택 중 손패 숨김/복구.
func set_hidden_for_target_select(hidden: bool) -> void:
	if hidden:
		_notify_card_manager_clear_hover()
	_hidden_for_target_select = hidden
	_apply_hand_visibility()


## 타겟 선택용 숨김 여부.
func is_hidden_for_target_select() -> bool:
	return _hidden_for_target_select


## 숨김 플래그에 맞춰 카드 visible·입력을 맞춘다.
func _apply_hand_visibility() -> void:
	for card in get_hand_cards():
		if not is_instance_valid(card):
			continue
		card.visible = not _hidden_for_target_select
		card.is_interactive = not _hidden_for_target_select


## CardManager 호버 잔존 해제.
func _notify_card_manager_clear_hover(card: Node2D = null) -> void:
	var cm := get_node_or_null("../CardManager")
	if cm and cm.has_method("clear_hover_state"):
		cm.clear_hover_state(card)


## 유효하지 않은 손패 참조를 걷어낸다.
func _prune_hand() -> void:
	player_hand = player_hand.filter(func(c): return c != null and is_instance_valid(c))


## 뷰포트 크기 (부채 중심 계산용).
func _viewport_size() -> Vector2:
	if is_inside_tree():
		return get_viewport().get_visible_rect().size
	return HandFanLayout.FALLBACK_VIEWPORT


## 카드를 손패에 넣고 부채 재배치한다.
func add_card_to_hand(card, speed) -> void:
	if card == null or not is_instance_valid(card):
		return
	_ensure_card_in_card_manager(card)
	CardHelpers.prepare_for_hand(card, GameConstants.Side.PLAYER)
	CardHelpers.restore_vfx_from_rotation(card)
	_prune_hand()
	if card not in player_hand:
		# 맨 뒤(큰 index)=오른쪽부터 채움. index 0=왼쪽은 레이아웃 불변.
		player_hand.append(card)
		update_hand_positions(speed)
	else:
		var idx := player_hand.find(card)
		_apply_pose(card, idx, player_hand.size(), speed if speed != null else DEFAULT_CARD_MOVE_SPEED)
	_apply_hand_visibility()


## 전 손패에 부채 포즈를 적용한다.
func update_hand_positions(speed) -> void:
	_prune_hand()
	var n := player_hand.size()
	var move_speed: float = float(speed) if speed != null else DEFAULT_CARD_MOVE_SPEED
	for i in range(n):
		var card = player_hand[i]
		if not is_instance_valid(card):
			continue
		_apply_pose(card, i, n, move_speed)


## index 장에 포즈(위치·회전·z)를 적용하고 트윈한다.
func _apply_pose(card: Node2D, index: int, count: int, speed: float) -> void:
	var pose := HandFanLayout.pose_for(
		GameConstants.Side.PLAYER, index, count, _viewport_size()
	)
	var target_pos: Vector2 = pose["position"]
	var target_rot: float = pose["rotation"]
	card.starting_position = target_pos
	card.z_index = int(pose["z_index"])
	animate_card_to_pose(card, target_pos, target_rot, speed)


## 위치·회전을 speed초 동안 보간한다. speed<=0 이면 즉시. MatchVfx 공통 이동.
func animate_card_to_pose(card: Node2D, new_position: Vector2, new_rotation: float, speed: float) -> void:
	if card == null or not is_instance_valid(card):
		return
	var to_global := new_position
	if card.get_parent() is Node2D:
		to_global = (card.get_parent() as Node2D).to_global(new_position)
	var params := MatchVfx.default_hand_params(
		float(speed) if speed != null else DEFAULT_CARD_MOVE_SPEED,
		MatchVfx.FACE_UP
	)
	params["to"] = to_global
	params["to_rotation"] = new_rotation
	if not is_inside_tree() or float(params["duration"]) <= 0.0:
		MatchVfx.snap_card(card, params)
		card.starting_position = new_position
		return
	MatchVfx.play_card_move(card, params)


## 드롭 X로 손패 배열 순서를 바꾼 뒤 부채를 다시 잡는다. index 0 = 왼쪽.
func reorder_card_by_x(card: Node2D, mouse_x: float, speed = DEFAULT_CARD_MOVE_SPEED) -> void:
	if card == null or not is_instance_valid(card):
		return
	_prune_hand()
	if card not in player_hand:
		return
	player_hand.erase(card)
	var insert_at := 0
	for other in player_hand:
		var ox: float = other.position.x
		if other.get("starting_position") != null:
			ox = other.starting_position.x
		if ox < mouse_x:
			insert_at += 1
	player_hand.insert(insert_at, card)
	update_hand_positions(speed if speed != null else DEFAULT_CARD_MOVE_SPEED)
	_apply_hand_visibility()


## 손패에서 제거하고 재배치한다. 떠난 카드의 부채 회전은 해제한다.
func remove_card_from_hand(card) -> void:
	if card == null:
		return
	_notify_card_manager_clear_hover(card as Node2D)
	player_hand.erase(card)
	if is_instance_valid(card):
		card.rotation = 0.0
	_prune_hand()
	update_hand_positions(DEFAULT_CARD_MOVE_SPEED)
	_apply_hand_visibility()


## 손패 장수.
func get_hand_size() -> int:
	_prune_hand()
	return player_hand.size()


## 손패 카드 배열.
func get_hand_cards() -> Array:
	_prune_hand()
	return player_hand


## 카드가 손패에 있으면 부채 z_index 를 복구한다 (호버 해제용).
func restore_card_z(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	var idx := player_hand.find(card)
	if idx < 0:
		return
	card.z_index = HandFanLayout.z_for_index(idx)


## CardManager 자식으로 옮긴다.
func _ensure_card_in_card_manager(card: Node2D) -> void:
	var card_manager: Node2D = $"../CardManager"
	if card.get_parent() == card_manager:
		return
	if card.get_parent():
		card.get_parent().remove_child(card)
	card_manager.add_child(card)
