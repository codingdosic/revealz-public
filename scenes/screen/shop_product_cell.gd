extends Button
class_name ShopProductCell
## 상점 격자 상품 셀. 레이아웃은 shop_product_cell.tscn에서 조정.
## bind()로 ShopProduct 표시 데이터를 채운다.
## 함정: instantiate 직후 bind 시 @onready 미준비 — _ensure_nodes로 경로 조회.


signal product_pressed(product: ShopProduct)

var _icon: TextureRect
var _name_label: Label
var _price_label: Label
var _product: ShopProduct = null
var _pressed_connected: bool = false


## 시그널 연결(중복 방지).
func _ready() -> void:
	_ensure_nodes()
	_ensure_pressed_signal()


## Content 하위 노드를 확보한다. @onready 전에 bind해도 동작.
func _ensure_nodes() -> void:
	if _icon == null:
		_icon = get_node_or_null("Content/VBox/Icon") as TextureRect
	if _name_label == null:
		_name_label = get_node_or_null("Content/VBox/NameLabel") as Label
	if _price_label == null:
		_price_label = get_node_or_null("Content/VBox/PriceLabel") as Label


## pressed → product_pressed 연결(한 번만).
func _ensure_pressed_signal() -> void:
	if _pressed_connected:
		return
	pressed.connect(_on_pressed)
	_pressed_connected = true


## 상품 데이터로 아이콘·이름·가격(또는 보유 중)을 채운다.
func bind(product: ShopProduct, fallback_icon: Texture2D = null, owned: bool = false) -> void:
	_ensure_nodes()
	_ensure_pressed_signal()
	_product = product
	if _name_label == null or _price_label == null or _icon == null:
		push_warning("[ShopProductCell] missing Content/VBox children")
		return
	if product == null:
		_name_label.text = ""
		_price_label.text = ""
		_icon.texture = fallback_icon
		return
	_name_label.text = product.display_name if not product.display_name.is_empty() else product.product_id
	if owned:
		_price_label.text = "보유 중"
	else:
		_price_label.text = "%d G" % int(product.price_gold)
	var tex: Texture2D = null
	if product is ShopAccessoryProduct:
		tex = (product as ShopAccessoryProduct).resolve_icon()
	if tex == null and product.icon != null:
		tex = product.icon
	_icon.texture = tex if tex != null else fallback_icon
	_apply_icon_layout_for_product(product)


func _apply_icon_layout_for_product(product: ShopProduct) -> void:
	if _icon == null:
		return
	if product is ShopAccessoryProduct:
		var acc := product as ShopAccessoryProduct
		if acc.get_accessory_type() == AccessoryTypes.TYPE_CARD_BACK:
			_icon.custom_minimum_size = Vector2(88, 122)
			return
	_icon.custom_minimum_size = Vector2(120, 120)


## 크롬 스타일을 아이콘 제외 컨트롤에 적용한다.
func apply_chrome(style: UiChromeStyle) -> void:
	_ensure_nodes()
	if style == null:
		return
	style.apply_button_compact(self)
	if _name_label:
		style.apply_muted_label(_name_label)
	if _price_label:
		style.apply_muted_label(_price_label)


## 바인딩된 상품. 없으면 null.
func get_product() -> ShopProduct:
	return _product


## 클릭 시 product_pressed.
func _on_pressed() -> void:
	if _product != null:
		product_pressed.emit(_product)
