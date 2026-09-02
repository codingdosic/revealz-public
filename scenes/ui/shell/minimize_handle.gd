class_name MinimizeHandle
extends Button
## L4a 최소화 복귀 핸들 — 클릭만 (드래그 없음).
## 타겟 선택 바 / 효과 다이얼로그 등이 접힌 뒤 이 버튼으로 복귀.
## 룩: UiChromeStyle (apply_chrome / GameUILayer 배포).
##
## 사용 (호스트):
##   handle.show_handle(restore_cb, "카드 선택")
##   handle.hide_handle()
##
## 위치 튜닝: UiShellConstants.MINIMIZE_HANDLE_OFFSET_* 또는 set_handle_position()
## 기존 game_ui_layer EffectDialogRestoreButton 대체용.

signal restore_pressed

@export var chrome_style: UiChromeStyle

var _restore_callback: Callable


## 부트: 숨김 · 크롬 · 기본 위치.
func _ready() -> void:
	visible = false
	disabled = true
	z_index = UiShellConstants.MINIMIZE_HANDLE_Z
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	apply_chrome(chrome_style)
	_apply_default_position()


## 크롬 버튼 스타일을 적용한다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	chrome_style.apply_button(self)


## 기본 화면 좌표 적용. 위치 바꾸려면 여기 또는 set_handle_position.
func _apply_default_position() -> void:
	offset_left = UiShellConstants.MINIMIZE_HANDLE_OFFSET_LEFT
	offset_top = UiShellConstants.MINIMIZE_HANDLE_OFFSET_TOP
	offset_right = offset_left + UiShellConstants.MINIMIZE_HANDLE_SIZE.x
	offset_bottom = offset_top + UiShellConstants.MINIMIZE_HANDLE_SIZE.y


## 픽셀 좌표로 핸들 위치·크기 지정.
func set_handle_position(top_left: Vector2, size: Vector2 = Vector2.ZERO) -> void:
	if size == Vector2.ZERO:
		size = UiShellConstants.MINIMIZE_HANDLE_SIZE
	offset_left = top_left.x
	offset_top = top_left.y
	offset_right = top_left.x + size.x
	offset_bottom = top_left.y + size.y


## 복귀 콜백과 라벨로 표시.
func show_handle(restore_callback: Callable, label_text: String = "") -> void:
	_restore_callback = restore_callback
	var copy := UiChromeStyle.resolve(chrome_style).get_copy()
	text = label_text if not label_text.is_empty() else copy.restore
	disabled = false
	visible = true


## 숨기고 콜백 해제.
func hide_handle() -> void:
	visible = false
	disabled = true
	_restore_callback = Callable()
	text = UiChromeStyle.resolve(chrome_style).get_copy().restore


## 핸들이 보이는지.
func is_handle_visible() -> bool:
	return visible


## 클릭 시 콜백 실행 후 핸들 숨김.
func _on_pressed() -> void:
	if disabled:
		return
	var cb := _restore_callback
	restore_pressed.emit()
	hide_handle()
	if cb.is_valid():
		cb.call()
