class_name DeckSelectScreen
extends Control
## 덱 선택 화면. 그리드 + 우측 옵션(Select/Edit/Delete/Accessory).
## main: 유저 덱만 · Select 숨김. prepare(single/online): builtin+유저 · Select 표시(슬롯별).
## builtin 선택 시 Edit/Delete 비활성. Delete는 PopupShell 확인.
## + / Edit → editor 후 복귀 시 open 컨텍스트(return·slot) 유지.


const MAIN_SCENE := "res://scenes/main/main.tscn"
const SELECT_SCENE := "res://scenes/screen/deck_select_screen.tscn"
const CELL_SCENE := preload("res://scenes/screen/deck_select_cell.tscn")
const POPUP_SHELL_SCENE := preload("res://scenes/ui/shell/popup_shell.tscn")

const SLOT_NONE := ""
const SLOT_PLAYER := "player"
const SLOT_COM := "com"
const SLOT_ONLINE := "online"

## change_scene 전 복귀 경로 · prepare 슬롯(player/com/online). 비면 main 모드.
static var pending_return_scene: String = MAIN_SCENE
static var pending_select_slot: String = SLOT_NONE

@export var chrome_style: UiChromeStyle

@onready var _deck_grid: GridContainer = $Margin/Body/GridSection/MarginContainer/GridScroll/DeckGrid
@onready var _add_cell: DeckSelectCell = $Margin/Body/GridSection/MarginContainer/GridScroll/DeckGrid/AddCell
@onready var _options_vbox: VBoxContainer = $Margin/Body/OptionsSection/OptionsMargin/OptionsVBox
@onready var _select_button: Button = $Margin/Body/OptionsSection/OptionsMargin/OptionsVBox/SelectButton
@onready var _edit_button: Button = $Margin/Body/OptionsSection/OptionsMargin/OptionsVBox/EditButton
@onready var _accessory_button: Button = $Margin/Body/OptionsSection/OptionsMargin/OptionsVBox/AccessoryButton
@onready var _delete_button: Button = $Margin/Body/OptionsSection/OptionsMargin/OptionsVBox/DeleteButton

var _return_scene: String = MAIN_SCENE
var _select_slot: String = SLOT_NONE
var _include_builtins: bool = false
var _selected_id: String = ""
var _selected_name: String = ""
var _selected_cell: DeckSelectCell = null
var _preview_cell: DeckSelectCell = null
var _delete_popup: PopupShell


## 선택 화면을 연다. select_slot이 player/com/online이면 prepare 모드(Select·builtin).
static func open(tree: SceneTree, return_scene: String = MAIN_SCENE, select_slot: String = SLOT_NONE) -> void:
	if tree == null:
		return
	pending_return_scene = return_scene
	pending_select_slot = select_slot
	MenuHost.push_file(SELECT_SCENE)


## 에디터 왕복 후에도 동일 return/slot을 쓰도록 pending을 다시 심는다.
func _stash_open_context() -> void:
	pending_return_scene = _return_scene
	pending_select_slot = _select_slot


## 크롬 · 팝업 · 그리드 · 옵션 연결.
func _ready() -> void:
	_return_scene = pending_return_scene
	_select_slot = pending_select_slot
	pending_return_scene = MAIN_SCENE
	pending_select_slot = SLOT_NONE
	_include_builtins = not _select_slot.is_empty()
	_apply_ui_chrome()
	ScreenRmbBack.install(self, _on_back_button_pressed)
	_delete_popup = POPUP_SHELL_SCENE.instantiate() as PopupShell
	add_child(_delete_popup)
	if _delete_popup.has_method("apply_chrome"):
		_delete_popup.call("apply_chrome", chrome_style)
	if _select_button and not _select_button.pressed.is_connected(_on_select_button_pressed):
		_select_button.pressed.connect(_on_select_button_pressed)
	if _edit_button and not _edit_button.pressed.is_connected(_on_edit_button_pressed):
		_edit_button.pressed.connect(_on_edit_button_pressed)
	if _delete_button and not _delete_button.pressed.is_connected(_on_delete_button_pressed):
		_delete_button.pressed.connect(_on_delete_button_pressed)
	if _accessory_button and not _accessory_button.pressed.is_connected(_on_accessory_button_pressed):
		_accessory_button.pressed.connect(_on_accessory_button_pressed)
	_rebuild_grid()
	_clear_selection()


## Cyan 크롬을 입힌다 (레이아웃 유지).
func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)


## AddCell(+) 유지 · builtin 포함 여부에 따라 목록 채움.
func _rebuild_grid() -> void:
	if _deck_grid == null:
		return
	var stale: Array[Node] = []
	for child in _deck_grid.get_children():
		if child != _add_cell:
			stale.append(child)
	for child in stale:
		_deck_grid.remove_child(child)
		child.free()
	if _add_cell:
		_add_cell.configure_as_add()
		if not _add_cell.cell_pressed.is_connected(_on_cell_pressed):
			_add_cell.cell_pressed.connect(_on_cell_pressed)
		_add_cell.apply_chrome(chrome_style)
		_add_cell.set_highlighted(false)
	var decks: Array[Dictionary] = (
		DeckStore.list_selectable_decks() if _include_builtins else DeckStore.list_user_decks()
	)
	for deck in decks:
		var cell := CELL_SCENE.instantiate() as DeckSelectCell
		if cell == null:
			continue
		_deck_grid.add_child(cell)
		var id := String(deck.get("id", ""))
		var display_name := String(deck.get("name", id))
		cell.bind(id, display_name)
		cell.apply_chrome(chrome_style)
		cell.cell_pressed.connect(_on_cell_pressed)


## 스택에서 다시 보일 때 그리드를 갱신하고 이전 선택을 복구한다.
func on_menu_shown() -> void:
	var keep_id := _selected_id
	_rebuild_grid()
	_clear_selection()
	if keep_id.is_empty() or _deck_grid == null:
		return
	for child in _deck_grid.get_children():
		var cell := child as DeckSelectCell
		if cell == null or cell.is_add_cell():
			continue
		if cell.get_deck_id() == keep_id:
			_on_cell_pressed(cell)
			return


## 하이라이트·선택 id를 지우고 우측 옵션을 숨긴다.
func _clear_selection() -> void:
	if _selected_cell and is_instance_valid(_selected_cell):
		_selected_cell.set_highlighted(false)
	_selected_cell = null
	_selected_id = ""
	_selected_name = ""
	if _preview_cell and is_instance_valid(_preview_cell):
		_preview_cell.visible = false
	if _options_vbox:
		_options_vbox.visible = false


## 셀 하이라이트 후 우측 옵션. +면 빈 에디터(컨텍스트 유지).
func _on_cell_pressed(cell: DeckSelectCell) -> void:
	if cell == null:
		return
	if cell.is_add_cell():
		_stash_open_context()
		DeckEditorScreen.open_new(get_tree(), SELECT_SCENE)
		return
	if _selected_cell and is_instance_valid(_selected_cell) and _selected_cell != cell:
		_selected_cell.set_highlighted(false)
	_selected_cell = cell
	_selected_id = cell.get_deck_id()
	_selected_name = cell.get_display_name()
	cell.set_highlighted(true)
	_show_options_for_selection()


## 옵션 패널 맨 위 미리보기 셀을 보장한다 (클릭 비활성).
func _ensure_preview_cell() -> void:
	if _preview_cell != null and is_instance_valid(_preview_cell):
		return
	if _options_vbox == null:
		return
	_preview_cell = CELL_SCENE.instantiate() as DeckSelectCell
	if _preview_cell == null:
		return
	_preview_cell.disabled = true
	_preview_cell.focus_mode = Control.FOCUS_NONE
	_preview_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_options_vbox.add_child(_preview_cell)
	_options_vbox.move_child(_preview_cell, 0)


## 선택 덱을 옵션 패널 상단 셀로 반영한다.
func _refresh_preview_cell() -> void:
	_ensure_preview_cell()
	if _preview_cell == null:
		return
	_preview_cell.bind(_selected_id, _selected_name)
	_preview_cell.apply_chrome(chrome_style)
	_preview_cell.set_highlighted(false)
	_preview_cell.visible = not _selected_id.is_empty()


## 선택 덱 옵션 표시. prepare만 Select. builtin이면 Edit/Delete 비활성.
func _show_options_for_selection() -> void:
	if _options_vbox == null:
		return
	_options_vbox.visible = true
	_refresh_preview_cell()
	var builtin := DeckStore.is_builtin_id(_selected_id)
	if _select_button:
		_select_button.visible = _include_builtins
		_select_button.disabled = _selected_id.is_empty()
	if _accessory_button:
		_accessory_button.visible = true
		_accessory_button.disabled = false
	if _edit_button:
		_edit_button.visible = true
		_edit_button.disabled = builtin
	if _delete_button:
		# prepare(Select 모드)에서는 삭제 숨김 · main에서만 표시.
		_delete_button.visible = not _include_builtins
		_delete_button.disabled = builtin


## prepare 슬롯에 덱을 확정하고 복귀 화면으로 돌아간다.
func _on_select_button_pressed() -> void:
	if _selected_id.is_empty() or _select_slot.is_empty():
		return
	DeckStore.touch_deck(_selected_id)
	match _select_slot:
		SLOT_PLAYER:
			AppSettings.save_last_deck_id(AppSettings.KEY_LAST_DECK_SINGLE_PLAYER, _selected_id)
		SLOT_COM:
			AppSettings.save_last_deck_id(AppSettings.KEY_LAST_DECK_SINGLE_COM, _selected_id)
		SLOT_ONLINE:
			AppSettings.save_last_deck_id(AppSettings.KEY_LAST_DECK_ONLINE, _selected_id)
		_:
			pass
	MenuHost.pop_or_file(_return_scene)


## 선택 덱을 에디터로 연다. builtin이면 무시.
func _on_edit_button_pressed() -> void:
	if _selected_id.is_empty() or DeckStore.is_builtin_id(_selected_id):
		return
	DeckStore.touch_deck(_selected_id)
	_stash_open_context()
	DeckEditorScreen.open(get_tree(), SELECT_SCENE, _selected_id)


## 선택 덱의 악세서리(뒷면·필드) 설정 화면으로 이동한다.
func _on_accessory_button_pressed() -> void:
	if _selected_id.is_empty():
		return
	_stash_open_context()
	AccessorySettingsScreen.open(get_tree(), _selected_id, SELECT_SCENE)


## 삭제 확인 팝업을 연다. builtin이면 무시.
func _on_delete_button_pressed() -> void:
	if _selected_id.is_empty() or DeckStore.is_builtin_id(_selected_id):
		return
	if _delete_popup == null:
		_confirm_delete_deck()
		return
	var copy := chrome_style.get_copy()
	_delete_popup.configure_confirm(
		"Delete deck",
		"\"%s\"을(를) 삭제할까요?" % _selected_name,
		_confirm_delete_deck,
		Callable(),
		"",
		copy.cancel if copy else "",
		{"full_dimmer": true}
	)
	_delete_popup.open()


## 확인 후 유저 덱을 삭제하고 그리드를 갱신한다.
func _confirm_delete_deck() -> void:
	if _selected_id.is_empty() or DeckStore.is_builtin_id(_selected_id):
		return
	if not DeckStore.delete_deck(_selected_id):
		return
	_clear_selection()
	_rebuild_grid()


## 진입 시 지정한 화면으로 돌아간다 (선택 변경 없음).
func _on_back_button_pressed() -> void:
	MenuHost.pop_or_file(_return_scene)
