extends PanelContainer

signal card_selected(card: Node)
signal close_requested
signal selection_confirmed
signal minimized

const CELL_SCENE := preload("res://scenes/ui/graveyard_card_cell.tscn")

@onready var _title: Label = $Margin/VBox/TitleRow/TitleLabel
@onready var _title_row: HBoxContainer = $Margin/VBox/TitleRow
@onready var _minimize_button: Button = $Margin/VBox/TitleRow/MinimizeButton
@onready var _grid: GridContainer = $Margin/VBox/ScrollContainer/GridContainer
@onready var _close_button: Button = $Margin/VBox/CloseButton
@onready var _empty_label: Label = $Margin/VBox/EmptyLabel

var _selection_mode: bool = false
var _selection_needed: int = 0
var _cells: Array = []
var _game_ui: Node


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_minimize_button.pressed.connect(_on_minimize_pressed)
	visible = false


func bind_game_ui(game_ui: Node) -> void:
	_game_ui = game_ui


func show_view(title_text: String, cards: Array) -> void:
	_selection_mode = false
	_selection_needed = 0
	_title.text = title_text
	_minimize_button.visible = false
	_close_button.text = UiCopy.load_default().close
	_close_button.visible = true
	_close_button.disabled = false
	_populate(cards, false)
	visible = true


func show_selection(
	title_text: String,
	display_cards: Array,
	selectable_cards: Array = [],
	needed: int = 1
) -> void:
	_selection_mode = true
	_selection_needed = needed
	_title.text = title_text
	_minimize_button.visible = true
	_close_button.text = UiCopy.load_default().confirm
	_close_button.visible = true
	_close_button.disabled = true
	if selectable_cards.is_empty():
		selectable_cards = display_cards
	_populate_selection(display_cards, selectable_cards)
	visible = true


func hide_panel() -> void:
	visible = false
	_selection_mode = false
	_selection_needed = 0
	_clear_cells()
	if _game_ui and _game_ui.has_method("hide_card_sidebar"):
		_game_ui.hide_card_sidebar()


func minimize_panel() -> void:
	visible = false


func restore_panel() -> void:
	visible = true


func is_selection_mode() -> bool:
	return _selection_mode


func update_selection_count(selected: int, needed: int) -> void:
	if not _selection_mode:
		return
	_close_button.disabled = selected < needed


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


func get_cells() -> Array:
	return _cells


func _populate_selection(display_cards: Array, selectable_cards: Array) -> void:
	_clear_cells()
	var valid: Array = []
	for card in display_cards:
		if is_instance_valid(card):
			valid.append(card)
	_empty_label.visible = valid.is_empty()
	_grid.visible = not valid.is_empty()
	if valid.is_empty():
		return
	for card in valid:
		var cell: PanelContainer = CELL_SCENE.instantiate()
		_grid.add_child(cell)
		var can_select := _card_in_list(card, selectable_cards)
		cell.set("chrome_style", UiChromeStyle.load_default())
		cell.setup(card, can_select)
		_cells.append(cell)
		if can_select:
			cell.card_pressed.connect(_on_card_pressed)
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


func _on_non_selectable_pressed(card: Node) -> void:
	if _game_ui and _game_ui.has_method("show_card_info") and CardInfoRules.is_sidebar_eligible(card):
		_game_ui.show_card_info(card)


func _populate(cards: Array, selectable: bool) -> void:
	_clear_cells()
	var valid: Array = []
	for card in cards:
		if is_instance_valid(card):
			valid.append(card)
	_empty_label.visible = valid.is_empty()
	_grid.visible = not valid.is_empty()
	if valid.is_empty():
		return
	for card in valid:
		var cell: PanelContainer = CELL_SCENE.instantiate()
		_grid.add_child(cell)
		cell.set("chrome_style", UiChromeStyle.load_default())
		cell.setup(card, selectable)
		_cells.append(cell)
		if selectable:
			cell.card_pressed.connect(_on_card_pressed)
		else:
			cell.card_pressed.connect(_on_card_view_clicked)


func _clear_cells() -> void:
	for cell in _cells:
		if is_instance_valid(cell):
			cell.queue_free()
	_cells.clear()


func _on_card_pressed(card: Node) -> void:
	card_selected.emit(card)


func _on_card_view_clicked(card: Node) -> void:
	if _game_ui and _game_ui.has_method("toggle_card_info"):
		_game_ui.toggle_card_info(card)


func _on_close_pressed() -> void:
	if _selection_mode:
		if _close_button.disabled:
			return
		selection_confirmed.emit()
		return
	close_requested.emit()
	hide_panel()


func _on_minimize_pressed() -> void:
	if not _selection_mode:
		return
	minimized.emit()
