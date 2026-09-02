extends EffectStepBase
class_name StepModifyAllInZone

@export_group("대상")
@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER
@export var zone: EffectTypes.EffectZone = EffectTypes.EffectZone.FIELD
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.SAME_AS_SOURCE
@export var units_only: bool = true
@export var exclude_source: bool = false
@export var include_name_exact: String = ""
@export var require_token: bool = false
@export var include_types: PackedStringArray = PackedStringArray()
@export_group("스탯")
@export var delta: int = 0
@export var apply_on_field_line: bool = true


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	var targets := EffectZoneQuery.get_cards_in_zone(
		ctx,
		source,
		relative_side,
		zone,
		line_scope,
		units_only,
		exclude_source,
		"",
		false,
		false,
		run_ctx.execution_pool,
		include_name_exact,
		require_token,
		include_types
	)
	var valid: Array = []
	for target in targets:
		if is_instance_valid(target):
			valid.append(target)

	var apply_cb := func() -> void:
		for target in valid:
			if not is_instance_valid(target):
				continue
			if ctx.current_effect_trigger == "PASSIVE" and target.has_method("apply_passive_line_bonus"):
				target.apply_passive_line_bonus(delta)
			elif apply_on_field_line and target.has_method("change_stat_on_field_line"):
				target.change_stat_on_field_line(delta)
				var line := ctx.line_of_card(target)
				ctx.record_stat_change(target, delta, line, source)
			elif target.has_method("change_stat"):
				target.change_stat(delta)
				target.update_labels()
				ctx.record_stat_change(target, delta, -1, source)

	# PASSIVE: EM이 보너스 변동 후 기류. OPEN 광역: 기류 시작=스탯 동시.
	if delta != 0 and ctx.current_effect_trigger != "PASSIVE" and not valid.is_empty():
		ctx.begin_stat_fx({"aura_only": true})
		await EffectFx.await_aura_batch(valid, delta, {}, apply_cb)
		ctx.end_stat_fx()
	else:
		apply_cb.call()
	ctx._refresh_line_power_ui()
