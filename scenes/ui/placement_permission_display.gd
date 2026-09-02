extends Node2D
class_name PlacementPermissionDisplay

## 세팅 배치권(마나) MVP 표시. max 칸 마름모 · 보유분 파랑(아래→위) · pending 예약은 연한 파랑.
## 색상은 UiShellConstants.PERMISSION_* — 플레이어 덱 왼쪽 프로토타입.

@export var max_slots: int = 4
@export var slot_radius: float = 10.0
@export var slot_gap: float = 6.0
@export var padding: Vector2 = Vector2(8, 8)

var _filled: int = 0
var _reserved: int = 0


## 보유 배치권·예약(pending cost)·칸 수를 반영하고 다시 그린다.
func set_permission(filled: int, reserved: int = 0, slot_count: int = -1) -> void:
	if slot_count > 0:
		max_slots = slot_count
	_filled = clampi(filled, 0, max_slots)
	_reserved = clampi(reserved, 0, _filled)
	queue_redraw()


## 표시를 비운다 (매치 전·rules 비활성).
func clear_permission() -> void:
	_filled = 0
	_reserved = 0
	queue_redraw()


## 컨테이너·슬롯 마름모를 그린다. 아래 칸부터 available→reserved→empty.
func _draw() -> void:
	var inner_h := _content_height()
	var inner_w := slot_radius * 2.0
	var size := Vector2(inner_w + padding.x * 2.0, inner_h + padding.y * 2.0)
	var top_left := -size * 0.5

	draw_rect(Rect2(top_left, size), UiShellConstants.PERMISSION_BG, true)
	draw_rect(Rect2(top_left, size), UiShellConstants.PERMISSION_BORDER, false, 1.5)

	var available := maxi(0, _filled - _reserved)
	var cx := 0.0
	var bottom_y := top_left.y + size.y - padding.y - slot_radius

	for i in range(max_slots):
		var cy := bottom_y - float(i) * (slot_radius * 2.0 + slot_gap)
		var color := UiShellConstants.PERMISSION_EMPTY
		if i < available:
			color = UiShellConstants.PERMISSION_FILLED
		elif i < _filled:
			color = UiShellConstants.PERMISSION_RESERVED
		_draw_diamond(Vector2(cx, cy), slot_radius, color)


## 중심·반경으로 세로 마름모(다이아)를 채운다.
func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, color)


## 슬롯·갭 기준 내부 높이.
func _content_height() -> float:
	if max_slots <= 0:
		return 0.0
	return float(max_slots) * slot_radius * 2.0 + float(maxi(0, max_slots - 1)) * slot_gap
