class_name MailboxItemRow
extends Button
## 선물함 목록 한 줄. 제목(카드 n장은 xN) · 날짜. 클릭 시 claim 요청.


signal claim_pressed(item: Dictionary)

const SCENE_PATH := "res://scenes/screen/mailbox_item_row.tscn"

@onready var _title_label: Label = $Content/VBox/TitleLabel
@onready var _summary_label: Label = $Content/VBox/SummaryLabel
@onready var _date_label: Label = $Content/VBox/DateLabel

var _item: Dictionary = {}


static func instantiate_row() -> MailboxItemRow:
	var packed := load(SCENE_PATH) as PackedScene
	return packed.instantiate() as MailboxItemRow


## 표시 제목. 동일 카드 n장(count>1)은 `제목 xN` 만 붙인다.
static func display_title(item: Dictionary) -> String:
	var title := String(item.get("title", "선물"))
	if title.is_empty():
		title = "선물"
	var count := payload_card_count(item.get("payload", {}))
	if count > 1:
		var suffix := " x%d" % count
		if not title.ends_with(suffix):
			return title + suffix
	return title


static func payload_card_count(payload: Variant) -> int:
	if typeof(payload) != TYPE_DICTIONARY:
		return 0
	var cards: Array = (payload as Dictionary).get("cards", []) as Array
	if cards.is_empty():
		return 0
	var total := 0
	for c in cards:
		if typeof(c) == TYPE_DICTIONARY:
			total += maxi(1, int((c as Dictionary).get("count", 1)))
	return total


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	_refresh()


func configure(item: Dictionary, chrome_style: UiChromeStyle = null) -> void:
	_item = item
	if chrome_style:
		chrome_style = UiChromeStyle.resolve(chrome_style)
		chrome_style.apply_buttons([self])
	_refresh()


func get_item() -> Dictionary:
	return _item


func _refresh() -> void:
	if _title_label == null:
		return
	_title_label.text = display_title(_item)
	var summary := _summary_from_payload(_item.get("payload", {}))
	_summary_label.text = summary
	_summary_label.visible = not summary.is_empty()
	var at := String(_item.get("created_at", "")).replace("T", " ")
	if at.length() > 16:
		at = at.substr(0, 16)
	_date_label.text = at


func _summary_from_payload(payload: Variant) -> String:
	if typeof(payload) != TYPE_DICTIONARY:
		return ""
	var gold := int((payload as Dictionary).get("gold", 0))
	if gold > 0:
		return "%d G" % gold
	return ""


func _on_pressed() -> void:
	claim_pressed.emit(_item)
