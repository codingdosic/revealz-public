class_name CardHoverTilt
extends RefCounted
## 인게임 카드: 강체 기울임 + 레어도 아웃라인 + Y축 실플립 + 오픈 라인 충격.
## CardImage = tilt+outline / CardBackImage = tilt only (rarity_tier=0).


const SHADER_PATH := "res://shaders/card_rigid_tilt.gdshader"
## Area2D 충돌(158×220) 반사이즈 — 로컬 마우스를 -1..1로 정규화.
const HALF_EXTENTS := Vector2(79.0, 110.0)
const MAX_TILT_DEG := 20.0
## 지수 감쇠 — 낮으면 커서를 뒤따라 꿀렁, 높으면 면에 붙음.
const FOLLOW_STIFFNESS := 28.0
const SETTLE_EPS := 0.04

const META_HOVER := &"_card_tilt_hover"
const META_TX := &"_card_tilt_x"
const META_TY := &"_card_tilt_y"
const META_MAT_FRONT := &"_card_tilt_mat_front"
const META_MAT_BACK := &"_card_tilt_mat_back"
const META_FLIPPING := &"_card_tilt_flipping"
const META_FLIP_TWEEN := &"_card_tilt_flip_tween"
const META_FLIP_START_MSEC := &"_card_tilt_flip_start_msec"
const META_FLIP_TOTAL_SEC := &"_card_tilt_flip_total_sec"
const META_FLIP_SWAP_SEC := &"_card_tilt_flip_swap_sec"
const META_FLIP_LIFT := &"_card_tilt_flip_lift"
const META_FLIP_BASE_POS := &"_card_tilt_flip_base_pos"
const META_FLIP_BASE_SCALE := &"_card_tilt_flip_base_scale"
const META_FLIP_BASE_Z := &"_card_tilt_flip_base_z"
const META_SHOCK_TWEEN := &"_card_open_shock_tween"
const META_SHOCK_BASE_POS := &"_card_open_shock_base_pos"
const META_SHOCK_DIR := &"_card_open_shock_dir"
const META_SHOCK_BASE_DIR := &"_card_open_shock_base_dir"
const META_SHOCK_STRENGTH := &"_card_open_shock_strength"
const META_SHOCK_PULSE_AMP := &"_card_open_shock_pulse_amp"
const META_SHOCK_ACTIVE := &"_card_open_shock_active"

static var _shader: Shader


## 호버 기울임 on/off. off면 0으로 보간 후 process 정지. 플립 중 on은 무시.
static func set_hovering(card: Node2D, enabled: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	if enabled and is_flipping(card):
		return
	_ensure_materials(card)
	card.set_meta(META_HOVER, enabled)
	if enabled:
		card.set_process(true)
	elif not card.has_meta(META_TX):
		card.set_meta(META_TX, 0.0)
		card.set_meta(META_TY, 0.0)


## instance_rarity를 앞면 material에 반영. 호버 전에도 아웃라인이 보이도록 init에서 호출.
static func apply_rarity(card: Node2D, tier: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	_ensure_materials(card)
	var t := clampi(tier, CardRarity.Tier.N, CardRarity.Tier.UR)
	# 뒷면이 보이는 동안엔 아웃라인 끄기 (공유 방지 — front mat만 사용).
	var show_fx := CardRarity.shows_display(t)
	if card.has_method("_is_showing_card_back") and card._is_showing_card_back():
		show_fx = false
	var mat: Variant = card.get_meta(META_MAT_FRONT, null)
	if mat is ShaderMaterial and is_instance_valid(mat):
		var sm := mat as ShaderMaterial
		sm.set_shader_parameter("rarity_tier", float(t if show_fx else CardRarity.Tier.N))
		sm.set_shader_parameter("rarity_hint", 0.0)
		var accent := CardRarity.accent_of(t)
		sm.set_shader_parameter("rarity_accent", Vector4(accent.r, accent.g, accent.b, accent.a))
		CardRarityFoil.bind_holo_maps(sm)


## Y축 원근 플립. 옆면에서 on_edge_swap.
## with_lift: 공개(뒷→앞)용 — 뜨며 뒤집고 앞면 최고점 후 쾅 착지.
static func play_y_flip(
	card: Node2D,
	on_edge_swap: Callable = Callable(),
	with_lift: bool = false
) -> Tween:
	if card == null or not is_instance_valid(card):
		return null
	if DisplayServer.get_name() == "headless":
		return null
	_ensure_materials(card)
	abort_flip(card)
	abort_open_shock(card)
	card.set_meta(META_HOVER, false)
	card.set_meta(META_TX, 0.0)
	card.set_meta(META_TY, 0.0)
	_apply_tilt(card, 0.0, 0.0)
	card.set_process(false)

	var flip_sec := GameConstants.CARD_FLIP_TOTAL_SEC
	var half := GameConstants.CARD_FLIP_SWAP_SEC
	var second := maxf(0.01, flip_sec - half)
	var edge := GameConstants.CARD_FLIP_EDGE_DEG
	var pitch := GameConstants.CARD_FLIP_PITCH_DEG
	var lift_at_swap := GameConstants.CARD_FLIP_LIFT_AT_SWAP
	var peak_hold := GameConstants.CARD_FLIP_PEAK_HOLD_SEC if with_lift else 0.0
	var slam := GameConstants.CARD_FLIP_SLAM_SEC if with_lift else 0.0
	var total := flip_sec + peak_hold + slam

	if with_lift:
		_store_lift_base(card)

	card.set_meta(META_FLIPPING, true)
	card.set_meta(META_FLIP_LIFT, with_lift)
	card.set_meta(META_FLIP_START_MSEC, Time.get_ticks_msec())
	card.set_meta(META_FLIP_TOTAL_SEC, total)
	card.set_meta(META_FLIP_SWAP_SEC, half)

	var tw := card.create_tween()
	card.set_meta(META_FLIP_TWEEN, tw)
	# 0 → +edge (접기) + 상승 → 교체 → -edge → 0 (앞면) 최고점 → 잠깐 멈춤 → 쾅 착지
	tw.set_parallel(true)
	tw.tween_method(func(y: float) -> void: _flip_tilt_sample(y, card, edge, pitch), 0.0, edge, half) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if with_lift:
		tw.tween_method(func(a: float) -> void: _apply_flip_lift(card, a), 0.0, lift_at_swap, half) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain()
	tw.set_parallel(false)
	tw.tween_callback(func() -> void: _flip_edge_swap(card, on_edge_swap, edge, pitch))
	tw.set_parallel(true)
	tw.tween_method(func(y: float) -> void: _flip_tilt_sample(y, card, edge, pitch), -edge, 0.0, second) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if with_lift:
		tw.tween_method(func(a: float) -> void: _apply_flip_lift(card, a), lift_at_swap, 1.0, second) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain()
	tw.set_parallel(false)
	if with_lift:
		if peak_hold > 0.001:
			tw.tween_interval(peak_hold)
		# BACK+IN: 가속 착지 후 살짝 눌렸다가 복귀. 착지 임팩트 시점에 약한 카메라 쉐이크.
		tw.set_parallel(true)
		tw.tween_method(func(a: float) -> void: _apply_flip_lift(card, a), 1.0, 0.0, slam) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: MatchVfx.play_flip_land_camera_shake(card)) \
			.set_delay(slam * 0.72)
		tw.chain()
		tw.set_parallel(false)
	tw.tween_callback(func() -> void: _flip_finished(card))
	return tw


static func _flip_tilt_sample(tilt_y: float, card: Node2D, edge: float, pitch: float) -> void:
	if not is_instance_valid(card):
		return
	var t := clampf(absf(tilt_y) / maxf(edge, 0.001), 0.0, 1.0)
	_set_tilt_meta(card, pitch * t, tilt_y)


static func _flip_edge_swap(card: Node2D, on_edge_swap: Callable, edge: float, pitch: float) -> void:
	if not is_instance_valid(card):
		return
	if on_edge_swap.is_valid():
		on_edge_swap.call()
	_set_tilt_meta(card, pitch, -edge)


static func _store_lift_base(card: Node2D) -> void:
	card.set_meta(META_FLIP_BASE_POS, card.position)
	card.set_meta(META_FLIP_BASE_SCALE, card.scale)
	card.set_meta(META_FLIP_BASE_Z, card.z_index)
	card.z_index = int(card.get_meta(META_FLIP_BASE_Z)) + GameConstants.CARD_FLIP_LIFT_Z


## amount 0=원위치 · 1=최고점(위+확대).
static func _apply_flip_lift(card: Node2D, amount: float) -> void:
	if not is_instance_valid(card):
		return
	if not card.has_meta(META_FLIP_BASE_POS):
		return
	var a := clampf(amount, -0.15, 1.25)
	var base_pos: Vector2 = card.get_meta(META_FLIP_BASE_POS) as Vector2
	var base_scale: Vector2 = card.get_meta(META_FLIP_BASE_SCALE) as Vector2
	var lift_t := clampf(a, 0.0, 1.0)
	card.position = base_pos + Vector2(0.0, -GameConstants.CARD_FLIP_LIFT_PX * a)
	var s := lerpf(1.0, GameConstants.CARD_FLIP_LIFT_SCALE, lift_t)
	# 착지 오버슈트(a<0) 때 살짝 납작
	if a < 0.0:
		s = lerpf(1.0, 0.94, clampf(-a / 0.15, 0.0, 1.0))
	card.scale = base_scale * s


static func _restore_lift_base(card: Node2D) -> void:
	if not is_instance_valid(card):
		return
	if card.has_meta(META_FLIP_BASE_POS):
		card.position = card.get_meta(META_FLIP_BASE_POS) as Vector2
	if card.has_meta(META_FLIP_BASE_SCALE):
		card.scale = card.get_meta(META_FLIP_BASE_SCALE) as Vector2
	if card.has_meta(META_FLIP_BASE_Z):
		card.z_index = int(card.get_meta(META_FLIP_BASE_Z))


static func _flip_finished(card: Node2D) -> void:
	if not is_instance_valid(card):
		return
	_restore_lift_base(card)
	_clear_flip_meta(card)
	snap_flat(card)


static func is_flipping(card: Node2D) -> bool:
	return card != null and is_instance_valid(card) and bool(card.get_meta(META_FLIPPING, false))


static func get_flip_tween(card: Node2D) -> Tween:
	if card == null or not is_instance_valid(card):
		return null
	var tw: Variant = card.get_meta(META_FLIP_TWEEN, null)
	if tw is Tween and (tw as Tween).is_valid():
		return tw as Tween
	return null


## 플립 종료까지 남은 초. 플립 중이 아니면 0.
static func flip_remaining_sec(card: Node2D) -> float:
	if not is_flipping(card):
		return 0.0
	var start_msec := int(card.get_meta(META_FLIP_START_MSEC, 0))
	var total := float(card.get_meta(META_FLIP_TOTAL_SEC, GameConstants.CARD_FLIP_TOTAL_SEC))
	var elapsed := maxf(0.0, float(Time.get_ticks_msec() - start_msec) * 0.001)
	return maxf(0.0, total - elapsed)


## 면 교체 시점까지 남은 초.
static func flip_sec_until_swap(card: Node2D) -> float:
	if not is_flipping(card):
		return 0.0
	var start_msec := int(card.get_meta(META_FLIP_START_MSEC, 0))
	var swap_at := float(card.get_meta(META_FLIP_SWAP_SEC, GameConstants.CARD_FLIP_SWAP_SEC))
	var elapsed := maxf(0.0, float(Time.get_ticks_msec() - start_msec) * 0.001)
	return maxf(0.0, swap_at - elapsed)


## 진행 중 Y플립 트윈을 끊고 평평하게(상승 위치도 복원).
static func abort_flip(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	var tw: Variant = card.get_meta(META_FLIP_TWEEN, null)
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	_restore_lift_base(card)
	_clear_flip_meta(card)


## 매 프레임: 커서 쪽 모서리가 화면 안쪽(축소)으로 가도록 tilt 갱신.
static func process(card: Node2D, delta: float) -> void:
	if card == null or not is_instance_valid(card):
		return
	if is_flipping(card):
		return
	# 오픈 충격 틸트 중엔 호버 보간을 끼우지 않음.
	if bool(card.get_meta(META_SHOCK_ACTIVE, false)):
		return
	var hovering := bool(card.get_meta(META_HOVER, false))
	# Face/zone 무효면 호버 메타만 끈다 (스케일은 CardManager가 담당).
	if hovering and not _is_face_tilt_valid(card):
		card.set_meta(META_HOVER, false)
		hovering = false
	var target_x := 0.0
	var target_y := 0.0
	if hovering:
		var local := card.get_local_mouse_position()
		var nx := clampf(local.x / HALF_EXTENTS.x, -1.0, 1.0)
		var ny := clampf(local.y / HALF_EXTENTS.y, -1.0, 1.0)
		# 우측(+x) → tilt_y+ (우측 축소). 하단(+y) → tilt_x- (하단 축소).
		target_y = nx * MAX_TILT_DEG
		target_x = -ny * MAX_TILT_DEG

	var cur_x := float(card.get_meta(META_TX, 0.0))
	var cur_y := float(card.get_meta(META_TY, 0.0))
	var t := 1.0 - exp(-FOLLOW_STIFFNESS * delta)
	cur_x = lerpf(cur_x, target_x, t)
	cur_y = lerpf(cur_y, target_y, t)
	card.set_meta(META_TX, cur_x)
	card.set_meta(META_TY, cur_y)
	_apply_tilt(card, cur_x, cur_y)

	if not hovering and absf(cur_x) < SETTLE_EPS and absf(cur_y) < SETTLE_EPS:
		card.set_meta(META_TX, 0.0)
		card.set_meta(META_TY, 0.0)
		_apply_tilt(card, 0.0, 0.0)
		card.set_process(false)


## 앞면·허용 zone일 때만 tilt 유지.
static func _is_face_tilt_valid(card: Node2D) -> bool:
	if not card.visible:
		return false
	var zone: Variant = card.get("zone")
	if zone != null:
		var z := int(zone)
		if z == EffectTypes.Location.GRAVE \
			or z == EffectTypes.Location.BANISH \
			or z == EffectTypes.Location.DECK:
			return false
	if card.has_method("_is_showing_card_back") and card._is_showing_card_back():
		return false
	var rs: Variant = card.get("reveal_state")
	if rs == null:
		return true
	return rs in [
		GameConstants.RevealState.HAND,
		GameConstants.RevealState.SETTING_PREVIEW,
		GameConstants.RevealState.REVEALED,
	]


## 플립/드래그 등으로 즉시 평평하게.
static func snap_flat(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.set_meta(META_HOVER, false)
	card.set_meta(META_TX, 0.0)
	card.set_meta(META_TY, 0.0)
	_apply_tilt(card, 0.0, 0.0)
	card.set_process(false)


## 오픈 충격: strength 0~1. dir=기존→오픈.
## 3단 감쇠(근측→원측→근측) + 미세 노이즈. 피벗은 들린 쪽의 반대편.
static func play_open_shock(card: Node2D, strength: float, dir: Vector2) -> void:
	if card == null or not is_instance_valid(card):
		return
	if DisplayServer.get_name() == "headless":
		return
	if is_flipping(card):
		return
	var s := clampf(strength, 0.0, 1.0)
	if s < 0.04:
		return
	_ensure_materials(card)
	abort_open_shock(card)
	var d := dir
	if d.length_squared() < 0.0001:
		d = Vector2.RIGHT
	else:
		d = d.normalized()
	card.set_meta(META_HOVER, false)
	card.set_meta(META_SHOCK_ACTIVE, true)
	card.set_meta(META_SHOCK_BASE_POS, card.position)
	card.set_meta(META_SHOCK_BASE_DIR, d)
	card.set_meta(META_SHOCK_DIR, d)
	card.set_meta(META_SHOCK_STRENGTH, s)
	card.set_meta(META_SHOCK_PULSE_AMP, 1.0)
	card.set_process(false)
	var tw := card.create_tween()
	card.set_meta(META_SHOCK_TWEEN, tw)
	tw.set_parallel(false)
	# 1: 오픈 쪽 ↑ → 2: 반대쪽 ↑ → 3: 다시 오픈 쪽 ↑ (점점 약하게)
	_append_shock_pulse(tw, card, 1.0, 1.0)
	_append_shock_pulse(tw, card, -1.0, GameConstants.CARD_OPEN_SHOCK_AMP2)
	_append_shock_pulse(tw, card, 1.0, GameConstants.CARD_OPEN_SHOCK_AMP3)
	tw.tween_callback(func() -> void: _finish_open_shock(card))


## side_sign +1=오픈 쪽 들림, -1=반대쪽. amp_mul에 노이즈를 섞어 펄스를 붙인다.
static func _append_shock_pulse(
	tw: Tween,
	card: Node2D,
	side_sign: float,
	amp_mul: float
) -> void:
	var noise := GameConstants.CARD_OPEN_SHOCK_NOISE
	var amp := amp_mul * randf_range(1.0 - noise, 1.0 + noise)
	var up_sec := GameConstants.CARD_OPEN_SHOCK_UP_SEC * randf_range(1.0 - noise, 1.0 + noise)
	var down_sec := GameConstants.CARD_OPEN_SHOCK_DOWN_SEC * randf_range(1.0 - noise, 1.0 + noise)
	# 방향에 작은 직교 노이즈 (너무 기계적이지 않게)
	var jx := randf_range(-noise, noise)
	var jy := randf_range(-noise, noise)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(card):
			return
		var base: Vector2 = card.get_meta(META_SHOCK_BASE_DIR, Vector2.RIGHT) as Vector2
		var lift := (base * side_sign + Vector2(jx, jy))
		if lift.length_squared() < 0.0001:
			lift = base * side_sign
		card.set_meta(META_SHOCK_DIR, lift.normalized())
		card.set_meta(META_SHOCK_PULSE_AMP, amp)
	)
	tw.tween_method(func(a: float) -> void: _apply_open_shock(card, a), 0.0, 1.0, up_sec) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void: _apply_open_shock(card, a), 1.0, 0.0, down_sec) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## 오픈 플립(+lift slam)과 라인 충격 3단이 끝날 때까지의 대기 시간(초).
static func open_reveal_fx_wait_sec() -> float:
	var flip_end := (
		GameConstants.CARD_FLIP_TOTAL_SEC
		+ GameConstants.CARD_FLIP_PEAK_HOLD_SEC
		+ GameConstants.CARD_FLIP_SLAM_SEC
	)
	var shock_start := (
		GameConstants.CARD_FLIP_TOTAL_SEC
		+ GameConstants.CARD_FLIP_PEAK_HOLD_SEC
		+ GameConstants.CARD_FLIP_SLAM_SEC * GameConstants.CARD_OPEN_SHOCK_SLAM_AT
	)
	var pulse := (
		GameConstants.CARD_OPEN_SHOCK_UP_SEC + GameConstants.CARD_OPEN_SHOCK_DOWN_SEC
	) * (1.0 + GameConstants.CARD_OPEN_SHOCK_NOISE)
	var shock_end := shock_start + pulse * 3.0
	return maxf(flip_end, shock_end) + 0.03


## 라인 충격을 예약한 뒤, 오픈·충격 연출이 끝날 때까지 await.
static func await_open_reveal_fx(opening_cards: Array, field_manager: Node) -> void:
	if opening_cards.is_empty():
		return
	play_line_open_shocks(opening_cards, field_manager)
	var sec := open_reveal_fx_wait_sec()
	if sec <= 0.001:
		return
	var host: Node = null
	for c in opening_cards:
		if c is Node and is_instance_valid(c) and (c as Node).is_inside_tree():
			host = c as Node
			break
	if host == null and field_manager != null and is_instance_valid(field_manager) \
		and field_manager.is_inside_tree():
		host = field_manager
	if host == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			await tree.create_timer(sec).timeout
		return
	await host.get_tree().create_timer(sec).timeout


## 오픈 플립이 쾅 착지하는 시점에 맞춰 라인 충격을 예약한다.
static func play_line_open_shocks(opening_cards: Array, field_manager: Node) -> void:
	if field_manager == null or opening_cards.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		return
	if not field_manager.has_method("get_slots_for_side_line"):
		return
	var openers: Array[Node2D] = []
	for c in opening_cards:
		if c is Node2D and is_instance_valid(c):
			openers.append(c as Node2D)
	if openers.is_empty():
		return
	# 플립 회전 + 최고점 홀드 + slam 임팩트
	var delay := (
		GameConstants.CARD_FLIP_TOTAL_SEC
		+ GameConstants.CARD_FLIP_PEAK_HOLD_SEC
		+ GameConstants.CARD_FLIP_SLAM_SEC * GameConstants.CARD_OPEN_SHOCK_SLAM_AT
	)
	var host := openers[0]
	var sched := host.create_tween()
	sched.tween_interval(delay)
	sched.tween_callback(func() -> void:
		_emit_line_open_shocks(openers, field_manager)
	)


static func _emit_line_open_shocks(openers: Array[Node2D], field_manager: Node) -> void:
	if field_manager == null or not is_instance_valid(field_manager):
		return
	var valid_openers: Array[Node2D] = []
	for opener in openers:
		if opener != null and is_instance_valid(opener):
			valid_openers.append(opener)
	if valid_openers.is_empty():
		return
	var falloff := maxf(GameConstants.CARD_OPEN_SHOCK_FALLOFF_PX, 1.0)
	var best: Dictionary = {}  # id -> {card, strength, dir}
	for opener in valid_openers:
		var slot: Variant = opener.get("card_slot_card_is_in")
		if slot == null or not is_instance_valid(slot):
			continue
		var side: GameConstants.Side = slot.side
		var line: GameConstants.Line = slot.line
		for sl in field_manager.get_slots_for_side_line(side, line):
			if sl == null or not is_instance_valid(sl):
				continue
			var other: Node2D = sl.card_in_slot as Node2D
			if other == null or not is_instance_valid(other):
				continue
			if other in valid_openers:
				continue
			var to_open: Vector2 = opener.global_position - other.global_position
			var dist := to_open.length()
			var strength := clampf(1.0 - dist / falloff, 0.0, 1.0)
			var key := other.get_instance_id()
			if best.has(key):
				var prev: Dictionary = best[key]
				if strength > float(prev["strength"]):
					prev["strength"] = strength
					prev["dir"] = to_open
			else:
				best[key] = {"card": other, "strength": strength, "dir": to_open}
	for key in best:
		var entry: Dictionary = best[key]
		play_open_shock(
			entry["card"] as Node2D,
			float(entry["strength"]),
			entry["dir"] as Vector2
		)


static func abort_open_shock(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	var tw: Variant = card.get_meta(META_SHOCK_TWEEN, null)
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	_restore_open_shock_base(card)
	_clear_open_shock_meta(card)


## amount 0~1. META_SHOCK_DIR 쪽 모서리가 들리며, 피벗은 그 반대편.
static func _apply_open_shock(card: Node2D, amount: float) -> void:
	if not is_instance_valid(card) or not card.has_meta(META_SHOCK_BASE_POS):
		return
	var base_pos: Vector2 = card.get_meta(META_SHOCK_BASE_POS) as Vector2
	var dir: Vector2 = card.get_meta(META_SHOCK_DIR, Vector2.RIGHT) as Vector2
	var strength := float(card.get_meta(META_SHOCK_STRENGTH, 1.0))
	var pulse := float(card.get_meta(META_SHOCK_PULSE_AMP, 1.0))
	var a := clampf(amount, 0.0, 1.0) * clampf(strength, 0.0, 1.0) * maxf(pulse, 0.0)
	var n := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	var max_deg := GameConstants.CARD_OPEN_SHOCK_TILT_MAX_DEG
	var tilt_y := -n.x * max_deg * a
	var tilt_x := n.y * max_deg * a
	var pivot := Vector2(-n.x * HALF_EXTENTS.x, -n.y * HALF_EXTENTS.y)
	_set_tilt_meta(card, tilt_x, tilt_y, pivot)
	card.position = base_pos + Vector2(0.0, -GameConstants.CARD_OPEN_SHOCK_LIFT_PX * a)


static func _restore_open_shock_base(card: Node2D) -> void:
	if not is_instance_valid(card):
		return
	if card.has_meta(META_SHOCK_BASE_POS):
		card.position = card.get_meta(META_SHOCK_BASE_POS) as Vector2
	_set_tilt_meta(card, 0.0, 0.0, Vector2.ZERO)


static func _clear_open_shock_meta(card: Node2D) -> void:
	card.set_meta(META_SHOCK_ACTIVE, false)
	if card.has_meta(META_SHOCK_TWEEN):
		card.remove_meta(META_SHOCK_TWEEN)
	if card.has_meta(META_SHOCK_BASE_POS):
		card.remove_meta(META_SHOCK_BASE_POS)
	if card.has_meta(META_SHOCK_DIR):
		card.remove_meta(META_SHOCK_DIR)
	if card.has_meta(META_SHOCK_BASE_DIR):
		card.remove_meta(META_SHOCK_BASE_DIR)
	if card.has_meta(META_SHOCK_STRENGTH):
		card.remove_meta(META_SHOCK_STRENGTH)
	if card.has_meta(META_SHOCK_PULSE_AMP):
		card.remove_meta(META_SHOCK_PULSE_AMP)


static func _finish_open_shock(card: Node2D) -> void:
	if not is_instance_valid(card):
		return
	_restore_open_shock_base(card)
	_clear_open_shock_meta(card)


static func _set_tilt_meta(
	card: Node2D,
	tilt_x: float,
	tilt_y: float,
	pivot: Vector2 = Vector2.ZERO
) -> void:
	card.set_meta(META_TX, tilt_x)
	card.set_meta(META_TY, tilt_y)
	_apply_tilt(card, tilt_x, tilt_y, pivot)


static func _clear_flip_meta(card: Node2D) -> void:
	card.set_meta(META_FLIPPING, false)
	if card.has_meta(META_FLIP_TWEEN):
		card.remove_meta(META_FLIP_TWEEN)
	if card.has_meta(META_FLIP_START_MSEC):
		card.remove_meta(META_FLIP_START_MSEC)
	if card.has_meta(META_FLIP_TOTAL_SEC):
		card.remove_meta(META_FLIP_TOTAL_SEC)
	if card.has_meta(META_FLIP_SWAP_SEC):
		card.remove_meta(META_FLIP_SWAP_SEC)
	if card.has_meta(META_FLIP_LIFT):
		card.remove_meta(META_FLIP_LIFT)
	if card.has_meta(META_FLIP_BASE_POS):
		card.remove_meta(META_FLIP_BASE_POS)
	if card.has_meta(META_FLIP_BASE_SCALE):
		card.remove_meta(META_FLIP_BASE_SCALE)
	if card.has_meta(META_FLIP_BASE_Z):
		card.remove_meta(META_FLIP_BASE_Z)


static func _ensure_materials(card: Node2D) -> void:
	var front_ok := card.has_meta(META_MAT_FRONT) \
		and card.get_meta(META_MAT_FRONT) is ShaderMaterial \
		and is_instance_valid(card.get_meta(META_MAT_FRONT))
	if front_ok:
		_sync_half_size_params(card)
		return
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	if _shader == null:
		push_error("CardHoverTilt: failed to load %s" % SHADER_PATH)
		return
	var front := ShaderMaterial.new()
	front.shader = _shader
	front.set_shader_parameter("card_half_size", HALF_EXTENTS)
	front.set_shader_parameter("corner_origin", 0.0)
	front.set_shader_parameter("tilt_pivot", Vector2.ZERO)
	front.set_shader_parameter("rarity_hint", 0.0)
	CardRarityFoil.bind_holo_maps(front)
	var back := ShaderMaterial.new()
	back.shader = _shader
	back.set_shader_parameter("rarity_tier", 0.0)
	back.set_shader_parameter("rarity_hint", 0.0)
	back.set_shader_parameter("card_half_size", HALF_EXTENTS)
	back.set_shader_parameter("corner_origin", 0.0)
	back.set_shader_parameter("tilt_pivot", Vector2.ZERO)
	card.set_meta(META_MAT_FRONT, front)
	card.set_meta(META_MAT_BACK, back)
	var img := card.get_node_or_null("CardImage") as CanvasItem
	if img:
		img.material = front
	var bk := card.get_node_or_null("CardBackImage") as CanvasItem
	if bk:
		bk.material = back


static func _sync_half_size_params(card: Node2D) -> void:
	for key in [META_MAT_FRONT, META_MAT_BACK]:
		var mat: Variant = card.get_meta(key, null)
		if mat is ShaderMaterial and is_instance_valid(mat):
			var sm := mat as ShaderMaterial
			sm.set_shader_parameter("card_half_size", HALF_EXTENTS)
			sm.set_shader_parameter("corner_origin", 0.0)


static func _apply_tilt(
	card: Node2D,
	tilt_x: float,
	tilt_y: float,
	pivot: Vector2 = Vector2.ZERO
) -> void:
	for key in [META_MAT_FRONT, META_MAT_BACK]:
		var mat: Variant = card.get_meta(key, null)
		if mat is ShaderMaterial and is_instance_valid(mat):
			var sm := mat as ShaderMaterial
			sm.set_shader_parameter("tilt_x_deg", tilt_x)
			sm.set_shader_parameter("tilt_y_deg", tilt_y)
			sm.set_shader_parameter("tilt_pivot", pivot)
