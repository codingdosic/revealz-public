extends PanelContainer
## 효과 확인/선택 다이얼로그 (중앙 확인형 팝업).
## L4a: 팝업 계열 confirm. 재사용 베이스는 PopupShell.configure_confirm.
## ButtonRow 순서 SSOT: Cancel | Confirm (PopupShell과 동일).
## 최소화 시 game_ui_layer MinimizeHandle 로 복귀 (SelectionPresenter).
## 룩: UiChromeStyle (기본 ui_chrome_cyan.tres).
##
## 튜닝: tscn 중앙 offset (±180 등) ↔ UiShellConstants.POPUP_CONFIRM_HALF

signal confirmed
signal canceled
signal minimized

@export var chrome_style: UiChromeStyle

@onready var _title: Label = $Margin/VBox/TitleLabel
@onready var _minimize_button: Button = $Margin/VBox/TitleLabel/MinimizeButton
@onready var _message: Label = $Margin/VBox/MarginContainer/MessageLabel
@onready var _confirm_button: Button = $Margin/VBox/ButtonRow/ConfirmButton
@onready var _cancel_button: Button = $Margin/VBox/ButtonRow/CancelButton


## 부트: 크롬 적용 · 버튼 시그널 · 숨김.
func _ready() -> void:
	apply_chrome(chrome_style)
	_confirm_button.pressed.connect(func() -> void: confirmed.emit())
	_cancel_button.pressed.connect(func() -> void: canceled.emit())
	_minimize_button.pressed.connect(func() -> void: minimized.emit())
	visible = false


## 크롬 팔레트로 패널·라벨·확인/취소/최소화 버튼을 갱신한다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	chrome_style.apply_panel(self)
	chrome_style.apply_title_label(_title)
	chrome_style.apply_muted_label(_message)
	chrome_style.apply_buttons([_confirm_button, _cancel_button, _minimize_button])


## 제목·본문·버튼 문구를 설정한다.
func configure(title: String, message: String, confirm_text: String, cancel_text: String) -> void:
	_title.text = title
	_message.text = message
	_confirm_button.text = confirm_text
	_cancel_button.text = cancel_text


## 다이얼로그를 보이고 부모 PopupShell 을 연다.
func show_dialog() -> void:
	visible = true
	_clear_in_game_card_hover()
	_sync_parent_popup_shell(true)


## 인게임 카드 호버가 다이얼로그 아래에 남지 않게 한다.
func _clear_in_game_card_hover() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("card_manager"):
		if n != null and n.has_method("clear_hover_state"):
			n.clear_hover_state()
			return


## 다이얼로그를 숨기고 부모 PopupShell 을 닫는다. 패널 visible은 셸 close 연출 후에 꺼진다.
func hide_dialog() -> void:
	var shell := _find_popup_shell()
	if shell != null and shell.visible:
		shell.call("close", "content")
	else:
		visible = false


## 부모 PopupShell 의 open/close 를 콘텐츠 visible 과 맞춘다.
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
			if n.has_method("use_content_confirm") or n is PopupShell:
				return n as Control
		n = n.get_parent()
	return null
