extends EffectStepBase
class_name StepCheckNoAllyStacks

## 아군 필드 스택 카드 수 조건 — 발동 가능 여부(can_trigger) 및 파이프라인 선행 체크
## 드루이어드: min=0 max=0 · 음유시인/바쿠 OPEN: min=1
@export_group("라인 · 대상")
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.ALL_LINES
@export var units_only: bool = true
@export_group("스택 수 조건")
@export var min_count: int = 0
## -1 이면 상한 없음. 0이면 min_count 이상이면서 max_count 이하
@export var max_count: int = -1
@export_group("체인 (선택)")
@export var store_key: String = ""


## 아군 필드 스택 수가 min/max 범위인지 선행 검사.
func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var ctx := run_ctx.game_context
	if ctx == null or source == null:
		return false
	var stack_count := ctx.count_ally_stacks(source, line_scope, units_only)
	if not store_key.is_empty():
		run_ctx.store(store_key, stack_count)
	return _passes(stack_count)


func run(_source: Node, run_ctx: EffectPipelineRunContext) -> void:
	if not evaluate_preflight(_source, run_ctx) and abort_on_fail:
		run_ctx.store("_abort", true)


func _passes(stack_count: int) -> bool:
	if stack_count < min_count:
		return not abort_on_fail
	if max_count >= 0 and stack_count > max_count:
		return not abort_on_fail
	return true
