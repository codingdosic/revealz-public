extends Area2D
class_name ZoneHoverArea

var _game_ui: Node
var _count_fn: Callable


func setup(game_ui: Node, count_fn: Callable) -> void:
	_game_ui = game_ui
	_count_fn = count_fn
	collision_layer = GameConstants.COLLISION_LAYER_ZONE_TOOLTIP
	collision_mask = 0
	input_pickable = false
