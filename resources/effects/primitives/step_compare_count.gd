extends EffectStepBase
class_name StepCompareCount

@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER
@export var zone: EffectTypes.EffectZone = EffectTypes.EffectZone.GRAVE
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.ANY
@export var units_only: bool = false
@export var count_ref_key: String = ""
@export var compare_op: EffectTypes.CompareOp = EffectTypes.CompareOp.GE
@export var threshold: int = 0
@export var store_key: String = ""


func _resolve_count(source: Node, run_ctx: EffectPipelineRunContext) -> int:
	if not count_ref_key.is_empty() and run_ctx.step_results.has(count_ref_key):
		return int(run_ctx.step_results[count_ref_key])
	return EffectZoneQuery.count_in_zone(
		run_ctx.game_context,
		source,
		relative_side,
		zone,
		line_scope,
		units_only,
		false,
		"",
		false,
		PackedStringArray(),
		EffectZoneQuery.should_filter_skill_immune_targets(relative_side, zone)
	)


func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var count := _resolve_count(source, run_ctx)
	if not store_key.is_empty():
		run_ctx.store(store_key, count)
	var ok := EffectZoneQuery.compare_int(count, compare_op, threshold)
	if not ok and abort_on_fail:
		return false
	return ok


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	if not evaluate_preflight(source, run_ctx) and abort_on_fail:
		run_ctx.store("_abort", true)
