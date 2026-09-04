class_name NotificationBadge
extends PanelContainer
## 재사용 알림 배지. 부모(버튼 등) 우상단에 빨간 원 + 마크를 표시한다.
## 클릭은 부모로 통과 (mouse_filter IGNORE).


const SCENE_PATH := "res://scenes/ui/notification_badge.tscn"
const DEFAULT_MARK := "!"

@onready var _mark_label: Label = $MarkLabel

var _alert_on: bool = false


static func instantiate_badge() -> NotificationBadge:
	var packed := load(SCENE_PATH) as PackedScene
	return packed.instantiate() as NotificationBadge


## 부모 Control 우상단에 배지를 붙인다. 이미 붙어 있으면 재사용.
static func attach_to(host: Control) -> NotificationBadge:
	if host == null:
		return null
	for child in host.get_children():
		if child is NotificationBadge:
			return child as NotificationBadge
	var badge := instantiate_badge()
	host.add_child(badge)
	badge._fit_to_host()
	return badge


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_to_host()
	_apply_visible()


## 알림 on/off. 마크 문자는 기본 "!".
func set_alert(on: bool, mark: String = DEFAULT_MARK) -> void:
	_alert_on = on
	if _mark_label:
		_mark_label.text = mark if not mark.is_empty() else DEFAULT_MARK
	_apply_visible()


func has_alert() -> bool:
	return _alert_on


func _fit_to_host() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -14.0
	offset_top = -8.0
	offset_right = 6.0
	offset_bottom = 12.0
	z_index = 10


func _apply_visible() -> void:
	visible = _alert_on
