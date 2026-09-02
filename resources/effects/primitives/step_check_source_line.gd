extends EffectStepBase
class_name StepCheckSourceLine

## 발동 카드가 특정 라인에 있을 때만 통과.
@export_group("허용 라인")
@export var allow_left: bool = true
@export var allow_center: bool = true
@export var allow_right: bool = true


func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var ctx := run_ctx.game_context
	var line := ctx.line_of_card(source)
	var ok := false
	match line:
		int(GameConstants.Line.LEFT):
			ok = allow_left
		int(GameConstants.Line.CENTER):
			ok = allow_center
		int(GameConstants.Line.RIGHT):
			ok = allow_right
		_:
			ok = false
	return ok or not abort_on_fail


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	if not evaluate_preflight(source, run_ctx) and abort_on_fail:
		run_ctx.store("_abort", true)

