extends Control
## 대상 카드 선택 리스트 콘텐츠 (하단 바텀시트 ContentSlot용).
## 크롬(제목·확인·최소화)은 부모 BottomSheetShell.
##
## 튜닝:
## - 드래그 스크롤 임계: DRAG_THRESHOLD_PX
## - 셀 씬: CELL_SCENE
## - 셸 여백·높이: UiShellConstants.BOTTOM_BAR_* / TARGET_BAR_HEIGHT

signal card_pressed(card: Node)
signal selection_confirmed
signal selection_canceled
signal minimized

const CELL_SCENE := preload("res://scenes/ui/graveyard_card_cell.tscn")
## 이 픽셀 이상 움직이면 클릭(선택) 대신 가로 스크롤.
const DRAG_THRESHOLD_PX := 8.0

@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _row: HBoxContainer = $ScrollContainer/CardRow
@onready var _empty_label: Label = $EmptyLabel

var _cells: Array = []
var _game_ui: Node
var _drag_scroll_origin: int = 0
var _scroll_pressing: bool = false
var _scroll_dragging: bool = false
var _scroll_press_x: float = 0.0
var _shell_wired: bool = false


## 부트: 스크롤 입력 · 카드행 중앙 정렬 · 부모 셸 시그널.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.gui_input.connect(_on_scroll_gui_input)
	visible = false
	if _row:
		_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wire_parent_shell()


func bind_game_ui(game_ui: Node) -> void:
	_game_ui = game_ui


func show_selection(
	title_text: String,
	display_cards: Array,
	selectable_cards: Array,
	needed: int,
	show_cancel: bool = false
) -> void:
	_wire_parent_shell()
	var shell := _find_bottom_sheet()
	_populate(display_cards, selectable_cards)
	visible = true
	if shell:
		shell.call("open_list", title_text, show_cancel)
		shell.call("update_selection_count", 0, needed)
	else:
		push_warning("TargetSelectBar: BottomSheetShell parent missing")


func hide_bar() -> void:
	var shell := _find_bottom_sheet()
	if shell:
		shell.call("hide_sheet")
	else:
		visible = false
		_clear_cells()


func minimize_bar() -> void:
	var shell := _find_bottom_sheet()
	if shell:
		shell.call("minimize_sheet")
	else:
		visible = false


func restore_bar() -> void:
	var shell := _find_bottom_sheet()
	if shell:
		shell.call("restore_sheet")
	visible = true


func update_selection_count(selected: int, needed: int, min_count: int = -1) -> void:
	var shell := _find_bottom_sheet()
	if shell:
		shell.call("update_selection_count", selected, needed, min_count)


func set_selected_cards(cards: Array) -> void:
	for cell in _cells:
		if not is_instance_valid(cell):
			continue
		if not cell.has_method("set_selected"):
			continue
		var cell_card: Node = cell.get_card() if cell.has_method("get_card") else null
		var is_on := false
		for card in cards:
			if card == cell_card:
				is_on = true
				break
		cell.set_selected(is_on)


## 가시성은 셸 기준 (콘텐츠만 visible 이면 안 됨).
func is_sheet_visible() -> bool:
	var shell := _find_bottom_sheet()
	if shell:
		return shell.visible
	return visible


func get_sheet() -> Control:
	return _find_bottom_sheet()


func _populate(display_cards: Array, selectable_cards: Array) -> void:
	_clear_cells()
	var valid: Array = []
	for card in display_cards:
		if is_instance_valid(card):
			valid.append(card)
	_empty_label.visible = valid.is_empty()
	_scroll.visible = not valid.is_empty()
	if valid.is_empty():
		return
	for card in valid:
		var cell: PanelContainer = CELL_SCENE.instantiate()
		_row.add_child(cell)
		var can_select := _card_in_list(card, selectable_cards)
		var sheet := _find_bottom_sheet()
		if sheet != null and sheet.get("chrome_style") != null:
			cell.set("chrome_style", sheet.get("chrome_style"))
		else:
			cell.set("chrome_style", UiChromeStyle.load_default())
		cell.setup(card, can_select, true, false, true)
		_cells.append(cell)
		cell.drag_moved.connect(_on_cell_drag_moved)
		cell.gui_input.connect(_on_cell_press_capture)
		if can_select:
			cell.card_pressed.connect(_on_cell_pressed)
		else:
			cell.card_pressed.connect(_on_non_selectable_pressed)


func _card_in_list(card: Node, cards: Array) -> bool:
	for candidate in cards:
		if candidate == card:
			return true
		if (
			is_instance_valid(candidate)
			and is_instance_valid(card)
			and candidate.get("instance_id") != null
			and card.get("instance_id") != null
			and candidate.instance_id == card.instance_id
		):
			return true
	return false


func _clear_cells() -> void:
	for cell in _cells:
		if is_instance_valid(cell):
			cell.queue_free()
	_cells.clear()


func _on_cell_press_capture(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_drag_scroll_origin = _scroll.scroll_horizontal


func _on_cell_drag_moved(total_dx: float) -> void:
	_scroll.scroll_horizontal = _drag_scroll_origin - int(total_dx)


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_scroll_pressing = true
			_scroll_dragging = false
			_scroll_press_x = event.global_position.x
			_drag_scroll_origin = _scroll.scroll_horizontal
		else:
			_scroll_pressing = false
			_scroll_dragging = false
		return
	if event is InputEventMouseMotion and _scroll_pressing:
		var total_dx: float = event.global_position.x - _scroll_press_x
		if not _scroll_dragging and absf(total_dx) >= DRAG_THRESHOLD_PX:
			_scroll_dragging = true
		if _scroll_dragging:
			_scroll.scroll_horizontal = _drag_scroll_origin - int(total_dx)
			accept_event()


func _on_cell_pressed(card: Node) -> void:
	card_pressed.emit(card)


func _on_non_selectable_pressed(card: Node) -> void:
	if _game_ui and _game_ui.has_method("show_card_info") and CardInfoRules.is_sidebar_eligible(card):
		_game_ui.show_card_info(card)


func _wire_parent_shell() -> void:
	if _shell_wired:
		return
	var shell := _find_bottom_sheet()
	if shell == null:
		return
	if shell.has_signal("selection_confirmed") and not shell.is_connected("selection_confirmed", _on_shell_confirmed):
		shell.connect("selection_confirmed", _on_shell_confirmed)
	if shell.has_signal("selection_canceled") and not shell.is_connected("selection_canceled", _on_shell_canceled):
		shell.connect("selection_canceled", _on_shell_canceled)
	if shell.has_signal("minimized") and not shell.is_connected("minimized", _on_shell_minimized):
		shell.connect("minimized", _on_shell_minimized)
	_shell_wired = true


func _on_shell_confirmed() -> void:
	selection_confirmed.emit()


func _on_shell_canceled() -> void:
	selection_canceled.emit()


func _on_shell_minimized() -> void:
	minimized.emit()


## Control 반환 — export 에서 `as BottomSheetShell` 캐스트가 null 이 되는 경우 방지.
func _find_bottom_sheet() -> Control:
	var n: Node = get_parent()
	while n:
		if n is Control and n.has_method("open_list") and n.has_method("hide_sheet"):
			return n as Control
		n = n.get_parent()
	return null
