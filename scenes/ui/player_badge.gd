extends Button
class_name PlayerBadge
## 아이콘 + 표시명. 메인/인게임 플레이어 정보 표시.
## 사이즈 SSOT: 메인 씬 PlayerBadge (181×40, min 100×40).
## 레이아웃: 기본 Icon|Name · mirrored=true 면 Name|Icon (상대 배지).


signal profile_requested

const FALLBACK_ICON := preload("res://assets_lite/accessories/icon/icon_default.png")
## 메인 씬 규격. 인게임 Local/OpponentIdBadge도 동일 폭·높이.
const BADGE_WIDTH := 181.0
const BADGE_HEIGHT := 40.0
const BADGE_MIN_SIZE := Vector2(100, 40)
const _CONTENT_EDGE_MARGIN := 8

var _content: MarginContainer
var _hbox: HBoxContainer
var _icon: TextureRect
var _name_label: Label
var _clickable: bool = false
var _mirrored: bool = false


func _ready() -> void:
	_ensure_nodes()
	custom_minimum_size = BADGE_MIN_SIZE
	focus_mode = Control.FOCUS_NONE
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	_apply_layout_mirror()


func _ensure_nodes() -> void:
	if _content == null:
		_content = get_node_or_null("Content") as MarginContainer
	if _hbox == null:
		_hbox = get_node_or_null("Content/HBox") as HBoxContainer
	if _icon == null:
		_icon = get_node_or_null("Content/HBox/Icon") as TextureRect
	if _name_label == null:
		_name_label = get_node_or_null("Content/HBox/NameLabel") as Label


## display_name · icon_id(악세서리 catalog) · clickable(로컬 프로필 진입).
func configure(display_name: String, icon_id: String = "", clickable: bool = false) -> void:
	_ensure_nodes()
	_clickable = clickable
	if _name_label:
		_name_label.text = display_name.strip_edges()
	var tex := AccessoryRuntime.texture_for_id(icon_id) if not icon_id.is_empty() else null
	if _icon:
		_icon.texture = tex if tex != null else FALLBACK_ICON
	mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	disabled = false


## 상대 배지용 — Name|Icon + 여백/정렬 좌우 반전.
func set_layout_mirrored(mirrored: bool) -> void:
	_mirrored = mirrored
	_apply_layout_mirror()


func apply_chrome(style: UiChromeStyle) -> void:
	_ensure_nodes()
	if style == null:
		return
	# 아이콘 반대쪽 챔퍼: Icon|Name → 우측, Name|Icon → 좌측.
	style.apply_player_badge(self, not _mirrored)
	if _name_label:
		style.apply_muted_label(_name_label)


func _apply_layout_mirror() -> void:
	_ensure_nodes()
	if _hbox == null or _icon == null or _name_label == null:
		return
	if _mirrored:
		_hbox.move_child(_name_label, 0)
		_hbox.move_child(_icon, 1)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		_hbox.move_child(_icon, 0)
		_hbox.move_child(_name_label, 1)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _content:
		_content.add_theme_constant_override(
			"margin_left", _CONTENT_EDGE_MARGIN if _mirrored else 0
		)
		_content.add_theme_constant_override(
			"margin_right", 0 if _mirrored else _CONTENT_EDGE_MARGIN
		)


func _on_pressed() -> void:
	if _clickable:
		profile_requested.emit()
