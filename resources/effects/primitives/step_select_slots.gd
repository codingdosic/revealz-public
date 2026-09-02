extends EffectStepBase
class_name StepSelectSlots

@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.SAME_AS_SOURCE
@export var count: int = 1
@export var store_key: String = "slots"


func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var slots := EffectZoneQuery.get_empty_slots(
		run_ctx.game_context, source, relative_side, line_scope
	)
	if slots.size() < count:
		return not abort_on_fail
	return true


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var slots := EffectZoneQuery.get_empty_slots(
		run_ctx.game_context, source, relative_side, line_scope
	)
	if slots.size() < count:
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	var picked: Array = []
	if run_ctx.effect_manager and run_ctx.effect_manager.has_method("select_slots"):
		picked = await run_ctx.effect_manager.select_slots(slots, count, source)
	elif slots.size() >= count:
		picked = slots.slice(0, count)
	if picked.size() < count:
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	if not store_key.is_empty():
		run_ctx.store(store_key, picked)
