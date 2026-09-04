class_name MatchVfxHost
extends Node2D
## MatchVfx 재생 호스트. Tween·트레일·busy 카운트. headless면 비활성.


const META_TWEEN := &"_match_vfx_tween"
const META_TRAIL := &"_match_vfx_trail"

var _active: bool = true
var _busy_count: int = 0


## headless Dedicated 등은 연출 끄고 snap만.
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_active = false


## 연출 활성 여부.
func is_vfx_active() -> bool:
	return _active


## 진행 중 이동이 있으면 true.
func is_busy() -> bool:
	return _busy_count > 0


## 이동을 시작하고 기다리지 않는다.
func play_card_move(card: Node2D, params: Dictionary) -> void:
	if not _active:
		MatchVfx.snap_card(card, params)
		_emit_slot_land_from_params(params)
		return
	_start_move(card, params)


## 이동이 끝날 때까지 await.
func await_card_move(card: Node2D, params: Dictionary) -> void:
	if not _active:
		MatchVfx.snap_card(card, params)
		_emit_slot_land_from_params(params)
		return
	var tween := _start_move(card, params)
	if tween == null:
		return
	await tween.finished


## moves: [{ "card": Node2D, "params": Dictionary }, ...] 동시 재생 후 대기.
func await_parallel_moves(moves: Array) -> void:
	if not _active:
		for item in moves:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			MatchVfx.snap_card(item.get("card") as Node2D, item.get("params", {}) as Dictionary)
		return
	var tweens: Array[Tween] = []
	for item in moves:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var card := item.get("card") as Node2D
		var params: Dictionary = item.get("params", {}) as Dictionary
		var tween := _start_move(card, params)
		if tween != null:
			tweens.append(tween)
	await MatchVfx.await_all_tweens(tweens)


## 라인 배틀: prep → lunge → impact → return.
func await_line_clash(cards: Array, clash_pos: Vector2) -> void:
	if not _active:
		return
	var states: Array = _begin_line_clash_states(cards, clash_pos)
	if states.is_empty():
		return
	_busy_count += 1
	await _await_clash_move_states(
		states,
		"pullback",
		MatchVfx.DEFAULT_BATTLE_PREP_SEC,
		Tween.TRANS_SINE,
		Tween.EASE_OUT,
		true
	)
	await _await_clash_move_states(
		states,
		"clash",
		MatchVfx.DEFAULT_BATTLE_LUNGE_SEC,
		Tween.TRANS_QUAD,
		Tween.EASE_IN,
		false
	)
	await _await_clash_impact(states, clash_pos)
	await _await_clash_move_states(
		states,
		"home",
		MatchVfx.DEFAULT_BATTLE_RETURN_SEC,
		Tween.TRANS_CUBIC,
		Tween.EASE_OUT,
		true
	)
	_finish_line_clash_states(states)
	_busy_count = maxi(0, _busy_count - 1)


## 슬롯 위 스케일 0→target. card_flip 대신 토큰 소환용.
func await_token_spawn_pop_in(card: Node2D, target_scale: Vector2) -> void:
	if not _active or card == null or not is_instance_valid(card) or not card.is_inside_tree():
		if card != null and is_instance_valid(card):
			card.scale = target_scale
		return
	_kill_card_tween(card)
	var anim := card.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.stop()
	card.scale = Vector2.ZERO
	_busy_count += 1
	var tween := card.create_tween()
	card.set_meta(META_TWEEN, tween)
	tween.tween_property(card, "scale", target_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	_busy_count = maxi(0, _busy_count - 1)
	if card.has_meta(META_TWEEN):
		card.remove_meta(META_TWEEN)
	if is_instance_valid(card):
		play_slot_land(card.global_position, "place")


## 슬롯 착지/오픈 rim flash — 사각형 테두리에서 바깥으로 팟. kind: place | open.
## --- 튜닝: MatchVfx.SLOT_LAND_* ---
func play_slot_land(world_pos: Vector2, kind: String = "place") -> void:
	if not _active or not is_inside_tree():
		return
	var color := MatchVfx.SLOT_LAND_COLOR_PLACE
	var start_size := MatchVfx.SLOT_LAND_START_SIZE
	var end_size := MatchVfx.SLOT_LAND_END_SIZE
	var sec := MatchVfx.SLOT_LAND_SEC
	var peak_a := MatchVfx.SLOT_LAND_PEAK_ALPHA
	if kind == "open":
		color = MatchVfx.SLOT_LAND_COLOR_OPEN
		end_size = MatchVfx.SLOT_LAND_OPEN_END_SIZE
		sec = MatchVfx.SLOT_LAND_OPEN_SEC
		peak_a = MatchVfx.SLOT_LAND_OPEN_PEAK_ALPHA
	var hold := MatchVfx.SLOT_LAND_HOLD_SEC
	var spread_sec := maxf(0.05, sec - hold)
	var spr := Sprite2D.new()
	spr.texture = _slot_land_texture_sharp()
	spr.centered = true
	spr.z_index = -1
	spr.z_as_relative = false
	spr.top_level = true
	spr.modulate = Color(color.r, color.g, color.b, peak_a)
	var tex_sz := float(MatchVfx.SLOT_LAND_TEX_SIZE)
	var start_scale := Vector2(start_size.x / tex_sz, start_size.y / tex_sz)
	var end_scale := Vector2(end_size.x / tex_sz, end_size.y / tex_sz)
	spr.scale = start_scale
	add_child(spr)
	spr.global_position = world_pos
	var tween := spr.create_tween()
	if hold > 0.001:
		tween.tween_interval(hold)
	tween.tween_callback(func() -> void:
		if is_instance_valid(spr):
			spr.texture = _slot_land_texture_soft()
	)
	tween.tween_property(spr, "scale", end_scale, spread_sec).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	tween.parallel().tween_property(spr, "modulate:a", 0.0, spread_sec).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(spr.queue_free)


## tilt 플립이 끝날 때까지 기다린 뒤 play_slot_land. 플립 중이 아니면 즉시.
func play_slot_land_after_flip(card: Node2D, kind: String = "open") -> void:
	if not _active or card == null or not is_instance_valid(card):
		return
	var remaining: float = CardHoverTilt.flip_remaining_sec(card)
	if remaining > 0.001:
		var tw := card.create_tween()
		tw.tween_interval(remaining)
		tw.tween_callback(func() -> void:
			if is_instance_valid(card):
				play_slot_land(card.global_position, kind)
		)
		return
	play_slot_land(card.global_position, kind)


func _emit_slot_land_from_params(params: Dictionary) -> void:
	var land_at: Variant = params.get("slot_land_at", Vector2.INF)
	if typeof(land_at) != TYPE_VECTOR2:
		return
	var pos := land_at as Vector2
	if not pos.is_finite():
		return
	play_slot_land(pos, String(params.get("slot_land_kind", "place")))


static var _slot_land_tex_sharp: Texture2D
static var _slot_land_tex_soft: Texture2D
## 텍스처 프로필 변경 시 bump.
const _SLOT_LAND_TEX_GEN := 4
static var _slot_land_tex_gen: int = 0


func _slot_land_texture_sharp() -> Texture2D:
	if _slot_land_tex_sharp != null and _slot_land_tex_gen == _SLOT_LAND_TEX_GEN:
		return _slot_land_tex_sharp
	_slot_land_tex_sharp = _build_slot_land_texture(true)
	_slot_land_tex_gen = _SLOT_LAND_TEX_GEN
	return _slot_land_tex_sharp


func _slot_land_texture_soft() -> Texture2D:
	if _slot_land_tex_soft != null and _slot_land_tex_gen == _SLOT_LAND_TEX_GEN:
		return _slot_land_tex_soft
	_slot_land_tex_soft = _build_slot_land_texture(false)
	return _slot_land_tex_soft


func _build_slot_land_texture(sharp: bool) -> Texture2D:
	var n := MatchVfx.SLOT_LAND_TEX_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := n * 0.5
	for y in n:
		for x in n:
			var u := (x + 0.5 - half) / half
			var v := (y + 0.5 - half) / half
			var d := maxf(absf(u), absf(v))
			var a := 0.0
			if sharp:
				# UV [-1,1]. 카드 테두리에 맞춘 날카로운 사각 rim.
				if d > 0.5:
					var peak := 0.78
					var sigma := 0.055
					var rim := exp(-pow(d - peak, 2) / (2.0 * sigma * sigma))
					var outer := 1.0 - smoothstep(0.9, 1.0, d)
					a = rim * outer
			else:
				# 넓은 rim + 바깥 bloom으로 자연스럽게 퍼짐.
				if d > 0.42:
					var rim := exp(-pow(d - 0.62, 2) / (2.0 * 0.16 * 0.16))
					var bloom := exp(-pow(maxf(d - 0.48, 0.0), 2) / (2.0 * 0.22 * 0.22)) * 0.55
					var outer := 1.0 - smoothstep(0.88, 1.0, d)
					a = clampf((rim + bloom) * outer, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


## Tween을 만들고 시작한다. duration<=0 이면 snap 후 null.
func _start_move(card: Node2D, params: Dictionary) -> Tween:
	if card == null or not is_instance_valid(card):
		return null
	if not card.is_inside_tree():
		MatchVfx.snap_card(card, params)
		return null

	var duration := float(params.get("duration", MatchVfx.DEFAULT_HAND_MOVE_SEC))
	if duration <= 0.0:
		MatchVfx.snap_card(card, params)
		_emit_slot_land_from_params(params)
		return null

	_kill_card_tween(card)

	MatchVfx.apply_face(card, params)

	if params.has("from"):
		card.global_position = params["from"] as Vector2

	var from_pos := card.global_position
	var to_pos := params.get("to", from_pos) as Vector2
	var to_rot := float(params.get("to_rotation", params.get("rotation", card.rotation)))
	var trail_on := bool(params.get("trail", false))
	var trail_color := params.get("color", MatchVfx.DEFAULT_TRAIL_COLOR) as Color
	var trail_width := float(params.get("trail_width", MatchVfx.DEFAULT_TRAIL_WIDTH))
	var trail_fade := float(params.get("trail_fade_sec", MatchVfx.DEFAULT_TRAIL_FADE_SEC))

	var trail: Line2D = null
	if trail_on:
		trail = _make_trail(from_pos, trail_color, trail_width)
		card.set_meta(META_TRAIL, trail)

	var tween := card.create_tween()
	tween.set_parallel(true)
	card.set_meta(META_TWEEN, tween)
	_busy_count += 1

	tween.tween_property(card, "global_position", to_pos, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation", to_rot, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if trail != null:
		tween.tween_method(
			_update_trail_endpoint.bind(trail, from_pos),
			from_pos,
			to_pos,
			duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.finished.connect(
		_on_move_finished.bind(
			card,
			trail,
			trail_fade,
			params.get("slot_land_at", Vector2.INF) as Vector2,
			String(params.get("slot_land_kind", "place"))
		),
		CONNECT_ONE_SHOT
	)
	return tween


## 트레일 끝점을 현재 이동 위치에 맞춘다. tween 보간값(pos)이 1번째.
func _update_trail_endpoint(pos: Vector2, trail: Line2D, from_pos: Vector2) -> void:
	if trail == null or not is_instance_valid(trail):
		return
	if trail.get_point_count() >= 2:
		trail.set_point_position(1, pos)
	else:
		trail.clear_points()
		trail.add_point(from_pos)
		trail.add_point(pos)


## 이동 종료 시 busy·트레일 정리 · 선택적 슬롯 착지 FX.
func _on_move_finished(
	card: Node2D,
	trail: Line2D,
	fade_sec: float = MatchVfx.DEFAULT_TRAIL_FADE_SEC,
	land_at: Vector2 = Vector2.INF,
	land_kind: String = "place"
) -> void:
	_busy_count = maxi(0, _busy_count - 1)
	if card != null and is_instance_valid(card) and card.has_meta(META_TWEEN):
		card.remove_meta(META_TWEEN)
	if card != null and is_instance_valid(card) and card.has_meta(META_TRAIL):
		card.remove_meta(META_TRAIL)
	_fade_out_trail(trail, fade_sec)
	if land_at.is_finite():
		play_slot_land(land_at, land_kind)


## 카드에 걸린 MatchVfx Tween을 끊는다.
func _kill_card_tween(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	if card.has_meta(META_TRAIL):
		var old_trail: Variant = card.get_meta(META_TRAIL)
		card.remove_meta(META_TRAIL)
		if old_trail is Line2D and is_instance_valid(old_trail):
			(old_trail as Line2D).queue_free()
	if not card.has_meta(META_TWEEN):
		return
	var old: Variant = card.get_meta(META_TWEEN)
	card.remove_meta(META_TWEEN)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
		_busy_count = maxi(0, _busy_count - 1)


## 시작점 트레일 Line2D를 만든다. top_level+원점 → 점은 월드(global) 좌표.
func _make_trail(from_pos: Vector2, color: Color, width: float = MatchVfx.DEFAULT_TRAIL_WIDTH) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 80
	line.z_as_relative = false
	line.top_level = true
	add_child(line)
	line.global_position = Vector2.ZERO
	line.add_point(from_pos)
	line.add_point(from_pos)
	return line


## 트레일을 짧게 페이드 후 제거한다.
func _fade_out_trail(trail: Line2D, fade_sec: float = MatchVfx.DEFAULT_TRAIL_FADE_SEC) -> void:
	if trail == null or not is_instance_valid(trail):
		return
	var fade := trail.create_tween()
	var dur := fade_sec if fade_sec > 0.0 else MatchVfx.DEFAULT_TRAIL_FADE_SEC
	fade.tween_property(trail, "modulate:a", 0.0, dur)
	fade.tween_callback(trail.queue_free)


func _begin_line_clash_states(cards: Array, line_clash: Vector2) -> Array:
	var states: Array = []
	for item in cards:
		var card := item as Node2D
		if card == null or not is_instance_valid(card) or not card.is_inside_tree():
			continue
		_kill_card_tween(card)
		var home := card.global_position
		var home_scale := card.scale
		var orig_z := card.z_index
		var side := int(card.get("owner_side")) if card.get("owner_side") != null else -1
		var pullback_dir := _pullback_dir_for_clash(side)
		# X(슬롯 열) 유지 — Y만 pullback / lunge
		var pullback := Vector2(home.x, home.y + pullback_dir.y * MatchVfx.DEFAULT_BATTLE_PULLBACK_PX)
		var clash_target := _clash_target_for_card(home, line_clash)
		var prep_scale := home_scale * MatchVfx.DEFAULT_BATTLE_PREP_SCALE
		var punch_scale := home_scale * MatchVfx.DEFAULT_BATTLE_IMPACT_SCALE
		card.z_index = 20
		states.append({
			"card": card,
			"home": home,
			"home_scale": home_scale,
			"pullback": pullback,
			"clash": clash_target,
			"prep_scale": prep_scale,
			"punch_scale": punch_scale,
			"orig_z": orig_z,
		})
	return states


func _clash_target_for_card(home: Vector2, line_clash: Vector2) -> Vector2:
	var frac := clampf(MatchVfx.DEFAULT_BATTLE_LUNGE_Y_FRAC, 0.0, 1.0)
	var y := lerpf(home.y, line_clash.y, frac)
	return Vector2(home.x, y)


func _pullback_dir_for_clash(side: int) -> Vector2:
	if side == int(GameConstants.Side.PLAYER):
		return Vector2(0.0, 1.0)
	if side == int(GameConstants.Side.OPPONENT):
		return Vector2(0.0, -1.0)
	return Vector2.ZERO


func _target_for_state(state: Dictionary, target_key: String) -> Vector2:
	match target_key:
		"pullback":
			return state["pullback"] as Vector2
		"clash":
			return state["clash"] as Vector2
		_:
			return state["home"] as Vector2


func _scale_for_state(state: Dictionary, target_key: String, with_scale: bool) -> Vector2:
	if not with_scale:
		return state["home_scale"] as Vector2
	match target_key:
		"pullback", "home":
			return state["home_scale"] as Vector2
		"clash":
			return state["prep_scale"] as Vector2
		_:
			return state["home_scale"] as Vector2


func _await_clash_move_states(
	states: Array,
	target_key: String,
	duration: float,
	trans: Tween.TransitionType,
	ease: Tween.EaseType,
	with_scale: bool
) -> void:
	var tweens := _start_clash_move_states(states, target_key, duration, trans, ease, with_scale)
	if tweens.is_empty():
		return
	await MatchVfx.await_all_tweens(tweens)


func _start_clash_move_states(
	states: Array,
	target_key: String,
	duration: float,
	trans: Tween.TransitionType,
	ease: Tween.EaseType,
	with_scale: bool
) -> Array[Tween]:
	var tweens: Array[Tween] = []
	if duration <= 0.0:
		return tweens
	for state in states:
		var card: Node2D = state["card"]
		if card == null or not is_instance_valid(card):
			continue
		var to_pos: Vector2 = _target_for_state(state, target_key)
		var to_scale: Vector2 = _scale_for_state(state, target_key, with_scale)
		var tween := card.create_tween()
		card.set_meta(META_TWEEN, tween)
		tween.set_parallel(true)
		tween.tween_property(card, "global_position", to_pos, duration).set_trans(trans).set_ease(ease)
		if with_scale:
			tween.tween_property(card, "scale", to_scale, duration).set_trans(trans).set_ease(ease)
		tween.finished.connect(_on_clash_phase_finished.bind(card), CONNECT_ONE_SHOT)
		tweens.append(tween)
	return tweens


func _on_clash_phase_finished(card: Node2D) -> void:
	if card != null and is_instance_valid(card) and card.has_meta(META_TWEEN):
		card.remove_meta(META_TWEEN)


func _await_clash_impact(states: Array, _line_clash: Vector2) -> void:
	for state in states:
		var card: Node2D = state["card"]
		if card == null or not is_instance_valid(card):
			continue
		card.global_position = state["clash"] as Vector2

	var tweens: Array[Tween] = []
	for state in states:
		var card: Node2D = state["card"]
		if card == null or not is_instance_valid(card):
			continue
		var punch_scale: Vector2 = state["punch_scale"]
		var tween := card.create_tween()
		card.set_meta(META_TWEEN, tween)
		tween.tween_property(
			card, "scale", punch_scale, MatchVfx.DEFAULT_BATTLE_IMPACT_PUNCH_SEC
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(MatchVfx.DEFAULT_BATTLE_IMPACT_HOLD_SEC)
		tween.finished.connect(_on_clash_phase_finished.bind(card), CONNECT_ONE_SHOT)
		tweens.append(tween)

	await MatchVfx.await_all_tweens(tweens)

	var cam_tw := _start_field_camera_shake()
	if cam_tw != null:
		await cam_tw.finished

	var shake_tweens: Array[Tween] = []
	for state in states:
		var card: Node2D = state["card"]
		if card == null or not is_instance_valid(card):
			continue
		var tw := _start_battle_hit_shake(card, card.global_position)
		if tw != null:
			shake_tweens.append(tw)
	if not shake_tweens.is_empty():
		await MatchVfx.await_all_tweens(shake_tweens)


func _start_battle_hit_shake(card: Node2D, origin: Vector2) -> Tween:
	if card == null or not is_instance_valid(card) or not card.is_inside_tree():
		return null
	card.global_position = origin
	var steps := MatchVfx.DEFAULT_BATTLE_HIT_SHAKE_STEPS
	var step_sec := MatchVfx.DEFAULT_BATTLE_HIT_SHAKE_SEC / float(maxi(steps, 1))
	var px := MatchVfx.DEFAULT_BATTLE_HIT_SHAKE_PX
	var tween := card.create_tween()
	for _i in range(steps):
		var ox := randf_range(-px, px)
		var oy := randf_range(-px, px)
		tween.tween_property(card, "global_position", origin + Vector2(ox, oy), step_sec)
	tween.tween_property(card, "global_position", origin, step_sec * 0.5)
	tween.finished.connect(_on_battle_hit_shake_finished.bind(card, origin), CONNECT_ONE_SHOT)
	return tween


func _on_battle_hit_shake_finished(card: Node2D, origin: Vector2) -> void:
	if not is_instance_valid(card):
		return
	card.global_position = origin


func _start_field_camera_shake() -> Tween:
	return _start_field_camera_shake_params(
		MatchVfx.DEFAULT_BATTLE_CAMERA_SHAKE_SEC,
		float(MatchVfx.DEFAULT_BATTLE_CAMERA_SHAKE_PX),
		MatchVfx.DEFAULT_BATTLE_CAMERA_SHAKE_STEPS
	)


## 공개 플립 착지용 약한 필드 쉐이크.
func play_flip_land_camera_shake() -> void:
	if not _active:
		return
	_start_field_camera_shake_params(
		MatchVfx.DEFAULT_FLIP_LAND_CAMERA_SHAKE_SEC,
		MatchVfx.DEFAULT_FLIP_LAND_CAMERA_SHAKE_PX,
		MatchVfx.DEFAULT_FLIP_LAND_CAMERA_SHAKE_STEPS
	)


func _start_field_camera_shake_params(sec: float, px: float, steps: int) -> Tween:
	var field := _resolve_field_shake_root()
	if field == null:
		return null
	var origin := field.position
	var step_count := maxi(steps, 1)
	var step_sec := sec / float(step_count)
	var tween := field.create_tween()
	for _i in range(step_count):
		var ox := randf_range(-px, px)
		var oy := randf_range(-px, px)
		tween.tween_property(field, "position", origin + Vector2(ox, oy), step_sec)
	tween.tween_property(field, "position", origin, step_sec * 0.5)
	tween.finished.connect(_on_field_shake_finished.bind(field, origin), CONNECT_ONE_SHOT)
	return tween


func _on_field_shake_finished(field: Node2D, origin: Vector2) -> void:
	if not is_instance_valid(field):
		return
	field.position = origin


func _resolve_field_shake_root() -> Node2D:
	var n: Node = self
	while n:
		if str(n.name) == "Field" and n is Node2D:
			return n as Node2D
		n = n.get_parent()
	return null


func _finish_line_clash_states(states: Array) -> void:
	for state in states:
		var card: Node2D = state["card"]
		if card == null or not is_instance_valid(card):
			continue
		_kill_card_tween(card)
		card.global_position = state["home"] as Vector2
		card.scale = state["home_scale"] as Vector2
		card.z_index = int(state.get("orig_z", card.z_index))
