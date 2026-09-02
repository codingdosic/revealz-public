extends Control
## 싱글 준비. Player/COM 덱 셀 → deck_select(Select) → 로딩 → game.
## 기본 표시=builtin_black · 이후 last_deck_id. Deck Edit 직행 없음.
## 두 덱이 모두 playable일 때만 Play 활성.
## 룩: UiChromeStyle (단색 ScreenBg · Section 묶음).


const PREPARE_SCENE := "res://scenes/screen/single_play_prepare_screen.tscn"
const DEFAULT_DECK_ID := "builtin_black"

@export var chrome_style: UiChromeStyle

@onready var _player_cell: DeckSelectCell = $CenterContainer/VBoxContainer/HBoxContainer/PlayerDeckSection/VBox/PlayerDeckCell
@onready var _com_cell: DeckSelectCell = $CenterContainer/VBoxContainer/HBoxContainer/ComDeckSection/VBox/ComDeckCell
@onready var _status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var _play_button: Button = $CenterContainer/VBoxContainer/PlayButton

var _player_deck_id: String = DEFAULT_DECK_ID
var _com_deck_id: String = DEFAULT_DECK_ID


## 크롬 · Player/COM 셀 바인딩 · Play 게이트.
func _ready() -> void:
	_apply_ui_chrome()
	ScreenRmbBack.install(self, _on_back_button_pressed)
	_player_deck_id = _resolve_deck_id(AppSettings.KEY_LAST_DECK_SINGLE_PLAYER)
	_com_deck_id = _resolve_deck_id(AppSettings.KEY_LAST_DECK_SINGLE_COM)
	if _player_cell:
		_player_cell.cell_pressed.connect(_on_player_cell_pressed)
		_player_cell.apply_chrome(chrome_style)
	if _com_cell:
		_com_cell.cell_pressed.connect(_on_com_cell_pressed)
		_com_cell.apply_chrome(chrome_style)
	_bind_section_cell(_player_cell, _player_deck_id)
	_bind_section_cell(_com_cell, _com_deck_id)
	_refresh_play_button()


## 스택에서 다시 보일 때 last_deck을 셀에 반영한다.
func on_menu_shown() -> void:
	_player_deck_id = _resolve_deck_id(AppSettings.KEY_LAST_DECK_SINGLE_PLAYER)
	_com_deck_id = _resolve_deck_id(AppSettings.KEY_LAST_DECK_SINGLE_COM)
	_bind_section_cell(_player_cell, _player_deck_id)
	_bind_section_cell(_com_cell, _com_deck_id)
	_refresh_play_button()


## Cyan 크롬을 입힌다 (레이아웃 유지).
func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)
	if _status_label:
		chrome_style.apply_muted_label(_status_label)


## last id가 유효하면 사용, 아니면 builtin_black.
func _resolve_deck_id(settings_key: String) -> String:
	var id := AppSettings.get_last_deck_id(settings_key).strip_edges()
	if id.is_empty():
		return DEFAULT_DECK_ID
	var deck := DeckStore.load_deck(id)
	if deck.is_empty():
		return DEFAULT_DECK_ID
	return id


## 셀에 덱 이름·id를 표시한다.
func _bind_section_cell(cell: DeckSelectCell, deck_id: String) -> void:
	if cell == null:
		return
	var deck := DeckStore.load_deck(deck_id)
	var id := deck_id
	var display_name := deck_id
	if not deck.is_empty():
		id = String(deck.get("id", deck_id))
		display_name = String(deck.get("name", id))
	cell.bind(id, display_name)


## Player 셀 → deck_select (Select가 Player 슬롯에 반영).
func _on_player_cell_pressed(_cell: DeckSelectCell) -> void:
	DeckSelectScreen.open(get_tree(), PREPARE_SCENE, DeckSelectScreen.SLOT_PLAYER)


## COM 셀 → deck_select (Select가 COM 슬롯에 반영).
func _on_com_cell_pressed(_cell: DeckSelectCell) -> void:
	DeckSelectScreen.open(get_tree(), PREPARE_SCENE, DeckSelectScreen.SLOT_COM)


## Player·COM 모두 playable이면 Play 활성. 아니면 StatusLabel에 사유.
func _refresh_play_button() -> void:
	if _play_button == null:
		return
	var player_ok := DeckStore.is_playable_id(_player_deck_id)
	var com_ok := DeckStore.is_playable_id(_com_deck_id)
	_play_button.disabled = not (player_ok and com_ok)
	_update_status_label(player_ok, com_ok)


## 진입 불가 시에만 StatusLabel에 사유를 보이고, 정상이면 비운다.
func _update_status_label(player_ok: bool, com_ok: bool) -> void:
	if _status_label == null:
		return
	if player_ok and com_ok:
		_status_label.text = ""
		_status_label.visible = false
		return
	var lines: PackedStringArray = PackedStringArray()
	if not player_ok:
		lines.append("Player: %s" % DeckStore.describe_play_block_ko(_player_deck_id))
	if not com_ok:
		lines.append("COM: %s" % DeckStore.describe_play_block_ko(_com_deck_id))
	_status_label.text = "\n".join(lines)
	_status_label.visible = true


## 선택 덱 ids·등급. 실패 시 빈 배열.
func _deck_payload(deck_id: String) -> Dictionary:
	var empty := {"ids": [] as Array[int], "rarities": [] as Array[int]}
	if deck_id.is_empty() or not DeckStore.is_playable_id(deck_id):
		return empty
	var ids := DeckStore.card_ids_of(deck_id)
	if ids.is_empty():
		return empty
	return {"ids": ids, "rarities": DeckStore.card_rarities_of(deck_id)}


## 선택한 덱으로 세션을 만들고 로딩 씬을 거쳐 game으로 진입한다.
func _on_play_button_pressed() -> void:
	_refresh_play_button()
	if _play_button.disabled:
		return
	var player := _deck_payload(_player_deck_id)
	var com := _deck_payload(_com_deck_id)
	var player_ids: Array[int] = player["ids"]
	var com_ids: Array[int] = com["ids"]
	if player_ids.is_empty() or com_ids.is_empty():
		return
	var player_rarities: Array[int] = player["rarities"]
	var com_rarities: Array[int] = com["rarities"]
	GameSession.start_local_single(
		player_ids,
		com_ids,
		player_rarities,
		com_rarities,
		_player_deck_id,
		_com_deck_id
	)
	var merged_ids: Array[int] = []
	merged_ids.append_array(player_ids)
	merged_ids.append_array(com_ids)
	GameSession.begin_match_loading_ids(merged_ids)


## 메인 메뉴로 돌아간다.
func _on_back_button_pressed() -> void:
	MenuHost.pop_or_file("res://scenes/main/main.tscn")
