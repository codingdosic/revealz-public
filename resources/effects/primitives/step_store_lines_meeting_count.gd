extends EffectStepBase
class_name StepStoreLinesMeetingCount

@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER
@export var min_units: int = 2
@export var units_only: bool = true
@export var store_key: String = "line_count"


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var count := EffectZoneQuery.count_lines_meeting_min_units(
		run_ctx.game_context, source, relative_side, min_units, units_only
	)
	if not store_key.is_empty():
		run_ctx.store(store_key, count)
