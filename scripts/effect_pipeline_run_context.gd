class_name EffectPipelineRunContext
extends RefCounted

var effect_manager: Node
var game_context: EffectContext
var step_results: Dictionary = {}
var execution_pool: Array = []
var current_targets: Array = []


func _init(p_effect_manager: Node, p_game_context: EffectContext) -> void:
	effect_manager = p_effect_manager
	game_context = p_game_context


func reset() -> void:
	step_results.clear()
	execution_pool.clear()
	current_targets.clear()


func store(key: String, value: Variant) -> void:
	if key.is_empty():
		return
	step_results[key] = value


func get_stored(key: String, default: Variant = null) -> Variant:
	return step_results.get(key, default)
