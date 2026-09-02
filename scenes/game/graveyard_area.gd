extends Node2D
class_name GraveyardArea

@export var owner_side: GameConstants.Side = GameConstants.Side.PLAYER

var click_area: Area2D
var hover_glow: ZoneHoverGlow


func _ready() -> void:
	click_area = Area2D.new()
	click_area.name = "ClickArea"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(158, 220)
	shape.shape = rect
	click_area.add_child(shape)
	click_area.collision_layer = GameConstants.COLLISION_LAYER_GRAVEYARD
	click_area.collision_mask = 0
	click_area.input_pickable = false
	add_child(click_area)
	hover_glow = ZoneHoverGlow.attach_to(self)
