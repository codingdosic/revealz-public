extends Button
class_name DeckSelectCell
## 덱 선택 격자 셀. 레이아웃은 deck_select_cell.tscn에서 조정.
## Icon=카드 뒷면 · MainCard=메인 카드(일러스트+foil) · Name/Sub.
## 함정: instantiate 직후 bind 시 @onready 미준비 — _ensure_nodes로 경로 조회.


signal cell_pressed(cell: DeckSelectCell)

const DEFAULT_CARD_BACK := preload("res://assets_lite/accessories/card_back/card_back_default.png")
const CARD_BACK_ICON_MIN := Vector2(88, 122)

var _icon: TextureRect
var _main_card: TextureRect
var _name_label: Label
var _sub_label: Label
var _deck_id: String = ""
var _display_name: String = ""
var _is_add_cell: bool = false
var _pressed_connected: bool = false
var _selection_ring: Panel = null


## 시그널 연결(중복 방지).
func _ready() -> void:
	_ensure_nodes()
	_ensure_pressed_signal()


## Content 하위 노드를 확보한다. @onready 전에 bind해도 동작.
func _ensure_nodes() -> void:
	if _icon == null:
		_icon = get_node_or_null("Content/VBox/Control/Icon") as TextureRect
	if _main_card == null:
		_main_card = get_node_or_null("Content/VBox/Control/MainCard") as TextureRect
	if _name_label == null:
		_name_label = get_node_or_null("Content/VBox/NameLabel") as Label
	if _sub_label == null:
		_sub_label = get_node_or_null("Content/VBox/SubLabel") as Label


## pressed → cell_pressed 연결(한 번만).
func _ensure_pressed_signal() -> void:
	if _pressed_connected:
		return
	pressed.connect(_on_pressed)
	_pressed_connected = true


## 신규 덱(+) 셀로 표시한다. 아이콘 비움 · 이름 "+" · 부제 공란.
func configure_as_add() -> void:
	_ensure_nodes()
	_ensure_pressed_signal()
	_is_add_cell = true
	_deck_id = ""
	_display_name = "+"
	if _name_label:
		_name_label.text = "+"
	if _sub_label:
		_sub_label.text = ""
	if _icon:
		_icon.texture = null
		_icon.visible = false
	if _main_card:
		CardRarityFoil.clear(_main_card)
		_main_card.texture = null
		_main_card.visible = false


## 이름·부제·뒷면·메인 카드를 채운다. deck_id는 후속 선택 로직용.
func bind(deck_id: String, display_name: String, subtitle: String = "", icon: Texture2D = null) -> void:
	_ensure_nodes()
	_ensure_pressed_signal()
	_is_add_cell = false
	_deck_id = deck_id
	_display_name = display_name
	if _name_label == null or _sub_label == null or _icon == null:
		push_warning("[DeckSelectCell] missing Content/VBox children")
		return
	_name_label.text = display_name
	_sub_label.text = subtitle
	var back_tex := icon
	if back_tex == null and not deck_id.is_empty():
		back_tex = AccessoryRuntime.card_back_texture(DeckStore.card_back_id_of(deck_id))
	_icon.visible = true
	_icon.texture = back_tex if back_tex != null else DEFAULT_CARD_BACK
	_apply_icon_layout()
	_apply_main_card()


## 메인 카드 일러스트 + foil. 빈 덱이면 card_back.
func _apply_main_card() -> void:
	if _main_card == null:
		return
	_main_card.visible = true
	_apply_main_card_layout()
	if _deck_id.is_empty():
		CardRarityFoil.clear(_main_card)
		_main_card.texture = DEFAULT_CARD_BACK
		return
	var resolved := DeckStore.main_card_of(_deck_id)
	if resolved.is_empty():
		CardRarityFoil.clear(_main_card)
		_main_card.texture = _icon.texture if _icon and _icon.texture else DEFAULT_CARD_BACK
		return
	var card_id := int(resolved.get("card_id", 0))
	var rarity := int(resolved.get("rarity", CardRarity.Tier.N))
	var data := CardRegistry.get_by_id(card_id)
	var art: Texture2D = data.illustration if data != null else null
	_main_card.texture = art if art != null else DEFAULT_CARD_BACK
	if CardRarity.shows_display(rarity):
		CardRarityFoil.apply(_main_card, rarity)
	else:
		CardRarityFoil.clear(_main_card)


## 크롬 스타일을 아이콘 제외 컨트롤에 적용한다.
func apply_chrome(style: UiChromeStyle) -> void:
	_ensure_nodes()
	if style == null:
		return
	style.apply_button_compact(self)
	if _name_label:
		style.apply_muted_label(_name_label)
	if _sub_label:
		style.apply_muted_label(_sub_label)


## 바인딩된 덱 id. + 셀이면 "".
func get_deck_id() -> String:
	return _deck_id


## 표시 이름.
func get_display_name() -> String:
	return _display_name


## 신규(+) 셀이면 true.
func is_add_cell() -> bool:
	return _is_add_cell


## 덱 셀 아이콘은 카드 뒷면 비율(세로형)로 표시한다.
func _apply_icon_layout() -> void:
	if _icon == null:
		return
	_icon.custom_minimum_size = CARD_BACK_ICON_MIN
	_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _apply_main_card_layout() -> void:
	if _main_card == null:
		return
	_main_card.custom_minimum_size = CARD_BACK_ICON_MIN
	_main_card.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_main_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


## 선택 하이라이트 on/off — 시안 테두리 링 (modulate 틴트 없음).
func set_highlighted(on: bool) -> void:
	modulate = Color.WHITE
	_selection_ring = SelectionHighlight.set_ui_cell_selected(self, _selection_ring, on)


## 클릭 시 cell_pressed.
func _on_pressed() -> void:
	cell_pressed.emit(self)
