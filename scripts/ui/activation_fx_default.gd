class_name ActivationFxDefault
extends RefCounted
## 기본 발동 연출: CanvasItem scale 짧은 펄스 + 푸른 링.
## 존 peek: await_pop_in(0→1) 후 await_play_on_visual.
## --- 튜닝 SSOT (이 파일 상수만 조정) ---
## SCALE_PEAK / SCALE_UP_SEC / SCALE_DOWN_SEC: 발동 scale 펄스.
## POP_IN_SEC: 존 칩 0→1 솟아남.
## PEEK_CHIP_SIZE: 존 peek 칩 크기.
## PULSE_*: 링. PULSE_LINE_WIDTH 변경 시 재시작(텍스처 캐시).


const SCALE_PEAK := 1.3
const SCALE_UP_SEC := 0.2
const SCALE_DOWN_SEC := 0.25
const POP_IN_SEC := 0.01
const PEEK_CHIP_SIZE := Vector2(67, 94)
const PULSE_START_SCALE := 0.55
const PULSE_END_SCALE := 2.8
const PULSE_SEC := 0.42
const PULSE_COLOR := Color(0.203, 0.845, 0.917, 0.9)
const PULSE_LINE_WIDTH := 8.0

const PULSE_NAME := "ActivationPulse"

static var _ring_texture: Texture2D = null


## 존 칩 등: scale 0 → 1로 솟아나게 한다.
func await_pop_in(visual: CanvasItem) -> void:
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
		return
	visual.scale = Vector2.ZERO
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", Vector2.ONE, POP_IN_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	await tween.finished
	if is_instance_valid(visual):
		visual.scale = Vector2.ONE


## Node2D 카드용 별칭.
func await_play_on_card(card: Node2D) -> void:
	await await_play_on_visual(card)


## scale 펄스 + 중심 링. 카드·칩 공통 (CanvasItem).
func await_play_on_visual(visual: CanvasItem) -> void:
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
		return
	var base_scale: Vector2 = visual.scale
	if absf(base_scale.x) < 0.01 or absf(base_scale.y) < 0.01:
		# 필드 카드 기본 0.4 · 칩은 보통 1.
		base_scale = Vector2.ONE if visual is Control else Vector2(0.4, 0.4)

	var at: Vector2 = visual.global_position
	if visual is Control:
		var c := visual as Control
		at = c.global_position + c.pivot_offset * c.scale
	elif visual is Node2D:
		at = (visual as Node2D).global_position

	var pulse := _spawn_pulse(visual, at)
	var tween := visual.create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "scale", base_scale * SCALE_PEAK, SCALE_UP_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	if pulse != null:
		pulse.scale = Vector2(PULSE_START_SCALE, PULSE_START_SCALE)
		pulse.modulate = PULSE_COLOR
		tween.tween_property(
			pulse, "scale", Vector2(PULSE_END_SCALE, PULSE_END_SCALE), PULSE_SEC
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(pulse, "modulate:a", 0.0, PULSE_SEC).set_ease(Tween.EASE_IN)

	tween.chain()
	tween.tween_property(visual, "scale", base_scale, SCALE_DOWN_SEC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	if is_instance_valid(visual):
		visual.scale = base_scale
	if pulse != null and is_instance_valid(pulse):
		pulse.queue_free()


## 월드 좌표 펄스만. parent 아래 스폰 · 존/패 확장용.
func await_play_at(at: Vector2, parent: Node, opts: Dictionary = {}) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var color := opts.get("color", PULSE_COLOR) as Color
	var start_s := float(opts.get("start_scale", PULSE_START_SCALE))
	var end_s := float(opts.get("end_scale", PULSE_END_SCALE))
	var sec := float(opts.get("duration", PULSE_SEC))
	var pulse := _spawn_pulse(parent, at)
	if pulse == null:
		return
	pulse.modulate = color
	pulse.scale = Vector2(start_s, start_s)
	var tween := pulse.create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector2(end_s, end_s), sec).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, sec).set_ease(Tween.EASE_IN)
	await tween.finished
	if is_instance_valid(pulse):
		pulse.queue_free()


## 링 스프라이트. top_level로 월드 좌표에 그린다.
func _spawn_pulse(parent: Node, at: Vector2) -> Sprite2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var pulse := Sprite2D.new()
	pulse.name = PULSE_NAME
	pulse.texture = _ensure_ring_texture()
	pulse.centered = true
	pulse.z_as_relative = false
	pulse.z_index = 200
	pulse.top_level = true
	pulse.modulate = PULSE_COLOR
	pulse.scale = Vector2(PULSE_START_SCALE, PULSE_START_SCALE)
	parent.add_child(pulse)
	pulse.global_position = at
	return pulse


## 흰 링 텍스처를 캐시한다 (modulate로 색).
func _ensure_ring_texture() -> Texture2D:
	if _ring_texture != null:
		return _ring_texture
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := float(size) * 0.5
	var outer := center - 2.0
	var inner := maxf(outer - PULSE_LINE_WIDTH, 1.0)
	for y in size:
		for x in size:
			var d := Vector2(float(x) - center, float(y) - center).length()
			if d > outer or d < inner:
				continue
			var mid := (inner + outer) * 0.5
			var half := maxf((outer - inner) * 0.5, 0.001)
			var a := 1.0 - absf(d - mid) / half
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_ring_texture = ImageTexture.create_from_image(img)
	return _ring_texture
