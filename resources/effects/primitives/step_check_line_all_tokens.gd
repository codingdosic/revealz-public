extends EffectStepBase
class_name StepCheckLineAllTokens

@export var token_name: String = "기사"
@export var exclude_source: bool = true
@export var store_key: String = "line_all_tokens"


func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var ok := EffectZoneQuery.line_other_allies_are_tokens(
		run_ctx.game_context, source, token_name, exclude_source
	)
	if not store_key.is_empty():
		run_ctx.store(store_key, ok)
	if ok:
		return true
	return not abort_on_fail


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	if not evaluate_preflight(source, run_ctx) and abort_on_fail:
		run_ctx.store("_abort", true)
