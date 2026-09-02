class_name LoadingGate
extends CanvasLayer
## G4e-UX 재사용 대기/로딩 게이트. 반투명 딤 + 스피너 + 한 줄 문구 + 선택적 취소.
## L4a: 알림형에 가깝지만 진행률·취소가 있어 당분간 독립 유지. PopupShell notice와 별개.
## 룩: UiChromeStyle (딤·배치는 유지).
##
## 튜닝:
## - layer (기본 80) — 다른 UI보다 위여야 함
## - SPINNER_RAD_PER_SEC — 회전 속도
## 호출: show_gate(message, cancel_visible, cancel_enabled)

signal cancel_pressed

## 스피너 1초에 한 바퀴. 빠르게/느리게: 이 값 조절.
const SPINNER_RAD_PER_SEC := TAU

@export var chrome_style: UiChromeStyle

@onready var _root: Control = $Root
@onready var _status_label: Label = $Root/CenterContainer/VBoxContainer/StatusLabel
@onready var _cancel_button: Button = $Root/CenterContainer/VBoxContainer/CancelButton
@onready var _spinner: Control = $Root/CenterContainer/VBoxContainer/SpinnerPivot
@onready var _spinner_mark: ColorRect = $Root/CenterContainer/VBoxContainer/SpinnerPivot/SpinnerMark


## 시작 시 숨김. 스피너 피벗을 중앙으로 · 크롬 적용.
func _ready() -> void:
	layer = 80
	_spinner.pivot_offset = Vector2(24, 24)
	hide_gate()
	_cancel_button.pressed.connect(_on_cancel_button_pressed)
	apply_chrome(chrome_style)


## 상태 라벨·취소 버튼·스피너 액센트에 크롬을 입힌다 (레이아웃 유지).
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	if _status_label:
		chrome_style.apply_muted_label(_status_label)
	if _cancel_button:
		chrome_style.apply_button(_cancel_button)
		_cancel_button.text = chrome_style.get_copy().cancel
	if _spinner_mark:
		_spinner_mark.color = chrome_style.accent


## 스피너 회전 (게이트가 보일 때만).
func _process(delta: float) -> void:
	if not visible:
		return
	_spinner.rotation += delta * SPINNER_RAD_PER_SEC


## 게이트 표시. cancel_visible=false 면 버튼 숨김, true면 cancel_enabled로 disabled 제어.
func show_gate(
	message: String,
	cancel_visible: bool = false,
	cancel_enabled: bool = false
) -> void:
	_status_label.text = message
	_cancel_button.visible = cancel_visible
	_cancel_button.disabled = not cancel_enabled
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	set_process(true)


## 문구만 갱신 (게이트가 떠 있을 때).
func update_message(message: String) -> void:
	_status_label.text = message


## 취소 버튼 visible/disabled만 바꾼다.
func set_cancel(cancel_visible: bool, cancel_enabled: bool = false) -> void:
	_cancel_button.visible = cancel_visible
	_cancel_button.disabled = not cancel_enabled


## 게이트 숨김. 입력 통과.
func hide_gate() -> void:
	visible = false
	set_process(false)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cancel_button.visible = false
	_cancel_button.disabled = true


## 취소 클릭 → 시그널만 (로직은 호출 측).
func _on_cancel_button_pressed() -> void:
	if _cancel_button.disabled:
		return
	cancel_pressed.emit()
