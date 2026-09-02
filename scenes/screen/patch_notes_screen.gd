extends Control
## 패치노트 화면. 좌측 목록 · 중앙 제목/날짜/본문(마크다운→BBCode).
## 룩: UiChromeStyle.


const MAIN_SCENE := "res://scenes/main/main.tscn"

@export var chrome_style: UiChromeStyle

@onready var _back_button: Button = $BackButton
@onready var _list: ItemList = $Margin/HBox/ListSection/VBox/NoteList
@onready var _empty_label: Label = $Margin/HBox/ListSection/VBox/EmptyLabel
@onready var _title_label: Label = $Margin/HBox/DetailSection/VBox/TitleLabel
@onready var _date_label: Label = $Margin/HBox/DetailSection/VBox/DateLabel
@onready var _body: RichTextLabel = $Margin/HBox/DetailSection/VBox/BodyScroll/BodyLabel
@onready var _status_label: Label = $Margin/HBox/DetailSection/VBox/StatusLabel

var _http: HTTPRequest
var _notes: Array = []


func _ready() -> void:
	_apply_ui_chrome()
	ScreenRmbBack.install(self, _on_back_button_pressed)
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	if _list and not _list.item_selected.is_connected(_on_note_selected):
		_list.item_selected.connect(_on_note_selected)
	_clear_detail("목록을 불러오는 중…")
	await _load_list()


func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)


func _on_back_button_pressed() -> void:
	MenuHost.pop_or_file(MAIN_SCENE)


func _clear_detail(status: String = "") -> void:
	if _title_label:
		_title_label.text = ""
	if _date_label:
		_date_label.text = ""
	if _body:
		_body.text = ""
	if _status_label:
		_status_label.text = status


func _load_list() -> void:
	var res: Dictionary = await MetaRemote.get_patch_notes(_http)
	if not bool(res.get("ok", false)):
		_notes = []
		if _list:
			_list.clear()
		if _empty_label:
			_empty_label.visible = true
			_empty_label.text = "패치노트를 불러오지 못했습니다"
		_clear_detail(String(res.get("error", "load_failed")))
		return
	var data: Dictionary = {}
	if typeof(res.get("data", {})) == TYPE_DICTIONARY:
		data = res.get("data", {}) as Dictionary
	_notes = data.get("notes", []) as Array
	if _list:
		_list.clear()
		for note in _notes:
			if typeof(note) != TYPE_DICTIONARY:
				continue
			var title := String(note.get("title", ""))
			var at := String(note.get("publishedAt", "")).replace("T", " ").substr(0, 16)
			_list.add_item("%s\n%s" % [title, at] if not at.is_empty() else title)
	var empty := _notes.is_empty()
	if _empty_label:
		_empty_label.visible = empty
		_empty_label.text = "등록된 패치노트가 없습니다"
	if empty:
		_clear_detail("")
		return
	_list.select(0)
	_on_note_selected(0)


func _on_note_selected(index: int) -> void:
	if index < 0 or index >= _notes.size():
		return
	var summary: Dictionary = _notes[index] as Dictionary
	if typeof(_notes[index]) != TYPE_DICTIONARY:
		return
	var note_id := int(summary.get("id", 0))
	if note_id <= 0:
		return
	_clear_detail("본문 불러오는 중…")
	var res: Dictionary = await MetaRemote.get_patch_note(_http, note_id)
	if not bool(res.get("ok", false)):
		_clear_detail(String(res.get("error", "load_failed")))
		return
	var data: Dictionary = {}
	if typeof(res.get("data", {})) == TYPE_DICTIONARY:
		data = res.get("data", {}) as Dictionary
	var note: Dictionary = {}
	if typeof(data.get("note", {})) == TYPE_DICTIONARY:
		note = data.get("note", {}) as Dictionary
	if _title_label:
		_title_label.text = String(note.get("title", summary.get("title", "")))
	if _date_label:
		var at := String(note.get("publishedAt", summary.get("publishedAt", "")))
		_date_label.text = at.replace("T", " ").substr(0, 19)
	if _body:
		_body.bbcode_enabled = true
		_body.text = MarkdownBbcode.to_bbcode(String(note.get("body", "")))
	if _status_label:
		_status_label.text = ""
