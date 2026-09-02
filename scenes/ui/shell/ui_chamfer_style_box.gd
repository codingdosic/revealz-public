class_name UiChamferStyleBox
extends StyleBox
## 사각형 StyleBox — 모서리 라운드 없음, 상단 한쪽 사선(chamfer) 컷.
## mirror_h=false → 좌상단, true → 우상단.
## diagonal_pair=true → 대각 반대 모서리도 동일 길이 챔퍼 (TL+BR / TR+BL).

@export var bg_color: Color = Color(0.08, 0.08, 0.12, 0.92)
@export var border_color: Color = Color(0.38, 0.52, 0.68, 1.0)
@export var border_width: float = 1.0
## 사선 길이(px). 0 이면 직각.
@export var chamfer_tl: float = 11.0
## true 면 우상단 챔퍼 (이름 배지 좌측용 등).
@export var mirror_h: bool = false
## true 면 대각 반대 모서리에도 동일 챔퍼.
@export var diagonal_pair: bool = false
@export var border_left: bool = true
@export var border_top: bool = true
@export var border_right: bool = true
@export var border_bottom: bool = true


## 배경 폴리곤 + 선택 보더를 그린다.
func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var pts := _outline_points(rect)
	if pts.size() < 3:
		return
	var colors := PackedColorArray()
	colors.resize(pts.size())
	colors.fill(bg_color)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, colors)
	_draw_borders(to_canvas_item, pts)


## 챔퍼가 반영된 외곽 꼭짓점 (시계 방향, 닫히지 않음).
func _outline_points(rect: Rect2) -> PackedVector2Array:
	var c := clampf(chamfer_tl, 0.0, minf(rect.size.x, rect.size.y) * 0.45)
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	if c <= 0.5:
		return PackedVector2Array([
			Vector2(x0, y0),
			Vector2(x1, y0),
			Vector2(x1, y1),
			Vector2(x0, y1),
		])
	if mirror_h:
		if diagonal_pair:
			# TR + BL
			return PackedVector2Array([
				Vector2(x0, y0),
				Vector2(x1 - c, y0),
				Vector2(x1, y0 + c),
				Vector2(x1, y1),
				Vector2(x0 + c, y1),
				Vector2(x0, y1 - c),
			])
		# 우상단만
		return PackedVector2Array([
			Vector2(x0, y0),
			Vector2(x1 - c, y0),
			Vector2(x1, y0 + c),
			Vector2(x1, y1),
			Vector2(x0, y1),
		])
	if diagonal_pair:
		# TL + BR
		return PackedVector2Array([
			Vector2(x0 + c, y0),
			Vector2(x1, y0),
			Vector2(x1, y1 - c),
			Vector2(x1 - c, y1),
			Vector2(x0, y1),
			Vector2(x0, y0 + c),
		])
	# 좌상단만
	return PackedVector2Array([
		Vector2(x0 + c, y0),
		Vector2(x1, y0),
		Vector2(x1, y1),
		Vector2(x0, y1),
		Vector2(x0, y0 + c),
	])


## 활성 변만 폴리라인으로 스트로크.
func _draw_borders(to_canvas_item: RID, pts: PackedVector2Array) -> void:
	if border_width <= 0.0:
		return
	var n := pts.size()
	if n < 2:
		return
	var edge_on: Array[bool] = []
	if n == 4:
		edge_on = [border_top, border_right, border_bottom, border_left]
	elif n == 6 and mirror_h:
		# TR+BL: top, TR-chamfer, right, bottom, BL-chamfer, left
		edge_on = [
			border_top,
			border_top or border_right,
			border_right,
			border_bottom,
			border_bottom or border_left,
			border_left,
		]
	elif n == 6:
		# TL+BR: top, right, BR-chamfer, bottom, left, TL-chamfer
		edge_on = [
			border_top,
			border_right,
			border_right or border_bottom,
			border_bottom,
			border_left,
			border_top or border_left,
		]
	elif mirror_h:
		# 5점 TR: top, chamfer, right, bottom, left
		edge_on = [
			border_top,
			border_top or border_right,
			border_right,
			border_bottom,
			border_left,
		]
	else:
		# 5점 TL: top, right, bottom, left, chamfer
		edge_on = [
			border_top,
			border_right,
			border_bottom,
			border_left,
			border_top or border_left,
		]
	for i in range(n):
		if i >= edge_on.size() or not edge_on[i]:
			continue
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		RenderingServer.canvas_item_add_line(
			to_canvas_item, a, b, border_color, border_width, true
		)
