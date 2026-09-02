extends Button
class_name AccessoryPickCell
## 악세서리 선택 격자 셀 — Icon + Name. shop_product_cell과 유사(가격 없음).
## main_card 타입은 덱 카드 일러스트 + R+ foil.


signal accessory_pressed(accessory_id: String)

const FALLBACK_ICON := preload("res://assets_lite/accessories/icon/icon_default.png")
const FALLBACK_CARD_BACK := preload("res://assets_lite/accessories/card_back/card_back_default.png")
const CARD_BACK_ICON_MIN := Vector2(88, 122)
const TYPE_MAIN_CARD := "main_card"

var _icon: TextureRect
var _name_label: Label
var _accessory_id: String = ""
var _pressed_connected: bool = false
var _pending_display_name: String = ""
var _pending_preview: Texture2D = null
var _pending_rarity: int = CardRarity.Tier.N
var _accessory_type: String = AccessoryTypes.TYPE_ICON
var _selection_ring: Panel = null


func _ready() -> void:
	_ensure_nodes()
	_ensure_pressed_signal()
	_apply_pending_bind()


func _ensure_nodes() -> void:
	if _icon == null:
		_icon = get_node_or_null("Content/VBox/Icon") as TextureRect
	if _name_label == null:
		_name_label = get_node_or_null("Content/VBox/NameLabel") as Label


func _ensure_pressed_signal() -> void:
	if _pressed_connected:
		return
	pressed.connect(_on_pressed)
	_pressed_connected = true


func configure_for_type(accessory_type: String) -> void:
	_accessory_type = accessory_type.strip_edges()
	_apply_icon_layout()


func bind(
	accessory_id: String,
	display_name: String,
	preview: Texture2D = null,
	rarity: int = CardRarity.Tier.N
) -> void:
	_ensure_nodes()
	_ensure_pressed_signal()
	_accessory_id = accessory_id.strip_edges()
	_pending_display_name = display_name
	_pending_preview = preview
	_pending_rarity = clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	_apply_pending_bind()


func _apply_pending_bind() -> void:
	if _accessory_id.is_empty() and _pending_display_name.is_empty() and _pending_preview == null:
		return
	_ensure_nodes()
	if _name_label:
		var label := _pending_display_name if not _pending_display_name.is_empty() else _accessory_id
		_name_label.text = label
	if _icon:
		var tex := _pending_preview
		if tex == null and not _accessory_id.is_empty() and _accessory_type != TYPE_MAIN_CARD:
			tex = AccessoryCatalog.preview_for_id(_accessory_id)
		_icon.texture = tex if tex != null else _fallback_texture()
		_apply_rarity_foil()
	_apply_icon_layout()


func _apply_rarity_foil() -> void:
	if _icon == null:
		return
	if _accessory_type == TYPE_MAIN_CARD and CardRarity.shows_display(_pending_rarity):
		CardRarityFoil.apply(_icon, _pending_rarity)
	else:
		CardRarityFoil.clear(_icon)


func _fallback_texture() -> Texture2D:
	if _accessory_type == AccessoryTypes.TYPE_CARD_BACK or _accessory_type == TYPE_MAIN_CARD:
		return FALLBACK_CARD_BACK
	return FALLBACK_ICON


func _apply_icon_layout() -> void:
	if _icon == null:
		return
	# IGNORE_SIZE: 가로로 긴 field preview가 FIT_WIDTH_PROPORTIONAL로 셀(160)을
	# 넘기지 않도록. 상점 ShopProductCell과 동일.
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if (
		_accessory_type == AccessoryTypes.TYPE_CARD_BACK
		or _accessory_type == TYPE_MAIN_CARD
	):
		_icon.custom_minimum_size = CARD_BACK_ICON_MIN
	else:
		_icon.custom_minimum_size = Vector2(120, 120)


func apply_chrome(style: UiChromeStyle) -> void:
	_ensure_nodes()
	if style == null:
		return
	style.apply_button_compact(self)
	if _name_label:
		style.apply_muted_label(_name_label)


func set_selected(on: bool) -> void:
	modulate = Color.WHITE
	_selection_ring = SelectionHighlight.set_ui_cell_selected(self, _selection_ring, on)


func get_accessory_id() -> String:
	return _accessory_id


func _on_pressed() -> void:
	if not _accessory_id.is_empty():
		accessory_pressed.emit(_accessory_id)
