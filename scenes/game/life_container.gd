extends Node2D
class_name LifeContainerDisplay

const CARD_SCALE := Vector2(0.4, 0.4)
const OVERLAP_OFFSET := 30.0
const CARD_ROTATION := 1.5707964

var deck_zone: DeckZone
var _display_root: Node2D
var _card_scene: PackedScene
var hover_area: ZoneHoverArea


func _ready() -> void:
	hover_area = ZoneHoverArea.new()
	hover_area.name = "HoverArea"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(90, 180)
	shape.shape = rect
	hover_area.add_child(shape)
	hover_area.collision_layer = GameConstants.COLLISION_LAYER_ZONE_TOOLTIP
	hover_area.collision_mask = 0
	add_child(hover_area)


func setup(deck: DeckZone, card_scene: PackedScene) -> void:
	deck_zone = deck
	_card_scene = card_scene
	refresh()


func get_tooltip_area() -> Area2D:
	return hover_area


## 패로 나갈 장의 화면 좌표. refresh 전이면 스택 맨 앞(방금 pop된 장) 더미 위치.
func takeoff_global_position() -> Vector2:
	var dummy := _takeoff_dummy()
	if dummy:
		return dummy.global_position
	return global_position


## 실카드를 라이프 스택 출발점에 둔다. 표시용 더미는 숨겨 겹침을 막는다.
func place_card_for_hand_fx(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	var dummy := _takeoff_dummy()
	if dummy:
		card.global_position = dummy.global_position
		dummy.visible = false
	else:
		card.global_position = global_position
	card.rotation = CARD_ROTATION
	card.set_meta("vfx_from_rotation", CARD_ROTATION)


## 스택 맨 앞 표시용 카드. 없으면 null.
func _takeoff_dummy() -> Node2D:
	if _display_root == null or not is_instance_valid(_display_root):
		return null
	if _display_root.get_child_count() <= 0:
		return null
	return _display_root.get_child(0) as Node2D


## 라이프 존 id 목록을 읽어 겹친 카드 스프라이트를 다시 그린다.
func refresh() -> void:
	if deck_zone == null or _card_scene == null:
		return

	if _display_root:
		_display_root.queue_free()

	_display_root = Node2D.new()
	_display_root.name = "LifeCards"
	add_child(_display_root)

	var count := deck_zone.life_cards.size()
	if count == 0:
		return

	var start_y := -OVERLAP_OFFSET * (count - 1) * 0.5

	for i in range(count):
		var card_id: int = int(deck_zone.life_cards[i])
		var card_name := CardRegistry.id_to_name(card_id)
		if card_name.is_empty():
			continue
		var card := _create_life_card(card_name)
		card.position = Vector2(0, start_y + i * OVERLAP_OFFSET)
		_display_root.add_child(card)


## 표시용 라이프 카드 노드를 만들고 상호작용을 끈다.
func _create_life_card(card_name: String) -> Node2D:
	var card: Node2D = _card_scene.instantiate()
	card.scale = CARD_SCALE
	card.rotation = CARD_ROTATION

	CardHelpers.setup_card_data(card, card_name, deck_zone.owner_side)
	AccessoryRuntime.apply_card_back(
		card,
		AccessoryRuntime.card_back_id_for_owner_side(deck_zone.owner_side)
	)
	CardHelpers.disable_interaction(card)
	card.apply_setting_hidden()
	return card
