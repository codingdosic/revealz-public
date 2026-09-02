extends Control
class_name PhaseToast

## 페이즈 전환 토스트. 오른쪽에서 중앙으로 들어온 뒤 대기, 왼쪽으로 나간다.
## 표시 중 mouse stop으로 클릭 차단.
## 룩: UiChromeStyle (기본 ui_chrome_cyan.tres). 인스펙터 chrome_style 로 조색.
## 패널: 라운드 없음 · 좌상단 챔퍼 (UiChamferStyleBox).
## 튜닝: UiShellConstants.TOAST_SLIDE_SEC · UiChromeStyle.toast_duration

@export var chrome_style: UiChromeStyle

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Label

var _style: StyleBox
var _chrome: UiChromeStyle
var _slide: UiShellSlide = UiShellSlide.new()
var _motion: Tween
var _play_id: int = 0


## 부트: 숨김 · 크롬 적용 · 풀스크린 클릭 차단 준비.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	apply_chrome(chrome_style)
	if _panel:
		_slide.capture(_panel, true)


## 크롬 팔레트로 토스트 패널·글자 스타일을 갱신한다.
func apply_chrome(style: UiChromeStyle) -> void:
	_chrome = UiChromeStyle.resolve(style)
	chrome_style = _chrome
	_style = _chrome.make_toast_stylebox()
	if _panel:
		_panel.add_theme_stylebox_override("panel", _style)
	if _label:
		_label.add_theme_color_override("font_color", _chrome.toast_font)
		_label.add_theme_font_size_override("font_size", _chrome.toast_font_size)


## 오른쪽에서 들어와 duration초 대기 후 왼쪽으로 나간다. await 가능.
func play(message: String, duration: float = -1.0) -> void:
	if _chrome == null:
		apply_chrome(chrome_style)
	if _label:
		_label.text = message
		_label.add_theme_color_override("font_color", _chrome.toast_font)
		_label.add_theme_font_size_override("font_size", _chrome.toast_font_size)
	_refresh_toast_style_colors()
	var wait_sec := duration if duration >= 0.0 else _chrome.toast_duration
	_play_id += 1
	var id := _play_id
	_kill_motion()
	if _panel:
		_slide.capture(_panel, true)
	var travel := _toast_travel()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	if DisplayServer.get_name() == "headless":
		_set_slide_x(0.0)
		await get_tree().create_timer(wait_sec).timeout
		if id != _play_id:
			return
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_set_slide_x(travel)
	_motion = create_tween()
	_motion.tween_method(_set_slide_x, travel, 0.0, UiShellConstants.TOAST_SLIDE_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(UiShellConstants.TOAST_SLIDE_SEC).timeout
	if id != _play_id:
		return
	await get_tree().create_timer(wait_sec).timeout
	if id != _play_id:
		return
	_kill_motion()
	_motion = create_tween()
	_motion.tween_method(_set_slide_x, 0.0, -travel, UiShellConstants.TOAST_SLIDE_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(UiShellConstants.TOAST_SLIDE_SEC).timeout
	if id != _play_id:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_slide_x(0.0)


## 화면 밖으로 나가기에 충분한 가로 이동량.
func _toast_travel() -> float:
	var half_panel := 160.0
	if _panel:
		half_panel = maxf(absf(_panel.offset_left), _panel.size.x * 0.5)
	var view_w := get_viewport_rect().size.x
	if view_w < 1.0:
		view_w = 1280.0
	return view_w * 0.5 + half_panel + 16.0


## 패널 가로 슬라이드 (오른쪽이 +).
func _set_slide_x(dx: float) -> void:
	if _panel:
		_slide.apply(_panel, dx)


## 진행 중 Tween을 끊는다.
func _kill_motion() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	_motion = null


## 토스트 StyleBox 색을 크롬 toast_* 로 맞춘다.
func _refresh_toast_style_colors() -> void:
	if _chrome == null:
		return
	if _style is UiChamferStyleBox:
		var chamfer := _style as UiChamferStyleBox
		chamfer.bg_color = _chrome.toast_bg
		chamfer.border_color = _chrome.toast_border
		chamfer.chamfer_tl = float(_chrome.chamfer_top_left)
	elif _style is StyleBoxFlat:
		var flat := _style as StyleBoxFlat
		flat.bg_color = _chrome.toast_bg
		flat.border_color = _chrome.toast_border
	elif _panel:
		_style = _chrome.make_toast_stylebox()
		_panel.add_theme_stylebox_override("panel", _style)
