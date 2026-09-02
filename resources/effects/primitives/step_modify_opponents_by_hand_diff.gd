extends EffectStepBase
class_name StepModifyOpponentsByHandDiff

## 동일 라인 상대 전원 LP -(abs(양측 핸드 차이) + add) (마녀의 조수 밀리아)
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.SAME_AS_SOURCE
@export var units_only: bool = true
@export var add: int = 1
@export_group("EffectFx")
@export var fx_wave_color: Color = Color(0, 0, 0, 0)
@export var fx_wave_width: float = 0.0
@export var fx_wave_sec: float = 0.0
@export var fx_aura_color: Color = Color(0, 0, 0, 0)
@export var fx_particle_count: int = 0


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	if ctx == null or source == null:
		return
	var ally_hands := ctx.hand_count(source.owner_side)
	var opp_hands := ctx.hand_count(GameConstants.opposite_side(source.owner_side))
	var amount := absi(ally_hands - opp_hands) + add
	if amount <= 0:
		return
	var delta := -amount
	var targets := EffectZoneQuery.get_cards_in_zone(
		ctx,
		source,
		EffectTypes.RelativeSide.OPPONENT,
		EffectTypes.EffectZone.FIELD,
		line_scope,
		units_only
	)
	var valid: Array = []
	for target in targets:
		if is_instance_valid(target):
			valid.append(target)

	var apply_cb := func() -> void:
		for target in valid:
			if not is_instance_valid(target):
				continue
			if target.has_method("change_stat_on_field_line"):
				target.change_stat_on_field_line(delta)
				var line := ctx.line_of_card(target)
				ctx.record_stat_change(target, delta, line, source)

	var play_fx := (
		ctx.current_effect_trigger not in ["PASSIVE", "STACK"] and not valid.is_empty()
	)
	if play_fx:
		var opts := _build_fx_opts()
		ctx.begin_stat_fx(opts)
		await EffectFx.await_line_wave(source, valid, delta, opts, apply_cb)
		ctx.end_stat_fx()
	else:
		apply_cb.call()
	ctx._refresh_line_power_ui()


## 인스펙터 오버라이드만 opts에 넣는다.
func _build_fx_opts() -> Dictionary:
	var opts := {"line_wave": true}
	if fx_wave_color.a > 0.001:
		opts["wave_color"] = fx_wave_color
	if fx_wave_width > 0.0:
		opts["wave_width"] = fx_wave_width
	if fx_wave_sec > 0.0:
		opts["wave_sec"] = fx_wave_sec
	if fx_aura_color.a > 0.001:
		opts["color"] = fx_aura_color
	if fx_particle_count > 0:
		opts["particle_count"] = fx_particle_count
	return opts
