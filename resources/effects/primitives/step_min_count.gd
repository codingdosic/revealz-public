extends EffectStepBase
class_name StepMinCount

## 조건 — zone 카드 수 ≥ min_count (EffectBundle.condition + cost 대응)
@export_group("대상 진영 · 존")
@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER
@export var zone: EffectTypes.EffectZone = EffectTypes.EffectZone.FIELD
@export_group("라인 · 개수")
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.ANY
@export var min_count: int = 1
@export var units_only: bool = false
@export_group("체인 (선택)")
@export var store_key: String = ""


func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var count := EffectZoneQuery.count_in_zone(
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
	if not store_key.is_empty():
		run_ctx.store(store_key, count)
	if count >= min_count:
		return true
	return not abort_on_fail


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	if not evaluate_preflight(source, run_ctx) and abort_on_fail:
		run_ctx.store("_abort", true)
