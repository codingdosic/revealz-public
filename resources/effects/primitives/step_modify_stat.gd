extends EffectStepBase
class_name StepModifyStat

## 행동 — EffectBundle.action(ChangeStat) + value 대응
@export_group("대상")
@export var targets_key: String = "targets"
@export var use_self: bool = false
@export_group("스탯 변경")
@export var delta: int = 0
@export var apply_on_field_line: bool = true
@export_group("EffectFx")
## true면 투사체 대신 라인별 곡선 파면(자동 광역용).
@export var fx_line_wave: bool = false
## a=0이면 시전 카드 색 기본(블랙→보라). 카드마다 인스펙터에서 덮어쓰기.
@export var fx_projectile_color: Color = Color(0, 0, 0, 0)
## a=0이면 상승=녹 / 하강=보라(블랙 시전은 진보라).
@export var fx_aura_color: Color = Color(0, 0, 0, 0)
@export var fx_wave_color: Color = Color(0, 0, 0, 0)
@export var fx_wave_width: float = 0.0
@export var fx_wave_sec: float = 0.0
@export var fx_particle_count: int = 0
@export var fx_particle_radius_min: float = 0.0
@export var fx_particle_radius_max: float = 0.0
@export var fx_aura_travel_px: float = 0.0
## 시작 Y 분산 폭(0=기본). 클수록 띠→구름 느낌.
@export var fx_aura_start_band_px: float = 0.0
@export var fx_skip_hit: bool = false


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
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
		_apply_stats(source, ctx, valid)

	if play_fx:
		var opts := _build_fx_opts()
		if use_self:
			opts["self_cast"] = true
			opts["skip_hit"] = true
		if fx_line_wave:
			opts["line_wave"] = true
		ctx.begin_stat_fx(opts)
		if fx_line_wave:
			await EffectFx.await_line_wave(source, valid, delta, opts, apply_cb)
		else:
			await EffectFx.await_modify_stat(source, valid, delta, opts, apply_cb)
		ctx.end_stat_fx()
	else:
		apply_cb.call()
	ctx._refresh_line_power_ui()


## 스탯 적용 + 기록.
func _apply_stats(source: Node, ctx: EffectContext, valid: Array) -> void:
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


## 인스펙터 오버라이드만 opts에 넣는다 (0/투명=기본값).
func _build_fx_opts() -> Dictionary:
	var opts := {}
	if fx_projectile_color.a > 0.001:
		opts["projectile_color"] = fx_projectile_color
	if fx_aura_color.a > 0.001:
		opts["color"] = fx_aura_color
	if fx_wave_color.a > 0.001:
		opts["wave_color"] = fx_wave_color
	if fx_wave_width > 0.0:
		opts["wave_width"] = fx_wave_width
	if fx_wave_sec > 0.0:
		opts["wave_sec"] = fx_wave_sec
	if fx_particle_count > 0:
		opts["particle_count"] = fx_particle_count
	if fx_particle_radius_min > 0.0:
		opts["particle_radius_min"] = fx_particle_radius_min
	if fx_particle_radius_max > 0.0:
		opts["particle_radius_max"] = fx_particle_radius_max
	if fx_aura_travel_px > 0.0:
		opts["aura_travel_px"] = fx_aura_travel_px
	if fx_aura_start_band_px > 0.0:
		opts["aura_start_band_px"] = fx_aura_start_band_px
	if fx_skip_hit:
		opts["skip_hit"] = true
	return opts


func _resolve_targets(run_ctx: EffectPipelineRunContext) -> Array:
	if not targets_key.is_empty() and run_ctx.step_results.has(targets_key):
		var stored = run_ctx.step_results[targets_key]
		if stored is Array:
			return stored
	return run_ctx.current_targets
