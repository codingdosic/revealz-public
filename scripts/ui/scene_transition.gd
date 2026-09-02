extends CanvasLayer
## 씬 전환용 검정 페이드. Autoload — 씬이 바뀌어도 커버가 유지되어 깜빡임을 막는다.

const DEFAULT_FADE_SEC := 0.55
const LAYER_Z := 4096

var _cover: ColorRect
var _pending_fade_in := false
var _pending_fade_in_sec := DEFAULT_FADE_SEC
var _tween: Tween


func _ready() -> void:
	layer = LAYER_Z
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = ColorRect.new()
	_cover.name = "Cover"
	_cover.color = Color.BLACK
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	_cover.modulate.a = 0.0
	add_child(_cover)


func is_blocking_input() -> bool:
	return _cover.visible and _cover.modulate.a > 0.05


func ensure_black() -> void:
	_kill_tween()
	_cover.visible = true
	_cover.modulate.a = 1.0
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP


func hide_immediate() -> void:
	_kill_tween()
	_cover.visible = false
	_cover.modulate.a = 0.0
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 씬 교체 직전 호출. 검정 유지 + 새 씬에서 take_pending_fade_in() 후 fade_from_black().
func arm_fade_in_after_scene_change(duration: float = DEFAULT_FADE_SEC) -> void:
	_pending_fade_in = true
	_pending_fade_in_sec = maxf(duration, 0.0)
	ensure_black()


## 예약된 페이드인 길이(초). 없으면 -1.
func take_pending_fade_in() -> float:
	if not _pending_fade_in:
		return -1.0
	_pending_fade_in = false
	return _pending_fade_in_sec


func fade_to_black(duration: float = DEFAULT_FADE_SEC) -> void:
	if duration <= 0.0:
		ensure_black()
		return
	_cover.visible = true
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_cover, "modulate:a", 1.0, duration)
	await _tween.finished
	_cover.modulate.a = 1.0


func fade_from_black(duration: float = DEFAULT_FADE_SEC) -> void:
	if not _cover.visible and _cover.modulate.a <= 0.0:
		return
	ensure_black()
	_kill_tween()
	if duration <= 0.0:
		hide_immediate()
		return
	_tween = create_tween()
	_tween.tween_property(_cover, "modulate:a", 0.0, duration)
	await _tween.finished
	hide_immediate()


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
