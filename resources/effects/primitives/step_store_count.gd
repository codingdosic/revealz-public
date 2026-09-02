extends EffectStepBase
class_name StepStoreCount

## 존 카드 수를 계산해서 run_ctx에 저장한다. (조건 실패 없음)
@export_group("대상 진영 · 존")
@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER
@export var zone: EffectTypes.EffectZone = EffectTypes.EffectZone.FIELD
@export_group("라인 · 필터")
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.ANY
@export var units_only: bool = false
@export var include_name_exact: String = ""
@export var require_token: bool = false
@export_group("출력")
@export var store_key: String = "count"


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var count := EffectZoneQuery.count_in_zone(
		run_ctx.game_context,
		source,
		relative_side,
		zone,
		line_scope,
		units_only,
		false,
		include_name_exact,
		require_token,
		PackedStringArray(),
		EffectZoneQuery.should_filter_skill_immune_targets(relative_side, zone)
	)
	if not store_key.is_empty():
		run_ctx.store(store_key, count)
