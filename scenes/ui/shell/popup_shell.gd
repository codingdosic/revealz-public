class_name PopupShell
extends Control
## L4a 팝업 셸 — 확인형(confirm) / 알림형(notice) / 콘텐츠 마운트.
##
## A) 빌트인 UI: configure_confirm / configure_notice
## B) 기존 패널 주입: ContentSlot에 EffectDialog 등 배치 후 mount 모드
##
## configure_confirm options:
##   confirm_only (bool) — 취소 버튼 숨김 (GameOver 등)
##   full_dimmer (bool) — 전체화면 딤머 + 중앙 패널
##   block_dismiss (bool) — 우클릭/ESC/바깥클릭 무시
##
## ButtonRow 순서 SSOT: Cancel | Confirm (왼쪽 취소 · 오른쪽 확인).
## 열림/닫힘 슬라이드 (`POPUP_SLIDE_*`). 확인=아래→위 · 알림=위→아래.
## 튜닝: UiShellConstants.POPUP_* · dismiss_on_* · UiChromeStyle

signal closed(reason: String)
signal confirmed
signal canceled

enum Mode { CONFIRM, NOTICE, CONTENT_CONFIRM, CONTENT_NOTICE }

@export var dismiss_on_right_click: bool = true
@export var dismiss_on_esc: bool = true
## 알림·콘텐츠알림은 보통 false. 확인형은 false 권장(버튼으로만 닫기).
@export var dismiss_on_outside_click: bool = false
## 빌트인 패널·버튼 룩. null 이면 ui_chrome_cyan.
@export var chrome_style: UiChromeStyle

var _mode: Mode = Mode.CONFIRM
var _on_confirm: Callable
var _on_cancel: Callable
var _dismiss: UiDismissPolicy = UiDismissPolicy.new()
var _bound_content: Control
var _confirm_only: bool = false
var _full_dimmer: bool = false
var _block_dismiss: bool = false
var _motion: Tween
var _slide: UiShellSlide = UiShellSlide.new()
var _closing: bool = false

@onready var _dimmer: ColorRect = $Dimmer
@onready var _builtin_root: Control = $Builtin
@onready var _title: Label = $Builtin/Margin/VBox/TitleLabel
@onready var _message: Label = $Builtin/Margin/VBox/MessageLabel
@onready var _button_row: HBoxContainer = $Builtin/Margin/VBox/ButtonRow
@onready var _confirm_button: Button = $Builtin/Margin/VBox/ButtonRow/ConfirmButton
@onready var _cancel_button: Button = $Builtin/Margin/VBox/ButtonRow/CancelButton
@onready var _content_slot: Control = $ContentSlot


## 부트: 숨김 · 크롬 · dismiss · 버튼 시그널 · ContentSlot 마운트.
func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dimmer:
		_dimmer.visible = false
		_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dismiss.bind(self)
	_sync_dismiss_flags()
	_dismiss.dismiss_requested.connect(_on_dismiss_requested)
	if _confirm_button:
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _cancel_button:
		_cancel_button.pressed.connect(_on_cancel_pressed)
	apply_chrome(chrome_style)
	_prepare_mounted_content()


## 크롬 팔레트로 빌트인 패널·라벨·확인/취소 버튼을 갱신한다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	if _builtin_root is PanelContainer:
		chrome_style.apply_panel(_builtin_root as PanelContainer)
	chrome_style.apply_title_label(_title)
	chrome_style.apply_muted_label(_message)
	chrome_style.apply_buttons([_confirm_button, _cancel_button])


## 입력 이벤트를 dismiss 정책에 넘긴다.
func _input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if _mode == Mode.NOTICE or _mode == Mode.CONTENT_NOTICE:
		return
	if _block_dismiss:
		return
	if _dismiss.handle_event(event):
		get_viewport().set_input_as_handled()


## dismiss_on_* export 와 block_dismiss 를 정책 객체에 반영한다.
func _sync_dismiss_flags() -> void:
	_dismiss.dismiss_on_right_click = dismiss_on_right_click and not _block_dismiss
	_dismiss.dismiss_on_esc = dismiss_on_esc and not _block_dismiss
	_dismiss.dismiss_on_outside_click = dismiss_on_outside_click and not _block_dismiss


## 확인/취소 빌트인 팝업.
## options: confirm_only / full_dimmer / block_dismiss
func configure_confirm(
	title: String,
	message: String,
	on_confirm: Callable = Callable(),
	on_cancel: Callable = Callable(),
	confirm_text: String = "",
	cancel_text: String = "",
	options: Dictionary = {}
) -> void:
	_mode = Mode.CONFIRM
	_on_confirm = on_confirm
	_on_cancel = on_cancel
	_confirm_only = bool(options.get("confirm_only", false))
	_full_dimmer = bool(options.get("full_dimmer", false))
	_block_dismiss = bool(options.get("block_dismiss", false))
	_show_builtin(true)
	_title.text = title
	_message.text = message
	var copy := UiChromeStyle.resolve(chrome_style).get_copy()
	_confirm_button.text = confirm_text if not confirm_text.is_empty() else copy.confirm
	_cancel_button.text = cancel_text if not cancel_text.is_empty() else copy.cancel
	_button_row.visible = true
	_confirm_button.visible = true
	_cancel_button.visible = not _confirm_only
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _full_dimmer:
		_apply_full_dimmer_layout()
	else:
		_apply_confirm_layout()
	_sync_dismiss_flags()


## 단순 알림 빌트인 (버튼 없음, 클릭 통과).
func configure_notice(title: String, message: String) -> void:
	_mode = Mode.NOTICE
	_on_confirm = Callable()
	_on_cancel = Callable()
	_confirm_only = false
	_full_dimmer = false
	_block_dismiss = false
	_show_builtin(true)
	_title.text = title
	_message.text = message
	_button_row.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_notice_layout()
	_sync_dismiss_flags()


## ContentSlot 자식을 확인형 호스트로 (EffectDialogPanel 등).
func use_content_confirm() -> void:
	_mode = Mode.CONTENT_CONFIRM
	_confirm_only = false
	_full_dimmer = false
	_block_dismiss = false
	_show_builtin(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_confirm_layout()
	_prepare_mounted_content()
	_sync_dismiss_flags()


## ContentSlot 자식을 알림형 호스트로 (EffectNoticePanel 등).
func use_content_notice() -> void:
	_mode = Mode.CONTENT_NOTICE
	_confirm_only = false
	_full_dimmer = false
	_block_dismiss = false
	_show_builtin(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_notice_layout()
	_prepare_mounted_content()
	_sync_dismiss_flags()


## ContentSlot 에 콘텐츠를 넣고 꽉 채운다.
func set_content(content: Control) -> void:
	for child in _content_slot.get_children():
		_content_slot.remove_child(child)
		child.queue_free()
	if content.get_parent():
		content.get_parent().remove_child(content)
	_content_slot.add_child(content)
	_bound_content = content
	_fit_content(content)


## 현재 ContentSlot 바인딩 콘텐츠.
func get_content() -> Control:
	return _bound_content


## 팝업을 표시한다. 패널을 아래에서 슬라이드인. 풀딤머면 확인 버튼에 포커스.
func open() -> void:
	_closing = false
	_sync_dismiss_flags()
	# ContentSlot 이 tscn에서 visible=false 로 시작하면, 콘텐츠 모드에서 슬롯을 먼저 연다.
	if _mode == Mode.CONTENT_CONFIRM or _mode == Mode.CONTENT_NOTICE:
		_show_builtin(false)
	visible = true
	move_to_front()
	if _bound_content and is_instance_valid(_bound_content):
		_bound_content.visible = true
	if _full_dimmer and _confirm_button:
		_confirm_button.grab_focus()
	_reapply_layout()
	_play_slide_in()


## 팝업을 슬라이드아웃 후 숨기고 closed 를 낸다. 호출은 동기(연출은 비동기).
func close(reason: String = "close") -> void:
	if _closing:
		return
	if not visible:
		_hide_now()
		return
	_closing = true
	_play_slide_out(reason)


## 닫기 정책 객체를 반환한다.
func get_dismiss_policy() -> UiDismissPolicy:
	return _dismiss


## 빌트인 루트와 ContentSlot 의 표시를 전환한다.
func _show_builtin(on: bool) -> void:
	if _builtin_root:
		_builtin_root.visible = on
	if _content_slot:
		_content_slot.visible = not on


## 슬롯 첫 자식을 콘텐츠로 바인딩한다 (tscn 배치용).
func _prepare_mounted_content() -> void:
	if _content_slot == null or _content_slot.get_child_count() == 0:
		return
	var content := _content_slot.get_child(0) as Control
	if content == null:
		return
	_bound_content = content
	_fit_content(content)
	if _mode == Mode.CONTENT_CONFIRM or _mode == Mode.CONTENT_NOTICE:
		_show_builtin(false)


## 콘텐츠를 슬롯 FULL_RECT 로 맞춘다.
func _fit_content(content: Control) -> void:
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 0.0
	content.offset_top = 0.0
	content.offset_right = 0.0
	content.offset_bottom = 0.0
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL


## 중앙 확인형 크기·앵커 (딤머 없음).
func _apply_confirm_layout() -> void:
	if _dimmer:
		_dimmer.visible = false
		_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var half := UiShellConstants.POPUP_CONFIRM_HALF
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -half.x
	offset_top = -half.y
	offset_right = half.x
	offset_bottom = half.y
	if _builtin_root:
		_builtin_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_builtin_root.offset_left = 0.0
		_builtin_root.offset_top = 0.0
		_builtin_root.offset_right = 0.0
		_builtin_root.offset_bottom = 0.0
	if _content_slot:
		_content_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cache_slide_rest()


## GameOver 등: 루트 전체화면 + 딤머 + 중앙 Builtin 패널.
func _apply_full_dimmer_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	if _dimmer:
		_dimmer.visible = true
		_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
		_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _builtin_root:
		var half := UiShellConstants.POPUP_CONFIRM_HALF
		# GameOver 기존 패널과 비슷한 여유.
		var half_go := Vector2(maxf(half.x, 200.0), maxf(half.y, 110.0))
		_builtin_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_builtin_root.offset_left = -half_go.x
		_builtin_root.offset_top = -half_go.y
		_builtin_root.offset_right = half_go.x
		_builtin_root.offset_bottom = half_go.y
	if _content_slot:
		_content_slot.visible = false
	_cache_slide_rest()


## 상단 알림형 크기·앵커.
func _apply_notice_layout() -> void:
	if _dimmer:
		_dimmer.visible = false
		_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hw := UiShellConstants.POPUP_NOTICE_HALF_WIDTH
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -hw
	offset_top = UiShellConstants.POPUP_NOTICE_TOP
	offset_right = hw
	offset_bottom = UiShellConstants.POPUP_NOTICE_TOP + 56.0
	if _builtin_root:
		_builtin_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_builtin_root.offset_left = 0.0
		_builtin_root.offset_top = 0.0
		_builtin_root.offset_right = 0.0
		_builtin_root.offset_bottom = 0.0
	if _content_slot:
		_content_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cache_slide_rest()


## 확인 버튼 — confirmed 후 close.
func _on_confirm_pressed() -> void:
	confirmed.emit()
	if _on_confirm.is_valid():
		_on_confirm.call()
	close("confirm")


## 취소 버튼 — canceled 후 close.
func _on_cancel_pressed() -> void:
	canceled.emit()
	if _on_cancel.is_valid():
		_on_cancel.call()
	close("cancel")


## ESC/우클릭/바깥클릭 dismiss. CONFIRM 모드는 cancel 취급.
func _on_dismiss_requested(reason: String) -> void:
	if _block_dismiss or _closing:
		return
	if _mode == Mode.CONFIRM or _mode == Mode.CONTENT_CONFIRM:
		canceled.emit()
		if _on_cancel.is_valid():
			_on_cancel.call()
	close(reason)


## RMB/취소로 닫을 수 있는 열린 확인 팝업이면 true (GameOver block 제외).
func is_rmb_cancelable() -> bool:
	if not visible or _block_dismiss or _closing:
		return false
	if _mode == Mode.NOTICE or _mode == Mode.CONTENT_NOTICE:
		return false
	if _confirm_only:
		return false
	return dismiss_on_right_click


## 취소 버튼과 동일하게 닫는다 (스크린 Back·RMB 우선처리용).
func request_cancel() -> void:
	if not is_rmb_cancelable():
		return
	_on_cancel_pressed()


## 슬라이드 대상 패널. 풀딤머·빌트인은 Builtin, 콘텐츠 마운트는 ContentSlot.
func _slide_panel() -> Control:
	if _mode == Mode.CONTENT_CONFIRM or _mode == Mode.CONTENT_NOTICE:
		return _content_slot
	return _builtin_root


## 현재 모드 레이아웃을 다시 적용해 슬라이드 rest를 맞춘다.
func _reapply_layout() -> void:
	if _full_dimmer:
		_apply_full_dimmer_layout()
	elif _mode == Mode.NOTICE or _mode == Mode.CONTENT_NOTICE:
		_apply_notice_layout()
	else:
		_apply_confirm_layout()


## 레이아웃 적용 직후 패널 정지 offset을 기억한다.
func _cache_slide_rest() -> void:
	_slide.capture(_slide_panel(), false)


## 알림은 위에서, 확인은 아래에서 들어온다.
func _slide_off_delta() -> float:
	if _mode == Mode.NOTICE or _mode == Mode.CONTENT_NOTICE:
		return -UiShellConstants.POPUP_SLIDE_PX
	return UiShellConstants.POPUP_SLIDE_PX


## 슬라이드 오프셋 dy(아래가 +)를 패널 높이를 유지한 채 적용한다.
func _set_slide_y(dy: float) -> void:
	_slide.apply(_slide_panel(), dy)


## 진행 중 슬라이드 Tween을 끊는다.
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
	if _dimmer:
		_dimmer.visible = false
		_dimmer.modulate.a = 1.0
	_set_slide_y(0.0)


## 패널을 오프스크린에서 제자리로 민다. 딤머가 있으면 알파도 같이.
func _play_slide_in() -> void:
	_kill_motion()
	var panel := _slide_panel()
	if panel == null:
		return
	var dy := _slide_off_delta()
	if DisplayServer.get_name() == "headless":
		_set_slide_y(0.0)
		if _dimmer and _dimmer.visible:
			_dimmer.modulate.a = 1.0
		return
	_set_slide_y(dy)
	if _dimmer and _dimmer.visible:
		_dimmer.modulate.a = 0.0
	_motion = create_tween()
	_motion.set_parallel(true)
	_motion.tween_method(_set_slide_y, dy, 0.0, UiShellConstants.POPUP_SLIDE_IN_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	if _dimmer and _dimmer.visible:
		_motion.tween_property(_dimmer, "modulate:a", 1.0, UiShellConstants.POPUP_SLIDE_IN_SEC)


## 패널을 오프스크린으로 밀고 숨긴 뒤 closed 를 낸다.
func _play_slide_out(reason: String) -> void:
	_kill_motion()
	var panel := _slide_panel()
	if panel == null or DisplayServer.get_name() == "headless":
		_finish_close(reason)
		return
	var dy := _slide_off_delta()
	_motion = create_tween()
	_motion.set_parallel(true)
	_motion.tween_method(_set_slide_y, 0.0, dy, UiShellConstants.POPUP_SLIDE_OUT_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_IN)
	if _dimmer and _dimmer.visible:
		_motion.tween_property(_dimmer, "modulate:a", 0.0, UiShellConstants.POPUP_SLIDE_OUT_SEC)
	_motion.chain()
	_motion.tween_callback(_finish_close.bind(reason))


## 슬라이드아웃 종료: 숨김 · rest 복구 · closed.
func _finish_close(reason: String) -> void:
	var was_visible := visible
	_hide_now()
	if was_visible:
		closed.emit(reason)

