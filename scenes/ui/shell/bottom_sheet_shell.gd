class_name BottomSheetShell
extends PanelContainer
## L4a 타겟 선택 바텀시트 셸 — 공통 크롬(제목·확인·최소화) + ContentSlot.
## 모드: LIST(카드 스크롤 콘텐츠) / FIELD(메시지 콘텐츠).
##
## 튜닝: UiShellConstants.BOTTOM_BAR_SIDE_MARGIN · FIELD_PROMPT_HEIGHT · FIELD_PROMPT_EDGE_MARGIN · TARGET_BAR_HEIGHT · SHEET_SLIDE_*
## 최소화: 클릭 핸들(MinimizeHandle) — 드래그 접기 없음. 복귀는 슬라이드인.
## 룩: UiChromeStyle.

signal selection_confirmed
signal selection_canceled
signal minimized

enum ContentMode { LIST, FIELD }

@export var chrome_style: UiChromeStyle

@onready var _title: Label = $Margin/VBox/TitleRow/TitleLabel
@onready var _minimize_button: Button = $Margin/VBox/TitleRow/MinimizeButton
@onready var _confirm_button: Button = $Margin/VBox/TitleRow/ConfirmButton
@onready var _cancel_button: Button = $Margin/VBox/TitleRow/CancelButton
@onready var _message: Label = $Margin/VBox/MessageLabel
@onready var _content_slot: Control = $Margin/VBox/ContentSlot

var _mode: ContentMode = ContentMode.LIST
var _bound_content: Control
var _anchor_top: bool = false
var _motion: Tween
var _slide: UiShellSlide = UiShellSlide.new()
var _closing: bool = false
var _hide_content_after: bool = false


## 부트: 시그널 · 크롬 · 마운트 · 하단 레이아웃.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	visible = false
	_minimize_button.pressed.connect(_on_minimize_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	if _cancel_button:
		_cancel_button.pressed.connect(_on_cancel_pressed)
	apply_chrome(chrome_style)
	_prepare_mounted_content()
	_apply_bottom_layout()


## 크롬 팔레트로 시트 패널·라벨·버튼·콘텐츠 스크롤바를 갱신한다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	chrome_style.apply_sheet_panel(self)
	chrome_style.apply_title_label(_title)
	chrome_style.apply_muted_label(_message)
	if _message:
		_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chrome_style.apply_buttons([_minimize_button, _confirm_button, _cancel_button])
	var copy := chrome_style.get_copy()
	if _cancel_button:
		_cancel_button.text = copy.cancel
	_apply_scroll_chrome_in_slot()


## ContentSlot(타겟 리스트 스크롤 등) 안의 ScrollContainer에 테마 스크롤바를 입힌다.
func _apply_scroll_chrome_in_slot() -> void:
	var root: Node = _bound_content if _bound_content else _content_slot
	if root == null:
		return
	_apply_scroll_chrome_recursive(root)


## 하위 ScrollContainer에 apply_scroll_container.
func _apply_scroll_chrome_recursive(node: Node) -> void:
	if node is ScrollContainer:
		chrome_style.apply_scroll_container(node as ScrollContainer)
	for child in node.get_children():
		_apply_scroll_chrome_recursive(child)


## LIST 모드로 연다. 콘텐츠 API(show_selection 등)는 ContentSlot 자식이 담당.
## show_cancel=true 는 효과 발동 선택(미발동 넘기기)용. 타겟 선택은 기본 false.
func open_list(title_text: String, show_cancel: bool = false) -> void:
	_mode = ContentMode.LIST
	_title.text = title_text
	_message.visible = false
	_content_slot.visible = true
	_minimize_button.visible = true
	_confirm_button.visible = true
	_confirm_button.disabled = true
	_confirm_button.text = UiChromeStyle.resolve(chrome_style).get_copy().confirm
	_set_cancel_visible(show_cancel)
	_anchor_top = false
	_apply_bottom_layout()
	_show_bound_content(true)
	visible = true
	_play_slide_in()


## FIELD 모드로 연다. message는 셸에, 추가 콘텐츠는 슬롯(없으면 메시지만).
func open_field(title_text: String, message_text: String, needed: int, anchor_top: bool = false) -> void:
	_mode = ContentMode.FIELD
	_title.text = title_text
	_message.text = message_text
	_message.visible = true
	_content_slot.visible = _bound_content != null
	_minimize_button.visible = true
	_confirm_button.visible = true
	_confirm_button.disabled = true
	_confirm_button.text = "%s (0/%d)" % [UiChromeStyle.resolve(chrome_style).get_copy().confirm, needed]
	_set_cancel_visible(false)
	_anchor_top = anchor_top
	_apply_field_layout()
	_show_bound_content(true)
	visible = true
	_play_slide_in()


## 취소 버튼 표시 토글 (외부 API).
func set_cancel_visible(on: bool) -> void:
	_set_cancel_visible(on)


## 제목 라벨 문구.
func set_title(title_text: String) -> void:
	_title.text = title_text


## 메시지 라벨 문구 (FIELD).
func set_message(message_text: String) -> void:
	_message.text = message_text


## 선택 수에 따라 확인 버튼 활성·라벨을 갱신한다.
func update_selection_count(selected: int, needed: int, min_count: int = -1) -> void:
	var min_v := needed if min_count < 0 else min_count
	_confirm_button.disabled = selected < min_v
	var confirm := UiChromeStyle.resolve(chrome_style).get_copy().confirm
	if min_v < needed:
		_confirm_button.text = "%s (%d, 최대 %d)" % [confirm, selected, needed]
	else:
		_confirm_button.text = "%s (%d/%d)" % [confirm, selected, needed]


## 시트를 슬라이드아웃 후 숨기고 바인딩 콘텐츠도 끈다.
func hide_sheet() -> void:
	_hide_content_after = true
	if _closing:
		return
	if not visible:
		_show_bound_content(false)
		_set_slide_y(0.0)
		return
	_closing = true
	_play_slide_out()


## 시트만 슬라이드아웃한다 (최소화). 콘텐츠는 복귀용으로 유지.
func minimize_sheet() -> void:
	_hide_content_after = false
	if _closing:
		return
	if not visible:
		return
	_closing = true
	_play_slide_out()


## 최소화된 시트를 슬라이드인으로 다시 연다.
func restore_sheet() -> void:
	_closing = false
	_hide_content_after = false
	if _mode == ContentMode.FIELD:
		_apply_field_layout()
	else:
		_apply_bottom_layout()
	_show_bound_content(true)
	visible = true
	_play_slide_in()


## 바인딩된 콘텐츠.
func get_content() -> Control:
	return _bound_content


## ContentSlot 노드.
func get_content_slot() -> Control:
	return _content_slot


## ContentSlot 에 콘텐츠를 넣고 맞춘다.
func set_content(content: Control) -> void:
	for child in _content_slot.get_children():
		_content_slot.remove_child(child)
		child.queue_free()
	if content.get_parent():
		content.get_parent().remove_child(content)
	_content_slot.add_child(content)
	_bound_content = content
	_fit_content(content)
	if chrome_style:
		_apply_scroll_chrome_in_slot()


## 슬롯 첫 자식을 콘텐츠로 바인딩한다.
func _prepare_mounted_content() -> void:
	if _content_slot.get_child_count() == 0:
		return
	var content := _content_slot.get_child(0) as Control
	if content == null:
		return
	_bound_content = content
	_fit_content(content)


## 콘텐츠 size_flags 를 슬롯에 맞게 설정한다.
func _fit_content(content: Control) -> void:
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL


## 바인딩 콘텐츠 visible 동기화.
func _show_bound_content(on: bool) -> void:
	if _bound_content and is_instance_valid(_bound_content):
		_bound_content.visible = on


## LIST 모드 하단 와이드 레이아웃.
func _apply_bottom_layout() -> void:
	## 런타임 높이는 상수만 사용. 에디터에서 tscn offset을 바꿔도 open_list/_ready가 여기로 덮어씀.
	var margin := UiShellConstants.BOTTOM_BAR_SIDE_MARGIN
	var height := UiShellConstants.TARGET_BAR_HEIGHT
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = margin
	offset_right = -margin
	offset_top = -height
	offset_bottom = 0


## FIELD 모드 상단 또는 하단 레이아웃.
func _apply_field_layout() -> void:
	var side := UiShellConstants.BOTTOM_BAR_SIDE_MARGIN
	var height := UiShellConstants.FIELD_PROMPT_HEIGHT
	var edge := UiShellConstants.FIELD_PROMPT_EDGE_MARGIN
	if _anchor_top:
		set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		offset_left = side
		offset_right = -side
		offset_top = edge
		offset_bottom = edge + height
	else:
		set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		offset_left = side
		offset_right = -side
		offset_top = -(height + edge)
		offset_bottom = -edge


## 취소 버튼 표시 여부.
func _set_cancel_visible(on: bool) -> void:
	if _cancel_button:
		_cancel_button.visible = on


## 상단 앵커는 위쪽, 하단은 아래쪽으로 높이만큼 숨긴다.
func _slide_off_delta() -> float:
	var h := size.y
	if h <= 1.0:
		h = (
			UiShellConstants.FIELD_PROMPT_HEIGHT
			if _mode == ContentMode.FIELD
			else UiShellConstants.TARGET_BAR_HEIGHT
		)
	return -h if _anchor_top else h


## 세로 슬라이드 delta(아래가 +)를 적용한다.
func _set_slide_y(dy: float) -> void:
	_slide.apply(self, dy)


## 진행 중 Tween을 끊는다.
func _kill_motion() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	_motion = null


## 레이아웃 rest를 잡고 오프스크린에서 제자리로 민다.
func _play_slide_in() -> void:
	_kill_motion()
	_closing = false
	_slide.capture(self, false)
	var dy := _slide_off_delta()
	if DisplayServer.get_name() == "headless":
		_set_slide_y(0.0)
		return
	_set_slide_y(dy)
	_motion = create_tween()
	_motion.tween_method(_set_slide_y, dy, 0.0, UiShellConstants.SHEET_SLIDE_IN_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)


## 오프스크린으로 민 뒤 숨긴다.
func _play_slide_out() -> void:
	_kill_motion()
	if DisplayServer.get_name() == "headless":
		_finish_hide()
		return
	var dy := _slide_off_delta()
	_motion = create_tween()
	_motion.tween_method(_set_slide_y, 0.0, dy, UiShellConstants.SHEET_SLIDE_OUT_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_IN)
	_motion.tween_callback(_finish_hide)


## 슬라이드아웃 종료: 숨김 · rest 복구 · 필요 시 콘텐츠 숨김.
func _finish_hide() -> void:
	_kill_motion()
	_closing = false
	visible = false
	if _hide_content_after:
		_show_bound_content(false)
	_set_slide_y(0.0)


## 확인 — disabled 이면 무시.
func _on_confirm_pressed() -> void:
	if _confirm_button.disabled:
		return
	selection_confirmed.emit()


## 취소 시그널.
func _on_cancel_pressed() -> void:
	selection_canceled.emit()


## 최소화 시그널.
func _on_minimize_pressed() -> void:
	minimized.emit()
