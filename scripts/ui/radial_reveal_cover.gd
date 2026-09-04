class_name RadialRevealCover
extends Control
## 셰이더 없이 중앙에서 바깥으로 밝아지는 검정 마스크. 모바일 렌더러 호환.

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

## 경계 부드러움(픽셀). 반경 hole_r ± softness/2 구간에서 알파 그라데이션.
var softness_pixels: float = 64.0
var ring_segments: int = 72
var softness_steps: int = 20


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	if progress <= 0.0001:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		return
	if progress >= 0.999:
		return
	var center := size * 0.5
	var max_r := center.length() * 1.25
	var hole_r := progress * max_r
	var outer_r := max_r * 2.0
	var soft := maxf(softness_pixels, 1.0)
	var soft_inner := hole_r - soft * 0.5
	var soft_outer := hole_r + soft * 0.5
	var segs := maxi(ring_segments, 12)
	var steps := maxi(softness_steps, 4)
	for step in steps:
		var t0 := float(step) / float(steps)
		var t1 := float(step + 1) / float(steps)
		var r0 := soft_inner + (soft_outer - soft_inner) * t0
		var r1 := soft_inner + (soft_outer - soft_inner) * t1
		if r1 <= 0.0:
			continue
		var mid := (r0 + r1) * 0.5
		var alpha := _smooth_band_alpha(mid, soft_inner, soft_outer)
		if alpha <= 0.001:
			continue
		_draw_annulus(center, maxf(r0, 0.0), r1, segs, Color(0, 0, 0, alpha))
	if soft_outer < outer_r:
		_draw_annulus(center, soft_outer, outer_r, segs, Color.BLACK)


func _smooth_band_alpha(radius: float, inner: float, outer: float) -> float:
	if radius <= inner:
		return 0.0
	if radius >= outer:
		return 1.0
	var t := (radius - inner) / maxf(outer - inner, 0.001)
	return t * t * (3.0 - 2.0 * t)


func _draw_annulus(
	center: Vector2,
	inner_r: float,
	outer_r: float,
	segs: int,
	color: Color
) -> void:
	if outer_r <= inner_r:
		return
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0_in := center + Vector2.from_angle(a0) * inner_r
		var p1_in := center + Vector2.from_angle(a1) * inner_r
		var p0_out := center + Vector2.from_angle(a0) * outer_r
		var p1_out := center + Vector2.from_angle(a1) * outer_r
		draw_colored_polygon(PackedVector2Array([p0_in, p1_in, p1_out, p0_out]), color)
