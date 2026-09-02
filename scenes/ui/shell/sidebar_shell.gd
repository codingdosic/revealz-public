class_name SidebarShell
extends Control
## L4a 사이드바 셸 — 틀(좌/우·폭)·닫기 조작. 패널 비주얼은 ContentSlot 자식이 담당.
##
## 사용 (에디터):
##   SidebarShell
##     ContentSlot
##       CardInfoSidebar (등)
##   shell.setup(ShellSide.LEFT) · open()/close()
##
## 튜닝: UiShellConstants.SIDEBAR_WIDTH / SIDEBAR_TOP_INSET / SIDEBAR_BOTTOM_INSET / SIDEBAR_SLIDE_*
## 닫기: dismiss_on_* / get_dismiss_policy()
## 열림/닫힘: 좌→우 또는 우→좌 슬라이드.
## 주의: enum 이름은 GameConstants.Side 와 겹치지 않게 ShellSide.

signal closed(reason: String)

enum ShellSide { LEFT, RIGHT }

## 바깥 좌클릭으로 닫기 (카드정보·존 브라우즈에 권장). 매치메뉴는 딤머가 있으므로 false.
@export var dismiss_on_outside_click: bool = true
@export var dismiss_on_right_click: bool = true
@export var dismiss_on_esc: bool = true
@export var shell_side: ShellSide = ShellSide.LEFT
## true 면 TOP/BOTTOM inset 적용(인게임). 덱에디터 embedded 는 false.
@export var use_screen_insets: bool = true

var _dismiss: UiDismissPolicy = UiDismissPolicy.new()
var _bound_content: Control
## >=0 이면 SIDEBAR_TOP_INSET 대신 사용. -1 = 상수 기본값.
var _top_inset_override: float = -1.0
var _motion: Tween
var _slide: UiShellSlide = UiShellSlide.new()
var _closing: bool = false


## 부트: 숨김 · dismiss · 좌/우 레이아웃 · ContentSlot 보장.
func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dismiss.bind(self)
	_sync_dismiss_flags()
	_dismiss.dismiss_requested.connect(_on_dismiss_requested)
	_apply_side_layout()
	if get_node_or_null("ContentSlot") == null:
		var slot := MarginContainer.new()
		slot.name = "ContentSlot"
		slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
	_prepare_mounted_content()


## 입력 이벤트를 dismiss 정책에 넘긴다.
func _input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if _dismiss.handle_event(event):
		get_viewport().set_input_as_handled()


## dismiss_on_* export 를 정책 객체에 반영한다.
func _sync_dismiss_flags() -> void:
	_dismiss.dismiss_on_outside_click = dismiss_on_outside_click
	_dismiss.dismiss_on_right_click = dismiss_on_right_click
	_dismiss.dismiss_on_esc = dismiss_on_esc


## 좌/우 스트립 배치. 폭 변경: UiShellConstants.SIDEBAR_WIDTH
## top_inset_override>=0 이면 SIDEBAR_TOP_INSET 대신 사용 (매치메뉴=0).
func setup(p_side: ShellSide, width: float = -1.0, top_inset_override: float = -1.0) -> void:
	shell_side = p_side
	use_screen_insets = true
	if width < 0.0:
		width = UiShellConstants.SIDEBAR_WIDTH
	custom_minimum_size.x = width
	_top_inset_override = top_inset_override
	_apply_side_layout()


## 부모 Control 안에 채움 (덱 에디터 LeftPane 등). 뷰포트 inset 미사용.
func setup_embedded(width: float = -1.0) -> void:
	use_screen_insets = false
	if width < 0.0:
		width = UiShellConstants.SIDEBAR_WIDTH
	custom_minimum_size.x = width
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


## 좌/우 앵커·폭·상하 inset 을 적용한다.
func _apply_side_layout() -> void:
	var width := custom_minimum_size.x
	if width <= 0.0:
		width = UiShellConstants.SIDEBAR_WIDTH
		custom_minimum_size.x = width
	if shell_side == ShellSide.LEFT:
		set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		offset_left = 0.0
		offset_right = width
	else:
		set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		offset_left = -width
		offset_right = 0.0
	if use_screen_insets:
		var top := UiShellConstants.SIDEBAR_TOP_INSET
		if _top_inset_override >= 0.0:
			top = _top_inset_override
		offset_top = top
		offset_bottom = -UiShellConstants.SIDEBAR_BOTTOM_INSET
	else:
		offset_top = 0.0
		offset_bottom = 0.0


## 내부 콘텐츠를 ContentSlot에 넣는다.
func set_content(content: Control) -> void:
	var slot := _content_slot()
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	if content.get_parent():
		content.get_parent().remove_child(content)
	slot.add_child(content)
	_bound_content = content
	_fit_content(content)


## 슬롯에 이미 있는 첫 자식을 콘텐츠로 인식 (tscn 배치용).
func _prepare_mounted_content() -> void:
	var slot := _content_slot()
	if slot.get_child_count() == 0:
		return
	var content := slot.get_child(0) as Control
	if content == null:
		return
	_bound_content = content
	_fit_content(content)


## 콘텐츠를 슬롯 FULL_RECT 로 맞춘다.
func _fit_content(content: Control) -> void:
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 0.0
	content.offset_top = 0.0
	content.offset_right = 0.0
	content.offset_bottom = 0.0
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL


## 바인딩된 콘텐츠 Control.
func get_content() -> Control:
	return _bound_content


## ContentSlot 노드.
func get_content_slot() -> Control:
	return _content_slot()


## 닫기 정책 객체.
func get_dismiss_policy() -> UiDismissPolicy:
	return _dismiss


## 사이드바를 표시하고 옆에서 슬라이드인한다.
func open() -> void:
	_closing = false
	_sync_dismiss_flags()
	_apply_side_layout()
	_slide.capture(self, true)
	visible = true
	if _bound_content and is_instance_valid(_bound_content):
		_bound_content.visible = true
	_play_slide_in()


## 사이드바를 슬라이드아웃 후 숨기고 closed 를 낸다.
func close(reason: String = "close") -> void:
	if _closing:
		return
	if not visible:
		# 셸은 숨겼는데 콘텐츠만 visible 인 꼬임 복구.
		if _bound_content and is_instance_valid(_bound_content):
			_bound_content.visible = false
		_set_slide_x(0.0)
		return
	_closing = true
	_play_slide_out(reason)


## ContentSlot 노드를 반환한다.
func _content_slot() -> Control:
	return get_node("ContentSlot") as Control


## dismiss 요청 시 close.
func _on_dismiss_requested(reason: String) -> void:
	if _closing:
		return
	close(reason)


## 왼쪽은 -, 오른쪽은 + 방향으로 폭만큼 숨긴다.
func _slide_off_delta() -> float:
	var w := custom_minimum_size.x
	if w <= 1.0:
		w = size.x if size.x > 1.0 else UiShellConstants.SIDEBAR_WIDTH
	return -w if shell_side == ShellSide.LEFT else w


## 가로 슬라이드 delta(오른쪽이 +)를 적용한다.
func _set_slide_x(dx: float) -> void:
	_slide.apply(self, dx)


## 진행 중 Tween을 끊는다.
func _kill_motion() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	_motion = null


## 연출 없이 즉시 숨긴다.
func _hide_now() -> void:
	_kill_motion()
	_closing = false
	visible = false
	if _bound_content and is_instance_valid(_bound_content):
		_bound_content.visible = false
	_set_slide_x(0.0)


## 옆에서 제자리로 민다.
func _play_slide_in() -> void:
	_kill_motion()
	var dx := _slide_off_delta()
	if DisplayServer.get_name() == "headless":
		_set_slide_x(0.0)
		return
	_set_slide_x(dx)
	_motion = create_tween()
	_motion.tween_method(_set_slide_x, dx, 0.0, UiShellConstants.SIDEBAR_SLIDE_IN_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)


## 옆으로 밀고 숨긴 뒤 closed 를 낸다.
func _play_slide_out(reason: String) -> void:
	_kill_motion()
	if DisplayServer.get_name() == "headless":
		_finish_close(reason)
		return
	var dx := _slide_off_delta()
	_motion = create_tween()
	_motion.tween_method(_set_slide_x, 0.0, dx, UiShellConstants.SIDEBAR_SLIDE_OUT_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_IN)
	_motion.tween_callback(_finish_close.bind(reason))


## 슬라이드아웃 종료: 숨김 · rest 복구 · closed.
func _finish_close(reason: String) -> void:
	var was_visible := visible
	_hide_now()
	if was_visible:
		closed.emit(reason)
