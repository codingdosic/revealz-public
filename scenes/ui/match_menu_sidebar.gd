extends PanelContainer
## 인게임 좌측 메뉴. 설정 / 재시작(싱글만) / 항복.
## 틀·닫기=SidebarShell. 배경·테두리=이 패널. 문구=UiCopy.

signal settings_pressed
signal restart_pressed
signal surrender_pressed

@export var chrome_style: UiChromeStyle

@onready var _title_label: Label = $Margin/VBox/TitleLabel
@onready var _restart_button: Button = $Margin/VBox/RestartButton
@onready var _settings_button: Button = $Margin/VBox/SettingsButton
@onready var _surrender_button: Button = $Margin/VBox/SurrenderButton


## 시작 시 숨김 · 크롬 적용 · 버튼 시그널 연결.
func _ready() -> void:
	visible = false
	apply_chrome(chrome_style)
	_settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	_surrender_button.pressed.connect(func() -> void: surrender_pressed.emit())


## 크롬 팔레트·문구로 패널·제목·메뉴 버튼을 갱신한다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	chrome_style.apply_panel(self)
	chrome_style.apply_title_label(_title_label)
	chrome_style.apply_buttons([_settings_button, _restart_button, _surrender_button])
	var copy := chrome_style.get_copy()
	_title_label.text = copy.match_menu_title
	_settings_button.text = copy.match_menu_settings
	_restart_button.text = copy.match_menu_restart
	_surrender_button.text = copy.match_menu_surrender


## 싱글이면 재시작 표시, 온라인이면 숨김.
func configure_for_singleplayer(is_single: bool) -> void:
	_restart_button.visible = is_single


## 메뉴를 연다.
func show_menu() -> void:
	visible = true
	SidebarContentUtil.sync_shell(self, true)


## 메뉴를 닫는다. 패널 visible은 셸 close 연출 후에 꺼진다.
func hide_menu() -> void:
	var shell := SidebarContentUtil.find_shell(self)
	if shell != null and shell.visible:
		shell.call("close", "content")
		return
	visible = false


## 토글. 열린 뒤 true.
func toggle_menu() -> bool:
	if visible:
		hide_menu()
		return false
	show_menu()
	return true
