extends Control
## 메인 메뉴. 싱글/멀티/덱선택/상점/설정 진입.
## 룩: UiChromeStyle (단색 ScreenBg · MenuSection). GoldLabel = WalletStore 잔액.
## VersionLabel: 연결 시 lobby 버전 · 점검 중 · 오프라인.

const POPUP_SHELL_SCENE := preload("res://scenes/ui/shell/popup_shell.tscn")

@export var chrome_style: UiChromeStyle

@onready var _gold_label: Label = $HBoxContainer/GoldSection/GoldLabel
@onready var _player_badge: PlayerBadge = $PlayerBadge as PlayerBadge
@onready var _version_label: Label = $VersionLabel

var _exit_popup: PopupShell
var _notice_popup: PopupShell


## 크롬 적용 · 메타 동기 대기 후 골드 표시 · 종료 확인 팝업 준비.
func _ready() -> void:
	_apply_ui_chrome()
	_setup_player_badge()
	_exit_popup = POPUP_SHELL_SCENE.instantiate() as PopupShell
	add_child(_exit_popup)
	if _exit_popup.has_method("apply_chrome"):
		_exit_popup.call("apply_chrome", chrome_style)
	_notice_popup = POPUP_SHELL_SCENE.instantiate() as PopupShell
	add_child(_notice_popup)
	if _notice_popup.has_method("apply_chrome"):
		_notice_popup.call("apply_chrome", chrome_style)
	if not MetaSync.boot_done:
		await MetaSync.sync_finished
	_refresh_gold_label()
	_refresh_player_badge()
	_refresh_version_label()
	if not MetaSync.sync_finished.is_connected(_on_meta_sync_finished):
		MetaSync.sync_finished.connect(_on_meta_sync_finished)
	if not MetaSync.online_gate_changed.is_connected(_on_online_gate_changed):
		MetaSync.online_gate_changed.connect(_on_online_gate_changed)


## 메타 동기 후 골드 · 버전 라벨.
func _on_meta_sync_finished(_ok: bool, _message: String) -> void:
	_refresh_gold_label()
	_refresh_player_badge()
	_refresh_version_label()


func _on_online_gate_changed() -> void:
	_refresh_version_label()


## 온라인/상점 차단 안내 팝업 (버튼 진입 시에만).
func _show_block_popup(message: String) -> void:
	if _notice_popup == null:
		return
	var copy := chrome_style.get_copy()
	var title := "점검 중" if MetaSync.block_kind == "maintenance" else "서버 오류"
	var body := message
	if body.is_empty():
		body = "서버 오류"
	_notice_popup.configure_confirm(
		title,
		body,
		Callable(),
		Callable(),
		copy.confirm,
		copy.cancel,
		{"confirm_only": true, "full_dimmer": true}
	)
	_notice_popup.open()


## Cyan 크롬을 입힌다 (레이아웃 유지).
func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)
	if _player_badge:
		_player_badge.apply_chrome(chrome_style)


func _setup_player_badge() -> void:
	if _player_badge == null:
		return
	_refresh_player_badge()


## 스택에서 다시 보일 때 health+meta 재점검 · 골드 · 버전 갱신.
func on_menu_shown() -> void:
	await MetaSync.refresh_async(true, false)
	_refresh_gold_label()
	_refresh_player_badge()
	_refresh_version_label()


## WalletStore 잔액으로 GoldLabel을 갱신한다.
func _refresh_gold_label() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "gold: %d" % WalletStore.get_gold()


## health 상태에 따라 우하단 버전 라벨을 갱신한다.
func _refresh_version_label() -> void:
	if _version_label == null:
		return
	if MetaSync.block_kind == "maintenance":
		_version_label.text = "점검 중"
	elif MetaSync.block_kind == "server_error" or MetaSync.lobby_version.is_empty():
		_version_label.text = "오프라인"
	else:
		_version_label.text = MetaSync.lobby_version


func _refresh_player_badge() -> void:
	if _player_badge == null:
		return
	if not AccountService.is_bootstrapped():
		_player_badge.visible = false
		return
	_player_badge.visible = true
	_player_badge.configure(
		AccountService.display_name(),
		AccountService.profile_icon_id(),
		true
	)
	if chrome_style:
		_player_badge.apply_chrome(chrome_style)


func _on_player_badge_pressed() -> void:
	PlayerProfileScreen.open(get_tree())


## 싱글 준비 화면으로 이동한다.
func _on_singleplay_button_pressed() -> void:
	MenuHost.push_file("res://scenes/screen/single_play_prepare_screen.tscn")


## 온라인 준비 화면으로 이동한다. 서버 불가·점검이면 팝업.
func _on_multiplay_button_pressed() -> void:
	await MetaSync.refresh_async(false, true)
	if not MetaSync.can_use_online():
		_show_block_popup(MetaSync.block_message)
		return
	MenuHost.push_file("res://scenes/screen/online_prepare_screen.tscn")


## 덱 선택 화면으로 이동한다. meta pull로 ops 부여 등 반영.
func _on_deck_button_pressed() -> void:
	await MetaSync.refresh_async(true, true)
	DeckSelectScreen.open(get_tree())


## 상점 화면으로 이동한다. 서버 불가·점검·메타 불가면 팝업.
func _on_shop_button_pressed() -> void:
	await MetaSync.refresh_async(true, true)
	if not MetaSync.can_use_shop():
		var msg := MetaSync.block_message
		if msg.is_empty():
			msg = "서버 오류 (DB)"
		_show_block_popup(msg)
		return
	MenuHost.push_file("res://scenes/screen/shop_screen.tscn")


## 설정 화면(G2)으로 이동한다.
func _on_settings_button_pressed() -> void:
	MenuHost.push_file("res://scenes/screen/settings_screen.tscn")


## 패치노트 화면으로 이동한다.
func _on_patch_note_button_pressed() -> void:
	MenuHost.push_file("res://scenes/screen/patch_notes_screen.tscn")


## 종료 확인 팝업을 연다. 확인 시 quit.
func _on_exit_button_pressed() -> void:
	if _exit_popup == null:
		get_tree().quit()
		return
	var copy := chrome_style.get_copy()
	_exit_popup.configure_confirm(
		"종료",
		"게임을 종료할까요?",
		_quit_game,
		Callable(),
		"종료",
		copy.cancel,
		{"full_dimmer": true}
	)
	_exit_popup.open()


## 앱을 종료한다.
func _quit_game() -> void:
	get_tree().quit()
