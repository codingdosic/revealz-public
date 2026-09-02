class_name UiShellSlide
extends RefCounted
## Control offset 슬라이드. 앵커에 맞춰 높/폭을 유지한다.
## delta + = 아래 또는 오른쪽.


var rest_a: float = 0.0
var rest_b: float = 0.0
var b_sign: float = -1.0
var horizontal: bool = false


## 현재 레이아웃을 정지 위치로 기억한다. horizontal=true 면 좌우.
func capture(panel: Control, p_horizontal: bool) -> void:
	if panel == null:
		return
	horizontal = p_horizontal
	if horizontal:
		rest_a = panel.offset_left
		rest_b = panel.offset_right
		b_sign = 1.0 if is_equal_approx(panel.anchor_left, panel.anchor_right) else -1.0
	else:
		rest_a = panel.offset_top
		rest_b = panel.offset_bottom
		b_sign = 1.0 if is_equal_approx(panel.anchor_top, panel.anchor_bottom) else -1.0


## 정지 위치에서 delta만큼 민다. 상하 앵커가 다르면 반대 offset으로 크기 유지.
func apply(panel: Control, delta: float) -> void:
	if panel == null:
		return
	if horizontal:
		panel.offset_left = rest_a + delta
		panel.offset_right = rest_b + b_sign * delta
	else:
		panel.offset_top = rest_a + delta
		panel.offset_bottom = rest_b + b_sign * delta
