extends EffectStepBase
class_name StepSetFieldLineStat

@export var use_self: bool = true
@export var value: int = 10
@export var condition_key: String = ""
@export var restore_base_when_false: bool = true


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var target: Node = source if use_self else null
	if target == null or not is_instance_valid(target):
		return
	var apply := true
	if not condition_key.is_empty() and run_ctx.step_results.has(condition_key):
		apply = bool(run_ctx.step_results[condition_key])
	if apply:
		if (
			run_ctx.game_context.current_effect_trigger == "PASSIVE"
			and target.has_method("apply_passive_line_absolute")
		):
			target.apply_passive_line_absolute(value)
			# PASSIVE는 클라가 로컬 refresh로 재계산 — STAT 기록 시 delta 누적(B3) 방지
		elif target.has_method("set_field_line_stat_absolute"):
			target.set_field_line_stat_absolute(value)
			var ctx := run_ctx.game_context
			if ctx and ctx.current_effect_trigger not in ["PASSIVE", "STACK"]:
				# absolute는 delta가 아니라 현재 L/C/R 스냅샷으로 동기화
				ctx.record_stat_change(target, 0)
	elif restore_base_when_false and run_ctx.game_context.current_effect_trigger != "PASSIVE":
		if target.has_method("reset_field_line_stat_from_data"):
			target.reset_field_line_stat_from_data()
	run_ctx.game_context._refresh_line_power_ui()
