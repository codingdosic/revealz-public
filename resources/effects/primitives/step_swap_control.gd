extends EffectStepBase
class_name StepSwapControl

## 동라인 상대 유닛과 발동 유닛의 필드 슬롯(컨트롤) 교환 — 전이 마술사 아스트로
@export var targets_key: String = "targets"
@export_group("MatchVfx")
enum TrailMode { KEEP_DEFAULT, FORCE_ON, FORCE_OFF }
@export var fx_trail: TrailMode = TrailMode.KEEP_DEFAULT
@export var fx_trail_color: Color = Color(0, 0, 0, 0)
@export var fx_trail_width: float = 0.0
@export var fx_move_sec: float = 0.0


func evaluate_preflight(source: Node, _run_ctx: EffectPipelineRunContext) -> bool:
	## can_trigger·확인 팝업 전에는 선택 스텝이 아직 실행되지 않음 — 소스 필드 배치만 검사
	if source == null or source.card_slot_card_is_in == null:
		return not abort_on_fail
	return true


## 소스·대상 유닛의 필드 슬롯(컨트롤) 교환.
func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	if ctx == null:
		return
	var targets: Array = _resolve_targets(run_ctx)
	if targets.is_empty():
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	var target = targets[0]
	if not is_instance_valid(target) or target.card_slot_card_is_in == null:
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	ctx.begin_move_vfx(_build_move_fx_opts(), source)
	await ctx.swap_field_control(source, target)
	ctx.end_move_vfx()


## 인스펙터 오버라이드만 opts에 넣는다.
func _build_move_fx_opts() -> Dictionary:
	var opts := {}
	match fx_trail:
		TrailMode.FORCE_ON:
			opts["trail"] = true
		TrailMode.FORCE_OFF:
			opts["trail"] = false
		_:
			pass
	if fx_trail_color.a > 0.001:
		opts["color"] = fx_trail_color
	if fx_trail_width > 0.0:
		opts["trail_width"] = fx_trail_width
	if fx_move_sec > 0.0:
		opts["duration"] = fx_move_sec
	return opts


func _resolve_targets(run_ctx: EffectPipelineRunContext) -> Array:
	if targets_key.is_empty():
		return []
	var stored = run_ctx.step_results.get(targets_key, [])
	if stored is Array:
		return stored
	return []
