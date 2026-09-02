extends EffectStepBase
class_name StepSetCard

## 대상 유닛을 효과 세트(뒷면·타겟 불가) 상태로 — 제약의 마술사 제노
@export var targets_key: String = "targets"


## 저장된 대상에 effect_set(뒷면·타겟 불가) 적용.
func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	if ctx == null:
		return
	var targets: Array = _resolve_targets(run_ctx)
	if targets.is_empty():
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	for card in targets:
		if is_instance_valid(card):
			ctx.apply_effect_set(card)


func _resolve_targets(run_ctx: EffectPipelineRunContext) -> Array:
	if targets_key.is_empty():
		return []
	var stored = run_ctx.step_results.get(targets_key, [])
	if stored is Array:
		return stored
	return []
