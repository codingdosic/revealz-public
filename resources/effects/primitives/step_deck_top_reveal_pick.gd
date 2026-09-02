extends EffectStepBase
class_name StepDeckTopRevealPick

## 덱 위 N장 공개 → TargetSelectBar에서 M장 선택 → 패 · 나머지 덱 아래 (선택의 마술사 뤼트)
@export var reveal_count: int = 3
@export var pick_count: int = 1


## 덱 위 공개·선택 선행 조건(덱 장수). can_trigger·파이프라인 게이트.
func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var ctx := run_ctx.game_context
	if ctx == null or source == null:
		return false
	if not ctx.can_reveal_deck_top(source.owner_side, reveal_count):
		return not abort_on_fail
	return true


## 덱 위 N장 공개 후 M장 패로, 나머지 덱 아래.
func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	if ctx == null or source == null:
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	await ctx.reveal_deck_top_and_pick(source, reveal_count, pick_count)
