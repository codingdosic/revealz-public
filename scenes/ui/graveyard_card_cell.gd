extends PanelContainer
## 묘지/선택 바용 카드 썸네일 셀.
## TargetSelectBar·ZoneBrowse(CardGridView)·(레거시) graveyard_grid_panel 에서 사용.
## 셀 색·소유 테두리: UiChromeStyle.cell_* · 배지/foil은 setup 플래그로 제어.
## 선택 링은 프레임 위 SelectionRing에서 그린다.

signal card_pressed(card: Node)

@onready var _image: TextureRect = $Margin/CardImage
@onready var _highlight: ColorRect = $Highlight

const DRAG_THRESHOLD_PX := 8.0
const SELECTION_RING_Z := 30

## 가로 드래그 스크롤용. total_dx = 프레스 이후 X 누적 이동.
signal drag_moved(total_dx: float)

@export var chrome_style: UiChromeStyle

var _card: Node
var _owner_border_style: StyleBoxFlat
var _is_selected: bool = false
var _h_drag_scroll: bool = false
var _show_rarity_badge: bool = true
var _apply_rarity_foil: bool = false
var _pressing: bool = false
var _dragging: bool = false
var _press_global_x: float = 0.0
var _rarity_frame: Panel
var _rarity_badge: Panel
var _rarity_label: Label
var _selection_ring: Panel


## 카드 텍스처·소유 테두리·레어도·선택 가능 여부를 세팅한다.
## show_rarity_badge: 우상단 배지. apply_rarity_foil: 일러스트 R+ foil 쉐이더.
func setup(
	card: Node,
	selectable: bool,
	enable_h_drag_scroll: bool = false,
	show_rarity_badge: bool = true,
	apply_rarity_foil: bool = false
) -> void:
	_card = card
	_h_drag_scroll = enable_h_drag_scroll
	_show_rarity_badge = show_rarity_badge
	_apply_rarity_foil = apply_rarity_foil
	if card == null or not is_instance_valid(card):
		return
	var tex: Texture2D = null
	if card.card_data and card.card_data.illustration:
		tex = card.card_data.illustration
	elif card.card_name != "":
		var path := "res://assets/Black/%s.png" % card.card_name
		if ResourceLoader.exists(path):
			tex = load(path)
	_image.texture = tex
	_highlight.visible = false
	_is_selected = false
	_apply_owner_border(card)
	_apply_rarity_visual(card)
	_ensure_selection_ring()
	if _selection_ring:
		_selection_ring.visible = false
	if selectable:
		_image.modulate = Color(1, 1, 1, 1)
	else:
		_image.modulate = Color(0.65, 0.65, 0.65, 0.85)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input.bind(selectable))


## 바인딩된 카드 노드.
func get_card() -> Node:
	return _card


## 선택 링 on/off. 소유자 테두리는 유지. 링은 레어 프레임 위에 표시.
func set_selected(selected: bool) -> void:
	_is_selected = selected
	_highlight.visible = false
	if _owner_border_style:
		add_theme_stylebox_override("panel", _owner_border_style)
	_ensure_selection_ring()
	if _selection_ring:
		_selection_ring.visible = selected


## 소유 사이드별 셀 StyleBox 를 크롬에서 만들어 적용한다.
func _apply_owner_border(card: Node) -> void:
	var chrome := UiChromeStyle.resolve(chrome_style)
	var style := chrome.make_cell_stylebox(int(card.owner_side))
	_owner_border_style = style
	if not _is_selected:
		add_theme_stylebox_override("panel", style)


## instance_rarity 기준 배지·프레임·foil (각각 플래그/게이트).
func _apply_rarity_visual(card: Node) -> void:
	_ensure_rarity_nodes()
	var tier := CardRarity.Tier.N
	var raw: Variant = card.get("instance_rarity")
	if raw != null:
		tier = clampi(int(raw), CardRarity.Tier.N, CardRarity.Tier.UR)
	if _rarity_frame:
		var show_frame := CardRarity.shows_frame(tier)
		_rarity_frame.visible = show_frame
		if show_frame:
			_rarity_frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(tier, 2.0))
	if _rarity_badge:
		var show_badge := _show_rarity_badge and CardRarity.shows_badge(tier)
		_rarity_badge.visible = show_badge
		if show_badge:
			_rarity_badge.add_theme_stylebox_override("panel", CardRarity.make_badge_style(tier))
		if _rarity_label and show_badge:
			_rarity_label.text = CardRarity.label_of(tier)
	if _image:
		if _apply_rarity_foil and CardRarity.shows_display(tier):
			CardRarityFoil.apply(_image, tier)
		else:
			CardRarityFoil.clear(_image)


## 이미지 위 레어 프레임·배지 노드를 보장한다 (@onready 전 setup 호출도 경로로 조회).
func _ensure_rarity_nodes() -> void:
	if _rarity_frame == null:
		if _image != null:
			_rarity_frame = _image.get_node_or_null("RarityFrame") as Panel
		if _rarity_frame == null:
			_rarity_frame = get_node_or_null("Margin/CardImage/RarityFrame") as Panel
		if _rarity_frame == null:
			push_warning("[GraveyardCardCell] missing RarityFrame scene child")
	if _rarity_badge == null:
		if _image != null:
			_rarity_badge = _image.get_node_or_null("RarityBadge") as Panel
		if _rarity_badge == null:
			_rarity_badge = get_node_or_null("Margin/CardImage/RarityBadge") as Panel
		if _rarity_badge == null:
			push_warning("[GraveyardCardCell] missing RarityBadge scene child")
			return
	if _rarity_label == null and _rarity_badge != null:
		_rarity_label = _rarity_badge.get_node_or_null("Label") as Label
		if _rarity_label == null:
			push_warning("[GraveyardCardCell] missing RarityBadge/Label")


## 셀 최상단 선택 링. 부모 _draw는 자식(레어 프레임)에 가려지므로 별도 Panel 사용.
func _ensure_selection_ring() -> void:
	if _selection_ring != null and is_instance_valid(_selection_ring):
		return
	_selection_ring = get_node_or_null("SelectionRing") as Panel
	if _selection_ring == null:
		push_warning("[GraveyardCardCell] missing SelectionRing scene child")
		return
	_selection_ring.add_theme_stylebox_override("panel", SelectionHighlight.make_chosen_stylebox())
	SelectionHighlight.configure_control_inset_ring(_selection_ring)
	move_child(_selection_ring, get_child_count() - 1)


## 클릭·가로 드래그 스크롤 입력 처리.
func _on_gui_input(event: InputEvent, _selectable: bool) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragging = false
			_press_global_x = event.global_position.x
			accept_event()
			return
		# release
		if _pressing and not _dragging:
			card_pressed.emit(_card)
		_pressing = false
		_dragging = false
		accept_event()
		return
	if not _h_drag_scroll:
		return
	if event is InputEventMouseMotion and _pressing:
		var total_dx: float = event.global_position.x - _press_global_x
		if not _dragging and absf(total_dx) >= DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			drag_moved.emit(total_dx)
			accept_event()
