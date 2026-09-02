extends PanelContainer
## 카드 정보 사이드바. 인게임 노드 또는 CardData로 표시 (G3 에디터 공용).
## 틀·닫기=SidebarShell. 배경·테두리=이 패널(내용). 폭·일러=UiShellConstants.
## 문구=UiCopy (chrome.copy). 룩=UiChromeStyle.

const CARD_COLOR = {
	1: "BLACK",
	2: "WHITE",
	4: "GREEN",
	8: "RED",
	16: "BLUE",
	32: "COLORLESS",
}

const DETAIL_SCENE := preload("res://scenes/ui/card_info_detail.tscn")

@export var chrome_style: UiChromeStyle

@onready var _card_image: TextureRect = $Margin/VBox/CardImage
@onready var _left_power_label: Label = $Margin/VBox/CardImage/LeftPowerLabel
@onready var _center_power_label: Label = $Margin/VBox/CardImage/CenterPowerLabel
@onready var _right_power_label: Label = $Margin/VBox/CardImage/RightPowerLabel
@onready var _name_label: Label = $Margin/VBox/NameLabel
@onready var _color_label: Label = $Margin/VBox/ColorLabel
#@onready var _rarity_label: Label = $Margin/VBox/RarityLabel
@onready var _speed_label: Label = $Margin/VBox/SpeedLabel
@onready var _card_type_label: Label = $Margin/VBox/CardTypeLabel
@onready var _effect_label: RichTextLabel = $Margin/VBox/EffectLabel

var _visible_card: Node
var _shown_data: CardData
var _detail: CardInfoDetail
var _rarity_frame: Panel
var _shown_rarity: int = CardRarity.Tier.N


## 시작 시 숨김 · 크롬 · CardImage 클릭으로 DetailRoot.
func _ready() -> void:
	visible = false
	apply_chrome(chrome_style)
	_card_image.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_image.gui_input.connect(_on_card_image_gui_input)
	_left_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
		_detail = null


## 크롬 패널·라벨 적용 · 일러 크기를 SIDEBAR_CARD_IMAGE_SIZE 로 맞춘다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	chrome_style.apply_panel(self)
	chrome_style.apply_title_label(_name_label)
	chrome_style.apply_muted_label(_color_label)
	#if _rarity_label:
		#chrome_style.apply_muted_label(_rarity_label)
	chrome_style.apply_muted_label(_speed_label)
	chrome_style.apply_muted_label(_card_type_label)
	if _effect_label:
		_effect_label.add_theme_color_override("default_color", chrome_style.font_muted)
	_apply_card_image_size()


## 사이드바 일러 custom_minimum_size 를 상수에 맞춘다.
func _apply_card_image_size() -> void:
	if _card_image == null:
		return
	_card_image.custom_minimum_size = UiShellConstants.SIDEBAR_CARD_IMAGE_SIZE


## 인게임 카드 노드로 사이드바를 채운다.
func show_card(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		hide_sidebar()
		return
	_visible_card = card
	var rarity := CardRarity.Tier.N
	var raw: Variant = card.get("instance_rarity")
	if raw != null:
		rarity = clampi(int(raw), CardRarity.Tier.N, CardRarity.Tier.UR)
	_apply_view(
		str(card.card_name),
		int(card.card_color),
		card.card_data as CardData,
		int(card.stat_l),
		int(card.stat_c),
		int(card.stat_r),
		int(card.stat_spd),
		rarity
	)


## 에디터 등: CardData만으로 사이드바를 채운다 (카드 노드 없음).
## p_rarity < 0 이면 CardData.rarity(카탈로그)를 쓴다.
func show_card_data(data: CardData, p_rarity: int = -1) -> void:
	if data == null:
		hide_sidebar()
		return
	_visible_card = null
	var rarity := p_rarity
	if rarity < 0:
		rarity = clampi(int(data.rarity), CardRarity.Tier.N, CardRarity.Tier.UR)
	else:
		rarity = clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	_apply_view(
		data.card_name,
		data.color,
		data,
		data.stat_l,
		data.stat_c,
		data.stat_r,
		data.stat_spd,
		rarity
	)


## 라벨·일러스트·레어도를 채우고 표시한다.
func _apply_view(
	card_name: String,
	card_color: int,
	data: CardData,
	stat_l: int,
	stat_c: int,
	stat_r: int,
	stat_spd: int,
	rarity: int = CardRarity.Tier.N
) -> void:
	_hide_detail()
	var copy := _copy()
	_name_label.text = card_name
	_color_label.text = copy.card_color_prefix + CARD_COLOR[card_color]
	#if _rarity_label:
		#_rarity_label.text = copy.card_rarity_prefix + CardRarity.label_of(rarity)
	var tex: Texture2D = null
	if data != null and data.illustration:
		tex = data.illustration
	elif not card_name.is_empty():
		var path := "res://assets/Black/%s.png" % card_name
		if ResourceLoader.exists(path):
			tex = load(path)
	_card_image.texture = tex
	_left_power_label.text = str(stat_l)
	_center_power_label.text = str(stat_c)
	_right_power_label.text = str(stat_r)
	_speed_label.text = copy.card_spd_format % stat_spd
	if data != null:
		_card_type_label.text = "%s / %s" % [data.card_type, data.type]
		_effect_label.text = CardDisplayHelpers.format_effect_text_bbcode(data)
	else:
		_card_type_label.text = ""
		_effect_label.text = ""
	_apply_rarity_frame(rarity)
	_shown_rarity = clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	_shown_data = data
	CardRarityFoil.apply(_card_image, _shown_rarity)
	visible = true
	SidebarContentUtil.sync_shell(self, true)


## 일러 위 R+ 프레임. N이면 숨김. KEEP_ASPECT 레터박스에 맞춰 텍스처 영역에 fit.
func _apply_rarity_frame(tier: int) -> void:
	_ensure_rarity_frame()
	if _rarity_frame == null:
		return
	var show := CardRarity.shows_frame(tier)
	_rarity_frame.visible = show
	if not show:
		return
	_rarity_frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(tier, 3.0))
	_fit_rarity_frame_to_texture()
	# 첫 레이아웃 전 size가 0일 수 있어 한 프레임 뒤 재정렬.
	call_deferred("_fit_rarity_frame_to_texture")


## CardImage 자식 RarityFrame을 확보한다 (위치·크기는 텍스처 draw rect에 맞춤).
func _ensure_rarity_frame() -> void:
	if _rarity_frame != null and is_instance_valid(_rarity_frame):
		return
	_rarity_frame = _card_image.get_node_or_null("RarityFrame") as Panel
	if _rarity_frame == null:
		push_warning("[CardInfoSidebar] missing RarityFrame scene child")
		return
	if not _card_image.resized.is_connected(_on_card_image_resized):
		_card_image.resized.connect(_on_card_image_resized)


## CardImage 리사이즈 시 프레임을 텍스처 draw rect에 재정렬.
func _on_card_image_resized() -> void:
	if _rarity_frame != null and _rarity_frame.visible:
		_fit_rarity_frame_to_texture()


## KEEP_ASPECT_CENTERED 기준 실제 그려진 텍스처 영역에 프레임을 맞춘다.
func _fit_rarity_frame_to_texture() -> void:
	if _rarity_frame == null or not is_instance_valid(_rarity_frame):
		return
	var rect := _texture_draw_rect(_card_image)
	_rarity_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_rarity_frame.anchor_right = 0.0
	_rarity_frame.anchor_bottom = 0.0
	_rarity_frame.position = rect.position
	_rarity_frame.size = rect.size


## TextureRect 안에서 KEEP_ASPECT_CENTERED로 그려지는 텍스처 rect.
func _texture_draw_rect(tr: TextureRect) -> Rect2:
	if tr == null:
		return Rect2()
	var view := tr.size
	if view.x <= 0.0 or view.y <= 0.0:
		return Rect2(Vector2.ZERO, view)
	if tr.texture == null:
		return Rect2(Vector2.ZERO, view)
	var tex_size := tr.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Rect2(Vector2.ZERO, view)
	var scale := minf(view.x / tex_size.x, view.y / tex_size.y)
	var drawn := tex_size * scale
	var origin := (view - drawn) * 0.5
	return Rect2(origin, drawn)


## 사이드바를 닫는다. DetailRoot도 같이 닫힘. 패널 visible은 셸 close 연출 후에 꺼진다.
func hide_sidebar() -> void:
	_hide_detail()
	_visible_card = null
	_shown_data = null
	var shell := SidebarContentUtil.find_shell(self)
	if shell != null and shell.visible:
		shell.call("close", "content")
		return
	visible = false


## 현재 그 카드 노드를 표시 중인지.
func is_showing_card(card: Node) -> bool:
	return visible and _visible_card == card


## 이 패널에 묶인 UiCopy.
func _copy() -> UiCopy:
	return UiChromeStyle.resolve(chrome_style).get_copy()


## CardImage 좌클릭으로 DetailRoot.
func _on_card_image_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _card_image.texture == null:
		return
	if is_detail_open():
		_hide_detail()
	else:
		_show_detail()
	accept_event()


## DetailRoot가 보이는지.
func is_detail_open() -> bool:
	return _detail != null and is_instance_valid(_detail) and _detail.is_open()


## 줌 → Detail. 처리했으면 true (사이드바는 열어둠).
func consume_back() -> bool:
	if _detail != null and is_instance_valid(_detail):
		return _detail.consume_back()
	return false


## DetailRoot를 화면 호스트에 한 번 붙인다.
func _ensure_detail() -> void:
	if _detail != null and is_instance_valid(_detail):
		return
	var host := _overlay_host()
	_detail = DETAIL_SCENE.instantiate() as CardInfoDetail
	host.add_child(_detail)
	if _detail.get_parent() is CanvasLayer or _detail.get_parent() is Control:
		_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail.z_index = 80
	_detail.apply_chrome(chrome_style)


## CanvasLayer(인게임) 또는 스크린 루트(덱에디터)를 찾는다.
func _overlay_host() -> Node:
	var n: Node = self
	while n:
		var parent := n.get_parent()
		if parent is CanvasLayer:
			return parent
		if parent == null or parent is Window or parent is Viewport:
			return n
		n = parent
	return self


## 현재 표시 카드로 DetailRoot를 연다.
func _show_detail() -> void:
	_ensure_detail()
	if _detail == null:
		return
	if _visible_card != null and is_instance_valid(_visible_card):
		_detail.present_card(_visible_card, chrome_style)
		return
	if _shown_data != null:
		_detail.present_data(_shown_data, _shown_rarity, chrome_style)


## DetailRoot를 닫는다.
func _hide_detail() -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.hide_detail()
