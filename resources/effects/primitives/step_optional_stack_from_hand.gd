extends EffectStepBase
class_name StepOptionalStackFromHand

## (선택) 핸드 1장 → self 스택 · 성공 시 추가 draw 1 (방랑자 엘리나)
@export var draw_count: int = 1
@export var confirm_title: String = "추가 효과"
@export var confirm_message: String = "핸드에서 카드 1장을 이 유닛에게 스택으로 넣고 추가로 1장 드로우하시겠습니까?"
@export_group("MatchVfx")
enum TrailMode { KEEP_DEFAULT, FORCE_ON, FORCE_OFF }
@export var fx_trail: TrailMode = TrailMode.KEEP_DEFAULT
@export var fx_trail_color: Color = Color(0, 0, 0, 0)
@export var fx_trail_width: float = 0.0
@export var fx_move_sec: float = 0.0


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	if ctx == null or source == null:
		return
	var em := run_ctx.effect_manager
	if em == null:
		return
	# MP-safe: route through decision owner (do not call ask_choice_dialog on authority alone).
	var confirmed := false
	if em.has_method("await_choice_dialog"):
		confirmed = await em.await_choice_dialog(
			source, confirm_title, confirm_message, "예", "아니오"
		)
	elif em.has_method("ask_choice_dialog"):
		confirmed = await em.ask_choice_dialog(confirm_title, confirm_message, "예", "아니오")
	if not confirmed:
		return
	var hand := ctx.get_hand(source.owner_side)
	if hand == null:
		return
	var candidates: Array = hand.get_hand_cards()
	if candidates.is_empty():
		return
	var picked: Array = await ctx.select_card_from(candidates, 1, source)
	if picked.is_empty():
		return
	var card: Node = picked[0]
	if not is_instance_valid(card):
		return
	ctx.begin_move_vfx(_build_move_fx_opts(), source)
	var attached_ok: bool = await ctx.attach_to_stack(card, source)
	ctx.end_move_vfx()
	if not attached_ok:
		return
	ctx.draw_cards(source.owner_side, draw_count)


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
