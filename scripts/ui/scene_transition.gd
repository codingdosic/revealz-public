extends CanvasLayer
## 씬 전환용 검정 페이드. Autoload — 씬이 바뀌어도 커버가 유지되어 깜빡임을 막는다.

enum FadeInStyle { UNIFORM, RADIAL_CENTER }

const DEFAULT_FADE_SEC := 0.55
const LAYER_Z := 4096

var _root: Control
var _uniform_cover: ColorRect
var _radial_cover: RadialRevealCover
var _armed := false
var _armed_duration := DEFAULT_FADE_SEC
var _armed_style := FadeInStyle.UNIFORM
var _tween: Tween


func _ready() -> void:
	layer = LAYER_Z
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_uniform_cover = ColorRect.new()
	_uniform_cover.name = "UniformCover"
	_uniform_cover.color = Color.BLACK
	_uniform_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_uniform_cover.visible = false
	_root.add_child(_uniform_cover)
	_radial_cover = RadialRevealCover.new()
	_radial_cover.name = "RadialCover"
	_radial_cover.visible = false
	_root.add_child(_radial_cover)
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_sync_root_size):
		vp.size_changed.connect(_sync_root_size)
	_sync_root_size()


func _sync_root_size() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var rect := vp.get_visible_rect()
	_root.position = rect.position
	_root.size = rect.size
	_uniform_cover.position = Vector2.ZERO
	_uniform_cover.size = rect.size
	_radial_cover.position = Vector2.ZERO
	_radial_cover.size = rect.size


func is_blocking_input() -> bool:
	if _radial_cover.visible and _radial_cover.progress < 0.98:
		return true
	if _uniform_cover.visible and _uniform_cover.modulate.a > 0.05:
		return true
	return false


func ensure_black() -> void:
	_kill_tween()
	_hide_all_covers()
	_uniform_cover.visible = true
	_uniform_cover.modulate = Color(1, 1, 1, 1)
	_uniform_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_root_size()


func hide_immediate() -> void:
	_kill_tween()
	_hide_all_covers()


## 씬 교체 직전 호출. 새 씬에서 play_armed_fade_in()으로 이어서 밝힌다.
func arm_fade_in_after_scene_change(
	duration: float = DEFAULT_FADE_SEC,
	style: FadeInStyle = FadeInStyle.UNIFORM
) -> void:
	_armed = true
	_armed_duration = maxf(duration, 0.0)
	_armed_style = style
	_sync_root_size()
	if style == FadeInStyle.RADIAL_CENTER:
		_show_radial_at_zero()
	else:
		ensure_black()


## 게임/메뉴 씬 _ready에서 직접 await. scene_changed에 의존하지 않는다.
func play_armed_fade_in() -> void:
	if not _armed:
		return
	_armed = false
	var duration := _armed_duration
	var style := _armed_style
	_sync_root_size()
	await fade_from_black(duration, style)


func fade_to_black(duration: float = DEFAULT_FADE_SEC) -> void:
	_sync_root_size()
	if duration <= 0.0:
		ensure_black()
		return
	_hide_all_covers()
	_uniform_cover.visible = true
	_uniform_cover.modulate = Color(1, 1, 1, 0.0)
	_uniform_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_uniform_cover, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _tween.finished
	_uniform_cover.modulate = Color(1, 1, 1, 1)


func fade_from_black(
	duration: float = DEFAULT_FADE_SEC,
	style: FadeInStyle = FadeInStyle.UNIFORM
) -> void:
	_sync_root_size()
	_kill_tween()
	if duration <= 0.0:
		hide_immediate()
		return
	if style == FadeInStyle.RADIAL_CENTER:
		await _fade_from_black_radial(duration)
	else:
		await _fade_from_black_uniform(duration)


func _fade_from_black_uniform(duration: float) -> void:
	ensure_black()
	_tween = create_tween()
	_tween.tween_property(_uniform_cover, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	hide_immediate()


func _fade_from_black_radial(duration: float) -> void:
	_show_radial_at_zero()
	var tree := get_tree()
	if tree == null:
		hide_immediate()
		return
	var start_usec := Time.get_ticks_usec()
	var dur_usec := int(maxf(duration, 0.001) * 1_000_000.0)
	while true:
		await tree.process_frame
		_sync_root_size()
		var elapsed_usec := Time.get_ticks_usec() - start_usec
		var raw := clampf(float(elapsed_usec) / float(dur_usec), 0.0, 1.0)
		_radial_cover.progress = _ease_in_out_smooth(raw)
		if raw >= 1.0:
			break
	hide_immediate()


func _show_radial_at_zero() -> void:
	_kill_tween()
	_uniform_cover.visible = false
	_radial_cover.visible = true
	_radial_cover.progress = 0.0
	_radial_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_root_size()


func _hide_all_covers() -> void:
	_uniform_cover.visible = false
	_uniform_cover.modulate = Color(1, 1, 1, 1)
	_uniform_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial_cover.visible = false
	_radial_cover.progress = 0.0
	_radial_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ease_in_out_smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
