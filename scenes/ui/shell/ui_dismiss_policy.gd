class_name UiDismissPolicy
extends RefCounted
## 패널 닫기/최소화 입력 공통 처리 (우클릭·ESC·바깥 클릭).
## 호스트(Control/CanvasLayer)의 _input 또는 _unhandled_input 에서 handle_event 호출.
##
## 튜닝:
## - dismiss_on_right_click / dismiss_on_esc / dismiss_on_outside_click
## - outside_minimizes=true 이면 바깥 클릭 시 "minimize", 아니면 "hide"

signal dismiss_requested(reason: String)

## 우클릭으로 닫기. false면 무시.
var dismiss_on_right_click: bool = UiShellConstants.DEFAULT_DISMISS_ON_RIGHT_CLICK
## ESC로 닫기.
var dismiss_on_esc: bool = UiShellConstants.DEFAULT_DISMISS_ON_ESC
## 패널 사각형 밖 좌클릭으로 닫기/최소화.
var dismiss_on_outside_click: bool = UiShellConstants.DEFAULT_DISMISS_ON_OUTSIDE_CLICK
## 바깥 클릭 시 minimize 시그널 reason 사용 (타겟 바 등).
var outside_minimizes: bool = false
## (Vector2) -> bool. true면 바깥 좌클릭 dismiss 생략 (타겟 바·존 브라우즈 등).
var is_outside_click_exempt: Callable = Callable()

var _panel: Control


## 대상 패널을 묶는다. panel.get_global_rect()로 바깥 클릭 판정.
func bind(panel: Control) -> void:
	_panel = panel


## 입력을 처리한다. 소비했으면 true (set_input_as_handled 권장).
func handle_event(event: InputEvent) -> bool:
	if _panel == null or not is_instance_valid(_panel) or not _panel.visible:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if dismiss_on_esc and event.keycode == KEY_ESCAPE:
			dismiss_requested.emit("esc")
			return true
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and dismiss_on_right_click:
			dismiss_requested.emit("right_click")
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT and dismiss_on_outside_click:
			if not _panel.get_global_rect().has_point(mb.global_position):
				if _is_outside_exempt(mb.global_position):
					return false
				dismiss_requested.emit("minimize" if outside_minimizes else "outside_click")
				return true
	return false


func _is_outside_exempt(global_pos: Vector2) -> bool:
	if not is_outside_click_exempt.is_valid():
		return false
	return bool(is_outside_click_exempt.call(global_pos))
