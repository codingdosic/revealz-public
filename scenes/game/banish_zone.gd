extends Node2D
class_name BanishArea

@export var owner_side: GameConstants.Side = GameConstants.Side.PLAYER

var hover_area: ZoneHoverArea
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

	hover_area = ZoneHoverArea.new()
	hover_area.name = "HoverArea"
	var hover_shape := CollisionShape2D.new()
	var hover_rect := RectangleShape2D.new()
	hover_rect.size = Vector2(158, 220)
	hover_shape.shape = hover_rect
	hover_area.add_child(hover_shape)
	hover_area.collision_layer = GameConstants.COLLISION_LAYER_ZONE_TOOLTIP
	hover_area.collision_mask = 0
	add_child(hover_area)
	hover_glow = ZoneHoverGlow.attach_to(self)


func get_tooltip_area() -> Area2D:
	return hover_area
