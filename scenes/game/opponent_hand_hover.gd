extends ZoneHoverArea

func _ready() -> void:
	collision_layer = GameConstants.COLLISION_LAYER_ZONE_TOOLTIP
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1000, 100)
	shape.shape = rect
	shape.position = Vector2(576, 60)
	add_child(shape)
