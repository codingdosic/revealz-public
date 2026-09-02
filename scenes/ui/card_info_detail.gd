class_name CardInfoDetail
extends Control
## 카드 상세(DetailRoot). CardInfoSidebar와 Zoom 사이 단계.
## 상점 CardInfoRoot · 인게임/덱에디터 사이드바 클릭 공용.

signal closed

const CARD_COLOR := {
	1: "BLACK",
	2: "WHITE",
	4: "GREEN",
	8: "RED",
	16: "BLUE",
	32: "COLORLESS",
}

const ZOOM_OVERLAY_SCENE := preload("res://scenes/ui/card_info_zoom_overlay.tscn")

@onready var _dimmer: ColorRect = $Dimmer
@onready var _art_panel: PanelContainer = $MarginContainer/HBoxContainer/PanelContainer
@onready var _text_panel: PanelContainer = $MarginContainer/HBoxContainer/PanelContainer2
@onready var _card_image: TextureRect = $MarginContainer/HBoxContainer/PanelContainer/MarginContainer2/VBoxContainer/TextureRect
@onready var _left_power: Label = $MarginContainer/HBoxContainer/PanelContainer/MarginContainer2/VBoxContainer/TextureRect/PowerRow/LeftPowerLabel
@onready var _center_power: Label = $MarginContainer/HBoxContainer/PanelContainer/MarginContainer2/VBoxContainer/TextureRect/PowerRow/CenterPowerLabel
@onready var _right_power: Label = $MarginContainer/HBoxContainer/PanelContainer/MarginContainer2/VBoxContainer/TextureRect/PowerRow/RightPowerLabel
@onready var _name_label: Label = $MarginContainer/HBoxContainer/PanelContainer2/MarginContainer/VBoxContainer2/NameLabel
@onready var _color_label: Label = $MarginContainer/HBoxContainer/PanelContainer2/MarginContainer/VBoxContainer2/MarginContainer/ColorLabel
@onready var _speed_label: Label = $MarginContainer/HBoxContainer/PanelContainer2/MarginContainer/VBoxContainer2/MarginContainer2/SpeedLabel
@onready var _card_type_label: Label = $MarginContainer/HBoxContainer/PanelContainer2/MarginContainer/VBoxContainer2/MarginContainer3/CardTypeLabel
@onready var _effect_label: RichTextLabel = $MarginContainer/HBoxContainer/PanelContainer2/MarginContainer/VBoxContainer2/MarginContainer4/EffectLabel

var chrome_style: UiChromeStyle
var _zoom_overlay: CardInfoZoomOverlay
var _rarity_frame: Panel
var _shown_rarity: int = CardRarity.Tier.N
var _back_consumed_frame: int = -1


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _dimmer and not _dimmer.gui_input.is_connected(_on_dimmer_gui_input):
		_dimmer.gui_input.connect(_on_dimmer_gui_input)
	if not gui_input.is_connected(_on_root_gui_input):
		gui_input.connect(_on_root_gui_input)
	if _card_image:
		_card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_card_image.custom_minimum_size = UiShellConstants.DETAIL_CARD_IMAGE_SIZE
		_card_image.mouse_filter = Control.MOUSE_FILTER_STOP
		if not _card_image.gui_input.is_connected(_on_card_image_gui_input):
			_card_image.gui_input.connect(_on_card_image_gui_input)
		if not _card_image.resized.is_connected(_on_card_image_resized):
			_card_image.resized.connect(_on_card_image_resized)
	for power in [_left_power, _center_power, _right_power]:
		if power:
			power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_rarity_frame()


func _exit_tree() -> void:
	if _zoom_overlay != null and is_instance_valid(_zoom_overlay):
		_zoom_overlay.queue_free()
		_zoom_overlay = null


## 크롬 패널·라벨.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	if _art_panel:
		chrome_style.apply_panel(_art_panel)
	if _text_panel:
		chrome_style.apply_panel(_text_panel)
	if _name_label:
		chrome_style.apply_title_label(_name_label)
	for label in [_color_label, _speed_label, _card_type_label, _left_power, _center_power, _right_power]:
		if label:
			chrome_style.apply_muted_label(label)
	if _effect_label:
		_effect_label.add_theme_color_override("default_color", chrome_style.font_muted)
	if _card_image:
		_card_image.custom_minimum_size = UiShellConstants.DETAIL_CARD_IMAGE_SIZE


## 인게임 카드 노드로 연다.
func present_card(card: Node, style: UiChromeStyle = null) -> void:
	if card == null or not is_instance_valid(card):
		hide_detail()
		return
	if style:
		apply_chrome(style)
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


## CardData로 연다. p_rarity < 0 이면 카탈로그 rarity.
func present_data(data: CardData, p_rarity: int = -1, style: UiChromeStyle = null) -> void:
	if data == null:
		hide_detail()
		return
	if style:
		apply_chrome(style)
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


## 이름·인스턴스 레어로 연다 (팩 칩).
func present_name(card_name: String, rarity: int, style: UiChromeStyle = null) -> void:
	if card_name.is_empty():
		hide_detail()
		return
	if style:
		apply_chrome(style)
	var data := CardRegistry.get_by_name(card_name)
	if data != null:
		present_data(data, rarity, null)
		return
	_apply_view(card_name, 0, null, 0, 0, 0, 0, rarity)


## 열려 있는지.
func is_open() -> bool:
	return visible


## 줌만 열려 있는지.
func is_zoom_visible() -> bool:
	return (
		_zoom_overlay != null
		and is_instance_valid(_zoom_overlay)
		and _zoom_overlay.is_overlay_visible()
	)


## 위층부터 닫기. 줌 → 상세. 처리했으면 true.
## 같은 프레임에 두 경로(gui_input + ScreenRmbBack/input)가 와도 한 단계만 닫는다.
func consume_back() -> bool:
	var frame := Engine.get_process_frames()
	if _back_consumed_frame == frame:
		return true
	if is_zoom_visible():
		_back_consumed_frame = frame
		_hide_zoom()
		return true
	if visible:
		_back_consumed_frame = frame
		hide_detail()
		return true
	return false


## 줌·상세를 닫는다.
func hide_detail() -> void:
	var was_open := visible
	_hide_zoom()
	visible = false
	if was_open:
		closed.emit()


func _apply_view(
	card_name: String,
	card_color: int,
	data: CardData,
	stat_l: int,
	stat_c: int,
	stat_r: int,
	stat_spd: int,
	rarity: int
) -> void:
	_hide_zoom()
	if chrome_style == null:
		apply_chrome(null)
	var copy := chrome_style.get_copy()
	_name_label.text = card_name if data == null else data.card_name
	_color_label.text = copy.card_color_prefix + String(CARD_COLOR.get(card_color, "?"))
	var tex: Texture2D = null
	if data != null and data.illustration:
		tex = data.illustration
	elif not card_name.is_empty():
		var path := "res://assets/Black/%s.png" % card_name
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
	_card_image.texture = tex
	_left_power.text = str(stat_l)
	_center_power.text = str(stat_c)
	_right_power.text = str(stat_r)
	_speed_label.text = copy.card_spd_format % stat_spd
	if data != null:
		_card_type_label.text = "%s / %s" % [data.card_type, data.type]
		_effect_label.text = CardDisplayHelpers.format_effect_text_bbcode(data)
	else:
		_card_type_label.text = ""
		_effect_label.text = ""
	_shown_rarity = clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	_apply_rarity_frame(_shown_rarity)
	CardRarityFoil.apply(_card_image, _shown_rarity)
	visible = true
	move_to_front()


func _on_card_image_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _card_image.texture == null:
		return
	if is_zoom_visible():
		_hide_zoom()
	else:
		_show_zoom()
	accept_event()


func _on_dimmer_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if is_zoom_visible():
		_hide_zoom()
	else:
		hide_detail()
	accept_event()


func _on_root_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	consume_back()
	accept_event()


func _show_zoom() -> void:
	_ensure_zoom()
	if _zoom_overlay == null:
		return
	_zoom_overlay.show_texture(
		_card_image.texture,
		UiShellConstants.SIDEBAR_CARD_IMAGE_SIZE * GameConstants.CARD_INFO_ZOOM_SCALE,
		_shown_rarity
	)


func _hide_zoom() -> void:
	if _zoom_overlay != null and is_instance_valid(_zoom_overlay):
		_zoom_overlay.hide_overlay()


func _ensure_zoom() -> void:
	if _zoom_overlay != null and is_instance_valid(_zoom_overlay):
		return
	_zoom_overlay = ZOOM_OVERLAY_SCENE.instantiate() as CardInfoZoomOverlay
	add_child(_zoom_overlay)
	_zoom_overlay.dismiss_requested.connect(_hide_zoom)


func _apply_rarity_frame(tier: int) -> void:
	_ensure_rarity_frame()
	if _rarity_frame == null:
		return
	var show := CardRarity.shows_frame(tier)
	_rarity_frame.visible = show
	if not show:
		return
	_rarity_frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(tier, 3.0))
	_fit_rarity_frame()
	call_deferred("_fit_rarity_frame")


func _ensure_rarity_frame() -> void:
	if _rarity_frame != null and is_instance_valid(_rarity_frame):
		return
	if _card_image == null:
		return
	_rarity_frame = _card_image.get_node_or_null("RarityFrame") as Panel
	if _rarity_frame == null:
		push_warning("[CardInfoDetail] missing RarityFrame")


func _on_card_image_resized() -> void:
	if _rarity_frame != null and _rarity_frame.visible:
		_fit_rarity_frame()


func _fit_rarity_frame() -> void:
	if _rarity_frame == null or not is_instance_valid(_rarity_frame):
		return
	var rect := _texture_draw_rect(_card_image)
	_rarity_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_rarity_frame.anchor_right = 0.0
	_rarity_frame.anchor_bottom = 0.0
	_rarity_frame.position = rect.position
	_rarity_frame.size = rect.size


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
