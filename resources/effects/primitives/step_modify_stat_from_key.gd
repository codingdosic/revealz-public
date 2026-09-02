extends EffectStepBase
class_name StepModifyStatFromKey

## 저장된 값(예: banish count, 카드 SPD 등)을 delta로 사용해 스탯을 변경한다.
@export_group("대상")
@export var targets_key: String = "targets"
@export var use_self: bool = false
@export_group("값")
@export var value_key: String = ""
@export var scale: int = 1
@export var add: int = 0
@export_group("적용")
@export var apply_on_field_line: bool = true


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	var v := 0
	if not value_key.is_empty() and run_ctx.step_results.has(value_key):
		v = int(run_ctx.step_results[value_key])
	var delta := (v * scale) + add

	var targets: Array = []
	if use_self:
		targets = [source]
	else:
		targets = _resolve_targets(run_ctx)
	var valid: Array = []
	for target in targets:
		if is_instance_valid(target):
			valid.append(target)

	var play_fx := (
		delta != 0
		and ctx.current_effect_trigger not in ["PASSIVE", "STACK"]
		and not valid.is_empty()
	)
	var apply_cb := func() -> void:
		_apply_stats(source, ctx, valid, delta)

	if play_fx:
		var opts := {}
		if use_self:
			opts["self_cast"] = true
			opts["skip_hit"] = true
		ctx.begin_stat_fx(opts)
		await EffectFx.await_modify_stat(source, valid, delta, opts, apply_cb)
		ctx.end_stat_fx()
	else:
		apply_cb.call()
	ctx._refresh_line_power_ui()


## 스탯 적용 + 기록.
func _apply_stats(source: Node, ctx: EffectContext, valid: Array, delta: int) -> void:
	for target in valid:
		if not is_instance_valid(target):
			continue
		if apply_on_field_line and target.has_method("change_stat_on_field_line"):
			if (
				ctx.current_effect_trigger in ["PASSIVE", "STACK"]
				and target.has_method("apply_passive_line_bonus")
			):
				target.apply_passive_line_bonus(delta)
			else:
				target.change_stat_on_field_line(delta)
			if ctx.current_effect_trigger not in ["PASSIVE", "STACK"]:
				var line := ctx.line_of_card(target)
				ctx.record_stat_change(target, delta, line, source)
		elif target.has_method("change_stat"):
			target.change_stat(delta)
			target.update_labels()
			if ctx.current_effect_trigger not in ["PASSIVE", "STACK"]:
				ctx.record_stat_change(target, delta, -1, source)


func _resolve_targets(run_ctx: EffectPipelineRunContext) -> Array:
	if not targets_key.is_empty() and run_ctx.step_results.has(targets_key):
		var stored = run_ctx.step_results[targets_key]
		if stored is Array:
			return stored
		if stored != null:
			return [stored]
	return run_ctx.current_targets
