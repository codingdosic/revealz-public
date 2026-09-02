class_name AccessorySettingsScreen
extends Control
## 덱별 악세서리(카드 뒷면·필드·메인 카드) 선택. 탭 + 격자 · 클릭 즉시 저장.


const ACCESSORY_SCENE := "res://scenes/screen/accessory_settings_screen.tscn"
const SELECT_SCENE := "res://scenes/screen/deck_select_screen.tscn"
const CELL_SCENE := preload("res://scenes/screen/accessory_pick_cell.tscn")
const NAV_TOGGLE_SCENE := preload("res://scenes/ui/nav_toggle_button.tscn")

## 메인 카드 탭용 가상 타입 (AccessoryStore 소유 아님).
const TYPE_MAIN_CARD := "main_card"
const TAB_LABELS: Array[String] = ["card back", "field", "main card"]
const TAB_MAIN_CARD := 2

static var pending_deck_id: String = ""
static var pending_return_scene: String = SELECT_SCENE

@export var chrome_style: UiChromeStyle

@onready var _title_label: Label = $Margin/VBox/DecktitleSection/TitleLabel
@onready var _tab_bar: VBoxContainer = $Margin/VBox/HBoxContainer/TabSection/TabBar
@onready var _grid: GridContainer = $Margin/VBox/HBoxContainer/GridSection/GridArea/GridScroll/ItemGrid
@onready var _empty_label: Label = $Margin/VBox/HBoxContainer/GridSection/GridArea/EmptyLabel
@onready var _status_label: Label = $Margin/VBox/StatusLabel

var _deck_id: String = ""
var _return_scene: String = SELECT_SCENE
var _tab_index: int = 0
var _accessories: Dictionary = {}
var _tab_button_group: ButtonGroup = ButtonGroup.new()


static func open(tree: SceneTree, deck_id: String, return_scene: String = SELECT_SCENE) -> void:
	if tree == null:
		return
	pending_deck_id = deck_id.strip_edges()
	pending_return_scene = return_scene
	MenuHost.push_file(ACCESSORY_SCENE)


func _ready() -> void:
	_deck_id = pending_deck_id
	_return_scene = pending_return_scene
	pending_deck_id = ""
	pending_return_scene = SELECT_SCENE
	AccessoryStore.ensure_loaded()
	_accessories = DeckStore.accessories_of(_deck_id)
	_apply_ui_chrome()
	_refresh_title()
	_rebuild_tabs()
	_select_tab(0)
	ScreenRmbBack.install(self, _on_back_button_pressed)
	if _status_label:
		_status_label.text = ""


func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)
	if _title_label:
		chrome_style.apply_title_label(_title_label)


func _refresh_title() -> void:
	if _title_label == null:
		return
	var deck := DeckStore.load_deck(_deck_id)
	var name := String(deck.get("name", _deck_id))
	_title_label.text = "Accessory — %s" % name


func _rebuild_tabs() -> void:
	if _tab_bar == null:
		return
	_clear_children(_tab_bar)
	for i in TAB_LABELS.size():
		var btn := NAV_TOGGLE_SCENE.instantiate() as NavToggleButton
		btn.configure(TAB_LABELS[i], _tab_button_group, false)
		btn.apply_chrome(chrome_style)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		_tab_bar.add_child(btn)


func _select_tab(index: int) -> void:
	_tab_index = clampi(index, 0, maxi(0, TAB_LABELS.size() - 1))
	for i in _tab_bar.get_child_count():
		var btn := _tab_bar.get_child(i) as Button
		if btn:
			btn.set_pressed_no_signal(i == _tab_index)
	_rebuild_grid()


func _is_main_card_tab() -> bool:
	return _tab_index == TAB_MAIN_CARD


func _current_type() -> String:
	if _is_main_card_tab():
		return TYPE_MAIN_CARD
	if _tab_index < 0 or _tab_index >= DeckStore.DECK_ACCESSORY_TYPES.size():
		return AccessoryTypes.TYPE_CARD_BACK
	return DeckStore.DECK_ACCESSORY_TYPES[_tab_index]


func _selected_id_for_current_type() -> String:
	if _is_main_card_tab():
		var resolved := DeckStore.main_card_of(_deck_id)
		return String(resolved.get("key", ""))
	return String(_accessories.get(_current_type(), "")).strip_edges()


func _rebuild_grid() -> void:
	if _grid == null:
		return
	_clear_children(_grid)
	if _is_main_card_tab():
		_rebuild_main_card_grid()
		return
	var accessory_type := _current_type()
	var selected_id := _selected_id_for_current_type()
	var owned_ids := AccessoryStore.list_owned_ids(accessory_type)
	var has_any := false
	for id in owned_ids:
		var display := AccessoryCatalog.display_name_for_id(id)
		var preview := AccessoryCatalog.preview_for_id(id)
		var cell := CELL_SCENE.instantiate() as AccessoryPickCell
		if cell == null:
			continue
		cell.configure_for_type(accessory_type)
		cell.bind(id, display, preview)
		cell.apply_chrome(chrome_style)
		cell.set_selected(id == selected_id)
		cell.accessory_pressed.connect(_on_cell_pressed)
		_grid.add_child(cell)
		has_any = true
	_set_grid_empty(not has_any)


func _rebuild_main_card_grid() -> void:
	var selected_key := _selected_id_for_current_type()
	var options := DeckStore.list_unique_main_card_options(_deck_id)
	var has_any := false
	for entry in options:
		var key := String(entry.get("key", ""))
		var display := String(entry.get("name", key))
		var card_id := int(entry.get("card_id", 0))
		var rarity := int(entry.get("rarity", CardRarity.Tier.N))
		var data := CardRegistry.get_by_id(card_id)
		var preview: Texture2D = data.illustration if data != null else null
		var cell := CELL_SCENE.instantiate() as AccessoryPickCell
		if cell == null:
			continue
		cell.configure_for_type(TYPE_MAIN_CARD)
		cell.bind(key, display, preview, rarity)
		cell.apply_chrome(chrome_style)
		cell.set_selected(key == selected_key)
		cell.accessory_pressed.connect(_on_cell_pressed)
		_grid.add_child(cell)
		has_any = true
	_set_grid_empty(not has_any)


func _set_grid_empty(empty: bool) -> void:
	if _empty_label:
		_empty_label.visible = empty
	if _grid:
		_grid.visible = not empty


func _on_cell_pressed(accessory_id: String) -> void:
	var id := accessory_id.strip_edges()
	if id.is_empty() or _deck_id.is_empty():
		return
	if _is_main_card_tab():
		_on_main_card_pressed(id)
		return
	var accessory_type := _current_type()
	var next := _accessories.duplicate(true)
	next[accessory_type] = id
	var result := DeckStore.save_deck_accessories(_deck_id, next)
	if not bool(result.get("ok", false)):
		if _status_label:
			_status_label.text = String(result.get("error", "Save failed"))
		return
	_accessories = DeckStore.accessories_of(_deck_id)
	if _status_label:
		_status_label.text = ""
	_rebuild_grid()


func _on_main_card_pressed(key: String) -> void:
	var parsed := DeckStore.parse_main_card_key(key)
	if parsed.is_empty():
		return
	var result := DeckStore.save_deck_main_card(
		_deck_id,
		int(parsed["card_id"]),
		int(parsed["rarity"])
	)
	if not bool(result.get("ok", false)):
		if _status_label:
			_status_label.text = String(result.get("error", "Save failed"))
		return
	if _status_label:
		_status_label.text = ""
	_rebuild_grid()


func _on_tab_pressed(index: int) -> void:
	_select_tab(index)


func _on_back_button_pressed() -> void:
	MenuHost.pop_or_file(_return_scene)


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
