class_name PlayerProfileScreen
extends Control
## 플레이어 정보 — account key(읽기) · 표시명 · 보유 아이콘 선택.


signal close_requested

const PROFILE_SCENE := "res://scenes/screen/player_profile_screen.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"
const CELL_SCENE := preload("res://scenes/screen/accessory_pick_cell.tscn")
const FALLBACK_ICON := preload("res://assets_lite/accessories/icon/icon_default.png")

static var pending_return_scene: String = MAIN_SCENE

@export var chrome_style: UiChromeStyle

@onready var _title_label: Label = $Margin/VBox/MarginContainer2/TitleSection/TitleLabel
@onready var _account_key_field: TextEdit = $Margin/VBox/MarginContainer/AccountSection/AccountVBox/AccountKeyField
@onready var _name_edit: LineEdit = $Margin/VBox/MarginContainer3/NameSection/NameRow/NameEdit
@onready var _icon_grid: GridContainer = $Margin/VBox/MarginContainer4/IconSection/GridArea/GridScroll/ItemGrid
@onready var _empty_label: Label = $Margin/VBox/MarginContainer4/IconSection/GridArea/EmptyLabel
@onready var _status_label: Label = $Margin/VBox/StatusLabel

var _return_scene: String = MAIN_SCENE
var _embedded: bool = false
var _suppress_name_commit: bool = false


static func open(tree: SceneTree, return_scene: String = MAIN_SCENE) -> void:
	if tree == null:
		return
	pending_return_scene = return_scene
	MenuHost.push_file(PROFILE_SCENE)


func _ready() -> void:
	_return_scene = pending_return_scene
	pending_return_scene = MAIN_SCENE
	AccessoryStore.ensure_loaded()
	_suppress_name_commit = true
	_populate_fields()
	_apply_ui_chrome()
	_rebuild_icon_grid()
	_suppress_name_commit = false
	ScreenRmbBack.install(self, _on_back_button_pressed)
	if _status_label:
		_status_label.text = ""


func set_embedded(embedded: bool) -> void:
	_embedded = embedded


## 임베드 오버레이를 다시 열 때 필드·격자를 최신 Account 상태로 갱신.
func refresh_from_account() -> void:
	_suppress_name_commit = true
	_populate_fields()
	_rebuild_icon_grid()
	_suppress_name_commit = false


func _populate_fields() -> void:
	if AccountService.is_bootstrapped():
		if _account_key_field:
			_account_key_field.text = AccountService.current_id()
		if _name_edit:
			_name_edit.text = AccountService.display_name()
			_name_edit.editable = true
	else:
		if _account_key_field:
			_account_key_field.text = "—"
		if _name_edit:
			_name_edit.text = ""
			_name_edit.editable = false


func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self, not _embedded)
	if _title_label:
		chrome_style.apply_title_label(_title_label)


func _rebuild_icon_grid() -> void:
	if _icon_grid == null:
		return
	_clear_children(_icon_grid)
	var selected := AccountService.profile_icon_id()
	var owned := AccessoryStore.list_owned_ids(AccessoryTypes.TYPE_ICON)
	var has_any := false
	for id in owned:
		var display := AccessoryCatalog.display_name_for_id(id)
		var preview := AccessoryCatalog.preview_for_id(id)
		if preview == null:
			preview = FALLBACK_ICON
		var cell := CELL_SCENE.instantiate() as AccessoryPickCell
		if cell == null:
			continue
		cell.bind(id, display, preview)
		cell.configure_for_type(AccessoryTypes.TYPE_ICON)
		cell.apply_chrome(chrome_style)
		cell.set_selected(id == selected)
		cell.accessory_pressed.connect(_on_icon_pressed)
		_icon_grid.add_child(cell)
		has_any = true
	if _empty_label:
		_empty_label.visible = not has_any
	_icon_grid.visible = has_any


func _on_icon_pressed(icon_id: String) -> void:
	var id := icon_id.strip_edges()
	if id.is_empty():
		return
	var err := AccountService.set_profile_icon_id(id)
	if not err.is_empty():
		if _status_label:
			_status_label.text = err
		return
	if _status_label:
		_status_label.text = ""
	_rebuild_icon_grid()


func _commit_display_name() -> void:
	if _suppress_name_commit or _name_edit == null or not _name_edit.editable:
		return
	var err := AccountService.set_display_name(_name_edit.text)
	if not err.is_empty():
		if _status_label:
			_status_label.text = err
		return
	_name_edit.text = AccountService.display_name()
	if _status_label:
		_status_label.text = ""


func _on_name_text_submitted(_text: String) -> void:
	_commit_display_name()


func _on_name_focus_exited() -> void:
	_commit_display_name()


func _on_back_button_pressed() -> void:
	_commit_display_name()
	if _embedded:
		close_requested.emit()
		return
	MenuHost.pop_or_file(_return_scene)


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
