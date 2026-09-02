class_name EffectFxDefault
extends RefCounted
## 스탯 modify 기본 연출.
## DEC: 투사체(동시) → 진동(동시) → [스탯 apply_cb] + 하강기류(동시).
## INC: [스탯 apply_cb] + 상승기류(동시).
## 광역 DEC: 라인별 Line2D 곡선 파면 → [apply_cb] + 하강기류.
## Godot 2D: Y+ = 아래. 상승=음수 Y, 하강=양수 Y.
## --- 튜닝 SSOT (이 파일 상수 · StepModifyStat opts 오버라이드) ---


const PROJECTILE_SEC := 0.28
const PROJECTILE_RADIUS := 7.0
const PROJECTILE_COLOR := Color(0.95, 0.35, 0.25, 0.95)
const PROJECTILE_COLOR_BLACK := Color(0.62, 0.28, 0.95, 0.95)

const HIT_SHAKE_SEC := 0.12
const HIT_SHAKE_PX := 7.0
const HIT_SHAKE_STEPS := 5

const AURA_SEC := 0.5
const AURA_PARTICLE_COUNT := 30
const AURA_RISE_PX := 180.0
const AURA_SPREAD_PX := 180.0
const AURA_CARD_HALF_H := 110.0
const AURA_START_BAND_PX := 100.0
const AURA_PARTICLE_RADIUS_MIN := 5.0
const AURA_PARTICLE_RADIUS_MAX := 8.0
const AURA_COLOR_UP := Color(0.0, 1.0, 0.0, 1.0)
const AURA_COLOR_DOWN := Color(1.0, 0, 0.0, 1)
const AURA_COLOR_BLACK_DOWN := Color(0.55, 0.25, 0.9, 0.9)

const WAVE_SEC := 0.42
const WAVE_WIDTH := 14.0
const WAVE_COLOR := Color(1.0, 0.28, 0.18, 0.9)
const WAVE_COLOR_BLACK := Color(0.58, 0.28, 0.92, 0.9)
const WAVE_SEGMENTS := 28
const WAVE_RINGS := 2
const WAVE_RING_GAP_PX := 22.0
const WAVE_RING_STAGGER_SEC := 0.07
const WAVE_RADIUS_PAD_PX := 48.0
const WAVE_MIN_RADIUS_PX := 80.0
const WAVE_APERTURE_PAD_RAD := 0.28
const WAVE_MIN_HALF_APERTURE_RAD := 0.38
const WAVE_SINGLE_HALF_APERTURE_RAD := 0.55

const CIRCLE_SEGMENTS := 16
const COLOR_FLAG_BLACK := 1
const META_SHAKE := &"_effect_fx_shake"
const META_AURA_PARTICLES := &"_effect_fx_aura_particles"


## 복수 타겟 동시. apply_cb는 기류 시작 직전.
func await_modify_stat(
	source: Node,
	targets: Array,
	delta: int,
	opts: Dictionary = {},
	apply_cb: Callable = Callable()
) -> void:
	if targets.is_empty() or delta == 0:
		if apply_cb.is_valid():
			apply_cb.call()
		return
	var merged := opts.duplicate()
	_apply_source_color_defaults(source, delta, merged)
	if bool(merged.get("line_wave", false)):
		await await_line_wave(source, targets, delta, merged, apply_cb)
		return
	var self_cast := bool(merged.get("self_cast", false))
	if not self_cast and source != null and targets.size() == 1 and source == targets[0]:
		self_cast = true
		merged["self_cast"] = true

	if delta < 0 and not self_cast and source is Node2D and is_instance_valid(source):
		await _await_projectiles_parallel(source as Node2D, targets, merged)
		if not bool(merged.get("skip_hit", false)):
			await _await_shakes_parallel(targets)

	# 기류 시작 직전 스탯 적용(apply_cb) · 기류는 동시.
	await await_aura_batch(targets, delta, merged, apply_cb)


## 라인별 곡선 파면(동시) → 기류. apply_cb는 기류 직전.
func await_line_wave(
	source: Node,
	targets: Array,
	delta: int,
	opts: Dictionary = {},
	apply_cb: Callable = Callable()
) -> void:
	if targets.is_empty() or delta == 0:
		if apply_cb.is_valid():
			apply_cb.call()
		return
	var merged := opts.duplicate()
	_apply_source_color_defaults(source, delta, merged)
	if source is Node2D and is_instance_valid(source):
		await _await_line_waves_parallel(source as Node2D, targets, merged)
	await await_aura_batch(targets, delta, merged, apply_cb)


## 기류만 동시. apply_cb는 시작 직전(광역·PASSIVE 후속 연출용).
func await_aura_batch(
	targets: Array,
	delta: int,
	opts: Dictionary = {},
	apply_cb: Callable = Callable()
) -> void:
	if targets.is_empty() or delta == 0:
		if apply_cb.is_valid():
			apply_cb.call()
		return
	if apply_cb.is_valid():
		apply_cb.call()
	var rise := delta > 0
	var tweens: Array[Tween] = []
	for t in targets:
		var target := t as Node2D
		if target == null or not is_instance_valid(target):
			continue
		var tw := _start_aura(target, rise, opts)
		if tw != null:
			tweens.append(tw)
	await MatchVfx.await_all_tweens(tweens)


## 시전 카드 색 기본값.
func _apply_source_color_defaults(source: Node, delta: int, opts: Dictionary) -> void:
	if source == null or not is_instance_valid(source):
		return
	var flags := int(source.get("card_color")) if source.get("card_color") != null else 0
	var is_black := (flags & COLOR_FLAG_BLACK) != 0
	if not opts.has("projectile_color"):
		opts["projectile_color"] = PROJECTILE_COLOR_BLACK if is_black else PROJECTILE_COLOR
	if not opts.has("color"):
		if delta < 0:
			opts["color"] = AURA_COLOR_BLACK_DOWN if is_black else AURA_COLOR_DOWN
		else:
			opts["color"] = AURA_COLOR_UP
	if not opts.has("wave_color"):
		opts["wave_color"] = WAVE_COLOR_BLACK if is_black else WAVE_COLOR


## 라인 그룹별 파면 동시 재생.
func _await_line_waves_parallel(source: Node2D, targets: Array, opts: Dictionary) -> void:
	if not source.is_inside_tree():
		return
	var parent := _resolve_fx_parent(source)
	if parent == null:
		return
	var groups := _group_targets_by_line(targets)
	var tweens: Array[Tween] = []
	var lines: Array[Line2D] = []
	for key in groups.keys():
		var group: Array = groups[key]
		if group.is_empty():
			continue
		var built := _start_line_wave_group(source, group, parent, opts)
		for tw in built.get("tweens", []):
			if tw != null:
				tweens.append(tw as Tween)
		for ln in built.get("lines", []):
			if ln != null:
				lines.append(ln as Line2D)
	await MatchVfx.await_all_tweens(tweens)
	for ln in lines:
		if is_instance_valid(ln):
			ln.queue_free()


## slot.line 기준 그룹. 없으면 X 버킷.
func _group_targets_by_line(targets: Array) -> Dictionary:
	var groups: Dictionary = {}
	for t in targets:
		var card := t as Node2D
		if card == null or not is_instance_valid(card):
			continue
		var key := _line_group_key(card)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(card)
	return groups


## 카드 슬롯 라인, 없으면 Field X 분리선 버킷.
func _line_group_key(card: Node2D) -> int:
	var slot = card.get("card_slot_card_is_in")
	if slot != null and is_instance_valid(slot) and slot.get("line") != null:
		return int(slot.line)
	var x := card.global_position.x
	if x < FieldBoardLayout.LINE_SEP_X_LEFT_CENTER:
		return 0
	if x < FieldBoardLayout.LINE_SEP_X_CENTER_RIGHT:
		return 1
	return 2


## 한 라인 그룹: 겹 파면 Line2D + radius Tween.
func _start_line_wave_group(
	source: Node2D, group: Array, parent: Node, opts: Dictionary
) -> Dictionary:
	var origin := source.global_position
	var angles: Array[float] = []
	var max_dist := 0.0
	for t in group:
		var card := t as Node2D
		if card == null or not is_instance_valid(card):
			continue
		var delta_v := card.global_position - origin
		var dist := delta_v.length()
		max_dist = maxf(max_dist, dist)
		if dist > 0.5:
			angles.append(delta_v.angle())
	if angles.is_empty():
		return {}
	var aperture := _wave_aperture_from_angles(angles, opts)
	var center_angle := aperture["center"] as float
	var half := aperture["half"] as float
	var angle_from := center_angle - half
	var angle_to := center_angle + half
	var radius_end := maxf(
		max_dist + float(opts.get("wave_radius_pad_px", WAVE_RADIUS_PAD_PX)),
		float(opts.get("wave_min_radius_px", WAVE_MIN_RADIUS_PX))
	)
	var dur := float(opts.get("wave_sec", WAVE_SEC))
	var width := float(opts.get("wave_width", WAVE_WIDTH))
	var color: Color = opts.get("wave_color", WAVE_COLOR) as Color
	var segments := clampi(int(opts.get("wave_segments", WAVE_SEGMENTS)), 8, 64)
	var rings := clampi(int(opts.get("wave_rings", WAVE_RINGS)), 1, 4)
	var ring_gap := float(opts.get("wave_ring_gap_px", WAVE_RING_GAP_PX))
	var stagger := float(opts.get("wave_ring_stagger_sec", WAVE_RING_STAGGER_SEC))
	var tweens: Array[Tween] = []
	var lines: Array[Line2D] = []
	for ring_i in range(rings):
		var line := _make_wave_line(width, color)
		line.z_index = 38
		parent.add_child(line)
		lines.append(line)
		var radius_offset := float(ring_i) * ring_gap
		var delay := float(ring_i) * stagger
		var state := {
			"line": line,
			"origin": origin,
			"angle_from": angle_from,
			"angle_to": angle_to,
			"segments": segments,
			"radius_offset": radius_offset,
			"radius_end": radius_end,
			"base_color": color,
		}
		_update_wave_line(0.0, state)
		var tween := line.create_tween()
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_method(_update_wave_line.bind(state), 0.0, 1.0, dur).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_OUT)
		tweens.append(tween)
	return {"tweens": tweens, "lines": lines}


## 각도 배열에서 중심·반개도(라디안).
func _wave_aperture_from_angles(angles: Array[float], opts: Dictionary) -> Dictionary:
	var pad := float(opts.get("wave_aperture_pad_rad", WAVE_APERTURE_PAD_RAD))
	var min_half := float(opts.get("wave_min_half_aperture_rad", WAVE_MIN_HALF_APERTURE_RAD))
	var single_half := float(
		opts.get("wave_single_half_aperture_rad", WAVE_SINGLE_HALF_APERTURE_RAD)
	)
	if angles.size() == 1:
		return {"center": angles[0], "half": single_half}
	# 원형 최소 호: 기준각 대비 최단 편차로 묶는다.
	var base := angles[0]
	var min_d := 0.0
	var max_d := 0.0
	for i in range(1, angles.size()):
		var d := angle_difference(base, angles[i])
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
	var center := base + (min_d + max_d) * 0.5
	var half := maxf((max_d - min_d) * 0.5 + pad, min_half)
	return {"center": center, "half": half}


## 곡선 파면 Line2D (양끝 알파 페이드).
func _make_wave_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var grad := Gradient.new()
	grad.colors = PackedColorArray(
		[Color(color.r, color.g, color.b, 0.0), color, color, Color(color.r, color.g, color.b, 0.0)]
	)
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.82, 1.0])
	line.gradient = grad
	return line


## t=0..1 로 반지름·알파 갱신. bind(state)용 시그니처.
func _update_wave_line(t: float, state: Dictionary) -> void:
	var line: Line2D = state.get("line") as Line2D
	if line == null or not is_instance_valid(line):
		return
	var origin: Vector2 = state.get("origin", Vector2.ZERO)
	var angle_from: float = float(state.get("angle_from", 0.0))
	var angle_to: float = float(state.get("angle_to", 0.0))
	var segments: int = int(state.get("segments", WAVE_SEGMENTS))
	var radius_offset: float = float(state.get("radius_offset", 0.0))
	var radius_end: float = float(state.get("radius_end", WAVE_MIN_RADIUS_PX))
	var radius := radius_offset + radius_end * clampf(t, 0.0, 1.0)
	var pts := PackedVector2Array()
	var denom := float(maxi(segments, 1))
	for i in range(segments + 1):
		var a := lerpf(angle_from, angle_to, float(i) / denom)
		pts.append(origin + Vector2(cos(a), sin(a)) * radius)
	line.points = pts
	var fade := 1.0
	if t > 0.65:
		fade = 1.0 - (t - 0.65) / 0.35
	line.modulate.a = clampf(fade, 0.0, 1.0)


## 투사체 동시 발사 후 전원 도착 대기.
func _await_projectiles_parallel(source: Node2D, targets: Array, opts: Dictionary) -> void:
	var tweens: Array[Tween] = []
	var bolts: Array[Polygon2D] = []
	for t in targets:
		var target := t as Node2D
		if target == null or not is_instance_valid(target):
			continue
		var pair := _start_projectile(source, target, opts)
		if pair.is_empty():
			continue
		tweens.append(pair["tween"] as Tween)
		bolts.append(pair["bolt"] as Polygon2D)
	await MatchVfx.await_all_tweens(tweens)
	for bolt in bolts:
		if is_instance_valid(bolt):
			bolt.queue_free()


## 피격 진동 동시.
func _await_shakes_parallel(targets: Array) -> void:
	var tweens: Array[Tween] = []
	for t in targets:
		var target := t as Node2D
		if target == null or not is_instance_valid(target):
			continue
		var tw := _start_hit_shake(target)
		if tw != null:
			tweens.append(tw)
	await MatchVfx.await_all_tweens(tweens)


## 투사체 Tween 시작. {tween, bolt} 또는 {}.
func _start_projectile(source: Node2D, target: Node2D, opts: Dictionary) -> Dictionary:
	if not source.is_inside_tree() or not target.is_inside_tree():
		return {}
	var parent := _resolve_fx_parent(source)
	if parent == null:
		return {}
	var color: Color = opts.get("projectile_color", PROJECTILE_COLOR) as Color
	var dur := float(opts.get("projectile_sec", PROJECTILE_SEC))
	var radius := float(opts.get("projectile_radius", PROJECTILE_RADIUS))
	var bolt := _make_circle(radius, color)
	bolt.z_index = 40
	parent.add_child(bolt)
	bolt.global_position = source.global_position
	var tween := bolt.create_tween()
	tween.tween_property(
		bolt, "global_position", target.global_position, dur
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	return {"tween": tween, "bolt": bolt}


## 피격 진동 Tween 시작.
func _start_hit_shake(target: Node2D) -> Tween:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var origin := target.global_position
	target.set_meta(META_SHAKE, origin)
	var steps := HIT_SHAKE_STEPS
	var step_sec := HIT_SHAKE_SEC / float(maxi(steps, 1))
	var tween := target.create_tween()
	for _i in range(steps):
		var ox := randf_range(-HIT_SHAKE_PX, HIT_SHAKE_PX)
		var oy := randf_range(-HIT_SHAKE_PX, HIT_SHAKE_PX)
		tween.tween_property(target, "global_position", origin + Vector2(ox, oy), step_sec)
	tween.tween_property(target, "global_position", origin, step_sec * 0.5)
	tween.finished.connect(_on_hit_shake_finished.bind(target, origin), CONNECT_ONE_SHOT)
	return tween


## 피격 진동 종료 시 위치·메타 복구.
func _on_hit_shake_finished(target: Node2D, origin: Vector2) -> void:
	if not is_instance_valid(target):
		return
	target.global_position = origin
	if target.has_meta(META_SHAKE):
		target.remove_meta(META_SHAKE)


## 기류 Tween 시작(await 없음).
func _start_aura(target: Node2D, rise: bool, opts: Dictionary) -> Tween:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var count := clampi(int(opts.get("particle_count", AURA_PARTICLE_COUNT)), 1, 32)
	var dur := float(opts.get("aura_sec", AURA_SEC))
	var travel := absf(float(opts.get("aura_travel_px", AURA_RISE_PX)))
	var travel_y := -travel if rise else travel
	var color: Color = opts.get("color", AURA_COLOR_UP if rise else AURA_COLOR_DOWN) as Color
	var spread := float(opts.get("aura_spread_px", AURA_SPREAD_PX))
	var half_h := float(opts.get("card_half_h", AURA_CARD_HALF_H))
	var band := float(opts.get("aura_start_band_px", AURA_START_BAND_PX))
	var start_y_center := half_h if rise else -half_h
	var r_min := float(opts.get("particle_radius_min", AURA_PARTICLE_RADIUS_MIN))
	var r_max := float(opts.get("particle_radius_max", AURA_PARTICLE_RADIUS_MAX))
	var particles: Array = []
	for _i in range(count):
		var radius := randf_range(r_min, r_max)
		var p := _make_circle(radius, color)
		p.z_index = 25
		p.position = Vector2(
			randf_range(-spread * 0.5, spread * 0.5),
			start_y_center + randf_range(-band * 0.5, band * 0.5)
		)
		target.add_child(p)
		particles.append(p)
	target.set_meta(META_AURA_PARTICLES, particles)
	var tween := target.create_tween()
	tween.set_parallel(true)
	for p in particles:
		if not is_instance_valid(p):
			continue
		var end_pos: Vector2 = (p as Node2D).position + Vector2(randf_range(-6.0, 6.0), travel_y)
		var p_dur := dur * randf_range(0.75, 1.0)
		tween.tween_property(p, "position", end_pos, p_dur).set_trans(Tween.TRANS_SINE).set_ease(
			Tween.EASE_OUT
		)
		tween.tween_property(p, "modulate:a", 0.0, p_dur).set_ease(Tween.EASE_IN)
	tween.finished.connect(_on_aura_finished.bind(target), CONNECT_ONE_SHOT)
	return tween


## 기류 종료 시 파티클 제거.
func _on_aura_finished(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_meta(META_AURA_PARTICLES):
		return
	var particles: Variant = target.get_meta(META_AURA_PARTICLES)
	target.remove_meta(META_AURA_PARTICLES)
	if particles is Array:
		for p in particles:
			if is_instance_valid(p):
				(p as Node).queue_free()


## 원형 Polygon2D.
func _make_circle(radius: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(CIRCLE_SEGMENTS):
		var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.color = color
	return poly


## 투사체 부모: MatchVfxHost 우선.
func _resolve_fx_parent(anchor: Node2D) -> Node:
	var host := MatchVfx.get_host()
	if host != null and is_instance_valid(host) and host.is_inside_tree():
		return host
	if anchor.get_parent() != null:
		return anchor.get_parent()
	return anchor
