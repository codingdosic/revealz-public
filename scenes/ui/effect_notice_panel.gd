extends PanelContainer
## 상대 효과 처리 중 알림 (상단 토스트).
## L4a: 팝업 계열 notice. 재사용 베이스는 PopupShell.configure_notice.
## mouse_filter=IGNORE — 클릭이 아래로 통과. 위치: UiShellConstants.POPUP_NOTICE_*
## 룩: UiChromeStyle.

@export var chrome_style: UiChromeStyle

@onready var _title: Label = $Margin/VBox/TitleLabel
@onready var _message: Label = $Margin/VBox/MessageLabel


## 부트: 클릭 통과 · 숨김 · 크롬.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	apply_chrome(chrome_style)


## 크롬 팔레트로 패널·라벨을 갱신한다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	chrome_style.apply_panel(self)
	chrome_style.apply_title_label(_title)
	chrome_style.apply_muted_label(_message)


## 상대 효과 알림을 표시한다.
func show_notice(card_name: String, trigger_text: String = "") -> void:
	_title.text = UiChromeStyle.resolve(chrome_style).get_copy().effect_notice_title
	if trigger_text.is_empty():
		_message.text = card_name
	else:
		_message.text = "%s — %s" % [card_name, trigger_text]
	visible = true
	_sync_parent_popup_shell(true)


## 알림을 숨긴다. 패널 visible은 셸 close 연출 후에 꺼진다.
func hide_notice() -> void:
	_message.text = ""
	var shell := _find_popup_shell()
	if shell != null and shell.visible:
		shell.call("close", "content")
	else:
		visible = false


## 부모 PopupShell open/close 동기화.
func _sync_parent_popup_shell(open: bool) -> void:
	var shell := _find_popup_shell()
	if shell == null:
		return
	if open:
		if not shell.visible:
			shell.call("open")
	elif shell.visible:
		shell.call("close", "content")


## Control 반환 — export 에서 `as PopupShell` 캐스트가 null 이 되는 경우 방지.
func _find_popup_shell() -> Control:
	var n: Node = get_parent()
	while n:
		if n is Control and n.has_method("open") and n.has_method("close"):
			if n.has_method("use_content_notice") or n is PopupShell:
				return n as Control
		n = n.get_parent()
	return null
