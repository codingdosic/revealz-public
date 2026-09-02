extends DeckZone

const CARD_SCENE_PATH := "res://scenes/card_slot/card/opponent_card.tscn"

var hover_area: ZoneHoverArea


func _ready() -> void:
	owner_side = GameConstants.Side.OPPONENT
	hover_area = ZoneHoverArea.new()
	hover_area.name = "HoverArea"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(158, 220)
	shape.shape = rect
	hover_area.add_child(shape)
	hover_area.collision_layer = GameConstants.COLLISION_LAYER_ZONE_TOOLTIP
	hover_area.collision_mask = 0
	add_child(hover_area)
	var back := get_node_or_null("Sprite2D") as Sprite2D
	if back:
		back.flip_v = true
	super._ready()


func get_tooltip_area() -> Area2D:
	return hover_area


func get_card_scene() -> PackedScene:
	return preload(CARD_SCENE_PATH)


func get_hand_manager() -> Node:
	var found := FieldBoardBuilder.find_under_field(self, "OpponentHand")
	return found if found else get_node_or_null("../OpponentHand")
