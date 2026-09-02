extends EffectStepBase
class_name StepCompareLineUnitCounts

@export var compare_op: EffectTypes.CompareOp = EffectTypes.CompareOp.GT
@export var store_key: String = ""


func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var ok := EffectZoneQuery.compare_line_unit_counts(
		run_ctx.game_context, source, compare_op
	)
	if not store_key.is_empty():
		run_ctx.store(store_key, ok)
	if ok:
		return true
	return not abort_on_fail


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	if not evaluate_preflight(source, run_ctx) and abort_on_fail:
		run_ctx.store("_abort", true)
