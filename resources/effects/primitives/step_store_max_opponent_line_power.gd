extends EffectStepBase
class_name StepStoreMaxOpponentLinePower

## 동일 라인 상대 유닛 중 배치 LP 최대값 저장 (거울의 마녀 미요)
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.SAME_AS_SOURCE
@export var units_only: bool = true
@export var store_key: String = "max_lp"


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var max_lp := EffectZoneQuery.max_opponent_field_line_power(
		run_ctx.game_context, source, line_scope, units_only
	)
	if not store_key.is_empty():
		run_ctx.store(store_key, max_lp)
