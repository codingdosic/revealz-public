extends CanvasLayer
## 인게임 UI 허브. SelectionPresenter ↔ 공개 API만 유지 (위젯 private 직접 호출 금지).
## L4a: 최소화 복귀는 MinimizeHandle. 셸 상수·정책은 scenes/ui/shell/.
## TargetListSheet(BottomSheetShell)+TargetSelectBar · FieldTargetPrompt(FIELD) · MatchVersusOverlay(승패).
##
## 튜닝:
## - 사이드바 폭: UiShellConstants.SIDEBAR_WIDTH
## - 존 툴팁 오프셋: CURSOR_TOOLTIP_OFFSET
## - 최소화 핸들 위치: UiShellConstants.MINIMIZE_HANDLE_OFFSET_*
## - UI 크롬(패널·버튼·토스트·문구): chrome_style → ui_chrome_cyan.tres (+ copy)

const CURSOR_TOOLTIP_OFFSET := Vector2(16, 20)
const ZONE_TOOLTIP_MASK := (
	GameConstants.COLLISION_LAYER_DECK
	| GameConstants.COLLISION_LAYER_GRAVEYARD
	| GameConstants.COLLISION_LAYER_ZONE_TOOLTIP
)

## 인게임 UI 통일 크롬. 인스펙터에서 .tres 교체·조색. null 이면 cyan 기본.
@export var chrome_style: UiChromeStyle

## ContentSlot 자식이 에디터에서 빠질 수 있어 런타임 폴백 마운트용.
const _CARD_INFO_SCENE := preload("res://scenes/ui/card_info_sidebar.tscn")
const _MATCH_MENU_SCENE := preload("res://scenes/ui/match_menu_sidebar.tscn")
const _ZONE_BROWSE_SCENE := preload("res://scenes/ui/zone_browse_sidebar.tscn")
const _EFFECT_DIALOG_SCENE := preload("res://scenes/ui/effect_dialog_panel.tscn")
const _EFFECT_NOTICE_SCENE := preload("res://scenes/ui/effect_notice_panel.tscn")
const _TARGET_SELECT_SCENE := preload("res://scenes/ui/target_select_bar.tscn")

@onready var _card_info_shell: Control = get_node_or_null("CardInfoShell")
@onready var _card_sidebar: PanelContainer = get_node_or_null("CardInfoShell/ContentSlot/CardInfoSidebar")
@onready var _match_menu_dimmer: ColorRect = get_node_or_null("MatchMenuDimmer")
@onready var _match_menu_shell: Control = get_node_or_null("MatchMenuShell")
@onready var _match_menu_sidebar: PanelContainer = get_node_or_null("MatchMenuShell/ContentSlot/MatchMenuSidebar")
@onready var _settings_overlay: Control = get_node_or_null("SettingsOverlayHost")
@onready var _settings_overlay_dimmer: ColorRect = get_node_or_null("SettingsOverlayHost/Dimmer")
@onready var _settings_screen: Control = get_node_or_null("SettingsOverlayHost/SettingsScreen")
@onready var _settings_button: Button = get_node_or_null("SettingsButton")
@onready var _zone_browse_shell: Control = get_node_or_null("ZoneBrowseShell")
@onready var _zone_browse_sidebar: PanelContainer = get_node_or_null("ZoneBrowseShell/ContentSlot/ZoneBrowseSidebar")
@onready var _zone_tooltip_panel: PanelContainer = get_node_or_null("ZoneCountTooltip")
@onready var _zone_tooltip_label: Label = get_node_or_null("ZoneCountTooltip/Label")
@onready var _effect_dialog_shell: Control = get_node_or_null("EffectDialogShell")
@onready var _effect_dialog: PanelContainer = get_node_or_null("EffectDialogShell/ContentSlot/EffectDialogPanel")
## L4a: 최소화 복귀 핸들 (구 EffectDialogRestoreButton).
@onready var _minimize_handle: Control = get_node_or_null("MinimizeHandle")
@onready var _target_list_sheet: Control = get_node_or_null("TargetListSheet")
@onready var _target_select_bar: Control = get_node_or_null("TargetListSheet/Margin/VBox/ContentSlot/TargetSelectBar")
@onready var _field_target_prompt: Control = get_node_or_null("FieldTargetPrompt")
@onready var _match_versus_overlay: MatchVersusOverlay = get_node_or_null("MatchVersusOverlay") as MatchVersusOverlay
var _phase_button_turn_side: int = -2
@onready var _effect_notice_shell: Control = get_node_or_null("EffectNoticeShell")
@onready var _effect_notice: PanelContainer = get_node_or_null("EffectNoticeShell/ContentSlot/EffectNoticePanel")
@onready var _phase_toast: Control = get_node_or_null("PhaseToast")
@onready var _local_id_badge: PlayerBadge = get_node_or_null("LocalIdBadge") as PlayerBadge
@onready var _opponent_id_badge: PlayerBadge = get_node_or_null("OpponentIdBadge") as PlayerBadge

var _restore_callback: Callable
var _sidebar_card: Node
var _player_hand: Node
var _effect_manager: EffectManager
var _notice_sidebar_lock: bool = false
var _zone_areas: Array = []
var _field_root: Node2D
var _surrender_dialog_armed: bool = false

enum ZoneBrowseKind { NONE, GRAVEYARD, BANISH, STACK }

var _zone_browse_kind: ZoneBrowseKind = ZoneBrowseKind.NONE
var _zone_browse_side: GameConstants.Side = GameConstants.Side.PLAYER
var _stack_browse_host: Node = null
var _zone_browse_open_grace: bool = false
var _player_graveyard: GraveyardArea
var _opponent_graveyard: GraveyardArea
var _player_banish: Node2D
var _opponent_banish: Node2D
var _active_zone_hover_glow: ZoneHoverGlow


## finish_setup으로 받은 EM의 매치 EffectContext. S3: static instance 대체.
func _effect_context() -> EffectContext:
	if _effect_manager:
		return _effect_manager.context
	return null


## 부트: 셸 마운트 · 크롬 배포 · 매치메뉴 · ID 배지.
func _ready() -> void:
	add_to_group("game_ui_layer")
	_ensure_shell_contents_mounted()
	_reset_shell_boot_visibility()
	if _minimize_handle and _minimize_handle.has_method("hide_handle"):
		_minimize_handle.hide_handle()
	_setup_ui_shells()
	_apply_chrome_style()
	var zone := _get_zone_browse_sidebar()
	if zone and zone.has_method("bind_game_ui"):
		zone.bind_game_ui(self)
	var bar := _get_target_select_bar()
	if bar and bar.has_method("bind_game_ui"):
		bar.bind_game_ui(self)
	if _zone_tooltip_panel:
		_zone_tooltip_panel.visible = false
	_field_root = get_parent() as Node2D
	if _match_versus_overlay and _match_versus_overlay.has_signal("confirmed"):
		_match_versus_overlay.confirmed.connect(_on_game_over_confirmed)
	_setup_match_menu()
	refresh_player_id_labels()
	_publish_display_name_for_match()


## chrome_style(또는 기본 cyan)을 인게임 UI 위젯에 배포한다.
func _apply_chrome_style() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	var chrome := chrome_style
	if _phase_toast and _phase_toast.has_method("apply_chrome"):
		_phase_toast.call("apply_chrome", chrome)
	if _match_menu_sidebar and _match_menu_sidebar.has_method("apply_chrome"):
		_match_menu_sidebar.call("apply_chrome", chrome)
	if _card_sidebar and _card_sidebar.has_method("apply_chrome"):
		_card_sidebar.call("apply_chrome", chrome)
	if _zone_browse_sidebar and _zone_browse_sidebar.has_method("apply_chrome"):
		_zone_browse_sidebar.call("apply_chrome", chrome)
	if _effect_dialog and _effect_dialog.has_method("apply_chrome"):
		_effect_dialog.call("apply_chrome", chrome)
	if _effect_notice and _effect_notice.has_method("apply_chrome"):
		_effect_notice.call("apply_chrome", chrome)
	if _match_versus_overlay:
		_match_versus_overlay.apply_chrome(chrome)
	if _effect_dialog_shell and _effect_dialog_shell.has_method("apply_chrome"):
		_effect_dialog_shell.call("apply_chrome", chrome)
	if _effect_notice_shell and _effect_notice_shell.has_method("apply_chrome"):
		_effect_notice_shell.call("apply_chrome", chrome)
	if _target_list_sheet and _target_list_sheet.has_method("apply_chrome"):
		_target_list_sheet.call("apply_chrome", chrome)
	if _field_target_prompt and _field_target_prompt.has_method("apply_chrome"):
		_field_target_prompt.call("apply_chrome", chrome)
	if _minimize_handle and _minimize_handle.has_method("apply_chrome"):
		_minimize_handle.call("apply_chrome", chrome)
	if _settings_button:
		chrome.apply_button(_settings_button)
	if _zone_tooltip_panel:
		chrome.apply_panel(_zone_tooltip_panel)
	if _local_id_badge:
		_local_id_badge.set_layout_mirrored(false)
		_local_id_badge.apply_chrome(chrome)
	if _opponent_id_badge:
		_opponent_id_badge.set_layout_mirrored(true)
		_opponent_id_badge.apply_chrome(chrome)
	_apply_line_power_chrome(chrome)
	if _zone_tooltip_label:
		chrome.apply_muted_label(_zone_tooltip_label)


## 셸 ContentSlot 자식이 tscn에서 빠졌을 때 런타임으로 복구.
## (인스턴스 하위 editable 자식이 에디터 저장 시 유실되는 경우 대비)
func _ensure_shell_contents_mounted() -> void:
	_card_sidebar = _mount_into_slot(
		_card_info_shell, "ContentSlot", "CardInfoSidebar", _CARD_INFO_SCENE, _card_sidebar
	) as PanelContainer
	_match_menu_sidebar = _mount_into_slot(
		_match_menu_shell, "ContentSlot", "MatchMenuSidebar", _MATCH_MENU_SCENE, _match_menu_sidebar
	) as PanelContainer
	_zone_browse_sidebar = _mount_into_slot(
		_zone_browse_shell, "ContentSlot", "ZoneBrowseSidebar", _ZONE_BROWSE_SCENE, _zone_browse_sidebar
	) as PanelContainer
	_effect_dialog = _mount_into_slot(
		_effect_dialog_shell, "ContentSlot", "EffectDialogPanel", _EFFECT_DIALOG_SCENE, _effect_dialog
	) as PanelContainer
	_effect_notice = _mount_into_slot(
		_effect_notice_shell, "ContentSlot", "EffectNoticePanel", _EFFECT_NOTICE_SCENE, _effect_notice
	) as PanelContainer
	_target_select_bar = _mount_into_slot(
		_target_list_sheet, "Margin/VBox/ContentSlot", "TargetSelectBar", _TARGET_SELECT_SCENE, _target_select_bar
	)
	# 셸 _ready 시 슬롯이 비어 있었으면 _bound_content 재바인딩.
	for shell in [_card_info_shell, _match_menu_shell, _zone_browse_shell, _effect_dialog_shell, _effect_notice_shell]:
		if shell and shell.has_method("_prepare_mounted_content"):
			shell.call("_prepare_mounted_content")


func _mount_into_slot(
	shell: Node,
	slot_path: String,
	child_name: String,
	packed: PackedScene,
	existing: Node
) -> Node:
	if existing and is_instance_valid(existing):
		return existing
	if shell == null or packed == null:
		return existing
	var slot := shell.get_node_or_null(slot_path) as Control
	if slot == null:
		push_warning("GameUILayer: missing slot %s/%s" % [shell.name, slot_path])
		return existing
	var already := slot.get_node_or_null(child_name)
	if already:
		return already
	var node := packed.instantiate()
	node.name = child_name
	slot.add_child(node)
	if node is Control:
		var c := node as Control
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node


## 부팅 시 셸/딤/오버레이가 입력을 가로채지 않게 강제 숨김.
func _reset_shell_boot_visibility() -> void:
	for node in [
		_card_info_shell,
		_match_menu_shell,
		_zone_browse_shell,
		_effect_dialog_shell,
		_effect_notice_shell,
		_target_list_sheet,
		_field_target_prompt,
		_match_versus_overlay,
		_settings_overlay,
		_match_menu_dimmer,
	]:
		if node and is_instance_valid(node):
			node.visible = false
	if _card_sidebar:
		_card_sidebar.visible = false
	if _match_menu_sidebar:
		_match_menu_sidebar.visible = false
	if _zone_browse_sidebar:
		_zone_browse_sidebar.visible = false
	if _effect_dialog:
		_effect_dialog.visible = false
	if _effect_notice:
		_effect_notice.visible = false
	# PopupShell ContentSlot 이 숨겨져 있으면 패널을 열어도 안 보임.
	for shell in [_effect_dialog_shell, _effect_notice_shell]:
		if shell == null:
			continue
		var slot := shell.get_node_or_null("ContentSlot") as Control
		if slot:
			slot.visible = true
		var builtin := shell.get_node_or_null("Builtin") as Control
		if builtin:
			builtin.visible = false


## L4a 2차: 셸 배치·모드·dismiss → 콘텐츠 hide 연결.
func _setup_ui_shells() -> void:
	if _card_info_shell and _card_info_shell.has_method("setup"):
		_card_info_shell.call("setup", 0)  # SidebarShell.ShellSide.LEFT
		if _card_info_shell.has_method("get_dismiss_policy"):
			var policy = _card_info_shell.call("get_dismiss_policy")
			if policy:
				policy.is_outside_click_exempt = _is_card_info_outside_click_exempt
		if _card_info_shell.has_signal("closed") and not _card_info_shell.is_connected("closed", _on_card_info_shell_closed):
			_card_info_shell.connect("closed", _on_card_info_shell_closed)
	if _match_menu_shell and _match_menu_shell.has_method("setup"):
		# top_inset 0 — 설정 버튼 영역까지 채움 (열릴 때 버튼 숨김).
		_match_menu_shell.call("setup", 0, -1.0, 0.0)
		if _match_menu_shell.has_signal("closed") and not _match_menu_shell.is_connected("closed", _on_match_menu_shell_closed):
			_match_menu_shell.connect("closed", _on_match_menu_shell_closed)
	if _zone_browse_shell and _zone_browse_shell.has_method("setup"):
		_zone_browse_shell.call("setup", 1)  # RIGHT
		if _zone_browse_shell.has_signal("closed") and not _zone_browse_shell.is_connected("closed", _on_zone_browse_shell_closed):
			_zone_browse_shell.connect("closed", _on_zone_browse_shell_closed)
	if _effect_dialog_shell:
		# 확인/취소·최소화 버튼으로만 닫기 — ESC/우클릭 숨김 시 await가 영구 대기함.
		_effect_dialog_shell.set("dismiss_on_outside_click", false)
		_effect_dialog_shell.set("dismiss_on_right_click", false)
		_effect_dialog_shell.set("dismiss_on_esc", false)
		if _effect_dialog_shell.has_method("use_content_confirm"):
			_effect_dialog_shell.call("use_content_confirm")
		if _effect_dialog_shell.has_signal("closed") and not _effect_dialog_shell.is_connected("closed", _on_effect_dialog_shell_closed):
			_effect_dialog_shell.connect("closed", _on_effect_dialog_shell_closed)
	if _effect_notice_shell and _effect_notice_shell.has_method("use_content_notice"):
		_effect_notice_shell.call("use_content_notice")


func _on_card_info_shell_closed(reason: String) -> void:
	if reason == "content":
		return
	_sidebar_card = null
	if _card_sidebar and _card_sidebar.has_method("hide_sidebar"):
		_card_sidebar.hide_sidebar()


## CardInfo 바깥 클릭 dismiss 제외 — 선택/브라우즈 UI는 클릭이 그대로 전달되어야 함.
func _is_card_info_outside_click_exempt(global_pos: Vector2) -> bool:
	# 필드/슬롯 타겟: 클릭은 프롬프트가 아니라 필드 카드·슬롯. 프롬프트가 떠 있으면
	# 사이드바 outside dismiss가 set_input_as_handled로 EM raycast를 막으므로 전부 면제.
	if _card_sidebar and _card_sidebar.has_method("is_detail_open") and _card_sidebar.is_detail_open():
		return true
	if is_field_target_prompt_visible():
		return true
	var zone := _get_zone_browse_sidebar()
	if zone and zone.visible and _control_contains_mouse(zone, global_pos):
		return true
	if _zone_browse_shell and _zone_browse_shell.visible and _control_contains_mouse(_zone_browse_shell, global_pos):
		return true
	var target_sheet := _get_target_list_sheet()
	if target_sheet and target_sheet.visible and _control_contains_mouse(target_sheet, global_pos):
		return true
	var field_prompt := _get_field_target_prompt()
	if field_prompt and field_prompt.visible and _control_contains_mouse(field_prompt, global_pos):
		return true
	var dialog := get_effect_dialog()
	if dialog and dialog.visible and _control_contains_mouse(dialog, global_pos):
		return true
	if _effect_dialog_shell and _effect_dialog_shell.visible and _control_contains_mouse(_effect_dialog_shell, global_pos):
		return true
	if _minimize_handle and _minimize_handle.visible and _control_contains_mouse(_minimize_handle, global_pos):
		return true
	# 카드 위 클릭: dismiss가 press를 가로채면 prepare_drag가 안 됨.
	# 열고 닫기는 card_manager release 토글이 담당.
	if _raycast_field_card_at(global_pos) != null:
		return true
	return false


func _on_match_menu_shell_closed(reason: String) -> void:
	if reason == "content":
		return
	_close_match_menu(true)


func _on_zone_browse_shell_closed(reason: String) -> void:
	if reason == "content":
		return
	if _zone_browse_kind != ZoneBrowseKind.NONE:
		_zone_browse_kind = ZoneBrowseKind.NONE
		_stack_browse_host = null
	if _zone_browse_sidebar and _zone_browse_sidebar.has_method("hide_sidebar"):
		_zone_browse_sidebar.hide_sidebar()


func _on_effect_dialog_shell_closed(reason: String) -> void:
	if reason == "content":
		return
	# 셸 dismiss로만 닫힌 경우 — 패널 hide + 대기 중이면 cancel로 풀어줌.
	if _effect_dialog and _effect_dialog.visible and _effect_dialog.has_signal("canceled"):
		_effect_dialog.canceled.emit()
	if _effect_dialog and _effect_dialog.has_method("hide_dialog"):
		_effect_dialog.hide_dialog()


func finish_setup(
	effect_manager: EffectManager,
	player_deck: DeckZone,
	opponent_deck: DeckZone,
	player_hand: Node,
	opponent_hand: Node,
	player_graveyard: GraveyardArea,
	opponent_graveyard: GraveyardArea,
	player_life: LifeContainerDisplay,
	opponent_life: LifeContainerDisplay,
	player_banish: Node2D,
	opponent_banish: Node2D,
	opponent_hand_hover: ZoneHoverArea
) -> void:
	_player_hand = player_hand
	setup_zones(
		player_deck,
		opponent_deck,
		opponent_hand,
		player_graveyard,
		opponent_graveyard,
		player_life,
		opponent_life,
		player_banish,
		opponent_banish,
		opponent_hand_hover
	)
	if effect_manager:
		_effect_manager = effect_manager
		effect_manager.bind_game_ui(self)
		if not effect_manager.graveyard_content_changed.is_connected(_on_graveyard_content_changed):
			effect_manager.graveyard_content_changed.connect(_on_graveyard_content_changed)
		if not effect_manager.effect_busy_changed.is_connected(_on_effect_busy_changed):
			effect_manager.effect_busy_changed.connect(_on_effect_busy_changed)
	refresh_turn_indicators()
	refresh_player_id_labels()
	_apply_phase_button_chrome()


## FieldBoardBuilder가 옮긴 PhaseButton + 라인 파워 라벨에 크롬을 입힌다.
func _apply_phase_button_chrome() -> void:
	var chrome := UiChromeStyle.resolve(chrome_style)
	var phase_btn := _find_phase_button()
	if phase_btn:
		phase_btn.clip_text = true
		_phase_button_turn_side = -2
		_refresh_phase_button_turn_chrome()
	_apply_line_power_chrome(chrome)
	_publish_display_name_for_match()


## PhaseButton — UI 자식 우선, 아직 Field에 있으면 그쪽.
func _find_phase_button() -> Button:
	var btn := get_node_or_null("PhaseButton") as Button
	if btn:
		return btn
	var field := get_parent()
	if field:
		return field.get_node_or_null("PhaseButton") as Button
	return null


## 턴 사이드에 따라 Phase 버튼 청/적 크롬 갱신 (사이드 변화 시에만).
func _refresh_phase_button_turn_chrome() -> void:
	var phase_btn := _find_phase_button()
	if phase_btn == null:
		return
	var side := _resolve_phase_button_turn_side()
	if side == _phase_button_turn_side:
		return
	_phase_button_turn_side = side
	UiChromeStyle.resolve(chrome_style).apply_phase_button(phase_btn, side)


## 턴 사이드 소스: EM get_turn_glow_local_side(SETTING/busy) → PhaseManager.active_side.
func _resolve_phase_button_turn_side() -> int:
	if _effect_manager:
		var glow := _effect_manager.get_turn_glow_local_side()
		if glow >= 0:
			return glow
	var field := get_parent()
	if field:
		var pm := field.get_node_or_null("PhaseManager")
		if pm != null and pm.get("active_side") != null:
			return int(pm.active_side)
	return GameConstants.Side.PLAYER


## Field 아래 Left/Center/RightPowerLabel에 대각 챔퍼 패널 적용.
func _apply_line_power_chrome(chrome: UiChromeStyle) -> void:
	if chrome == null:
		return
	var field := get_parent()
	if field == null:
		return
	for node_name in ["LeftPowerLabel", "CenterPowerLabel", "RightPowerLabel"]:
		var panel := field.get_node_or_null(node_name) as PanelContainer
		if panel:
			chrome.apply_power_label(panel)


## 온라인 매치에서 로컬 표시명을 상대에게 보내고, 늦게 도착해도 라벨을 갱신한다.
func _publish_display_name_for_match() -> void:
	var session := GameSession.get_active()
	if session == null or session.play_mode != GameSessionBase.PlayMode.ONLINE:
		return
	if not NetworkManager.is_online():
		return
	NetworkManager.publish_display_name()
	# 상대 publish가 한 템포 늦을 수 있어 짧게 재시도.
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		NetworkManager.publish_display_name()
		refresh_player_id_labels()
	)


## 좌하단 자신 / 우상단 상대 표시명·아이콘 갱신. 인게임 배지는 표시 전용(클릭 불가).
func refresh_player_id_labels() -> void:
	var local_id := ""
	var local_icon := AccessoryCatalog.DEFAULT_ICON_ID
	var opp_id := "COM"
	var opp_icon := AccessoryCatalog.DEFAULT_ICON_ID
	if AccountService.is_bootstrapped():
		local_id = AccountService.display_name()
		local_icon = AccessoryCatalog.resolve_icon_id(AccountService.profile_icon_id())
	var session := GameSession.get_active()
	if session:
		session.sync_local_display_name()
		session.sync_local_profile_icon()
		if not session.local_display_name.is_empty():
			local_id = session.local_display_name.strip_edges()
		if not session.local_profile_icon_id.is_empty():
			local_icon = AccessoryCatalog.resolve_icon_id(session.local_profile_icon_id)
		if session.play_mode == GameSessionBase.PlayMode.ONLINE:
			opp_id = session.opponent_display_name.strip_edges()
			if opp_id.is_empty():
				opp_id = "…"
			if not session.opponent_profile_icon_id.is_empty():
				opp_icon = AccessoryCatalog.resolve_icon_id(session.opponent_profile_icon_id)
		elif not session.opponent_display_name.is_empty():
			opp_id = session.opponent_display_name.strip_edges()
			if not session.opponent_profile_icon_id.is_empty():
				opp_icon = AccessoryCatalog.resolve_icon_id(session.opponent_profile_icon_id)
	if _local_id_badge:
		_local_id_badge.visible = true
		_local_id_badge.configure(
			local_id if not local_id.is_empty() else "—",
			local_icon,
			false
		)
	if _opponent_id_badge:
		_opponent_id_badge.visible = true
		_opponent_id_badge.configure(
			opp_id,
			opp_icon,
			false
		)


func _get_zone_browse_sidebar() -> PanelContainer:
	if _zone_browse_sidebar:
		return _zone_browse_sidebar
	return get_node_or_null("ZoneBrowseShell/ContentSlot/ZoneBrowseSidebar") as PanelContainer


func _get_target_select_bar() -> Control:
	if _target_select_bar:
		return _target_select_bar
	return get_node_or_null("TargetListSheet/Margin/VBox/ContentSlot/TargetSelectBar") as Control


func _get_target_list_sheet() -> Control:
	if _target_list_sheet:
		return _target_list_sheet
	return get_node_or_null("TargetListSheet") as Control


func _get_field_target_prompt() -> Control:
	if _field_target_prompt:
		return _field_target_prompt
	return get_node_or_null("FieldTargetPrompt") as Control


func setup_zones(
	player_deck: DeckZone,
	opponent_deck: DeckZone,
	opponent_hand: Node,
	player_graveyard: GraveyardArea,
	opponent_graveyard: GraveyardArea,
	player_life: LifeContainerDisplay,
	opponent_life: LifeContainerDisplay,
	player_banish: Node2D,
	opponent_banish: Node2D,
	opponent_hand_hover: ZoneHoverArea
) -> void:
	_player_graveyard = player_graveyard
	_opponent_graveyard = opponent_graveyard
	_player_banish = player_banish
	_opponent_banish = opponent_banish
	_zone_areas.clear()
	_register_zone_area(player_deck.get_tooltip_area(), func() -> int: return player_deck.deck.size())
	_register_zone_area(
		player_graveyard.click_area,
		_grave_count_fn.bind(GameConstants.Side.PLAYER),
		player_graveyard.hover_glow
	)
	_register_zone_area(player_life.get_tooltip_area(), func() -> int: return player_deck.get_life_count())
	_register_banish_zone_area(player_banish)
	_register_zone_area(opponent_hand_hover, func() -> int: return opponent_hand.get_hand_size())
	_register_zone_area(opponent_deck.get_tooltip_area(), func() -> int: return opponent_deck.deck.size())
	_register_zone_area(
		opponent_graveyard.click_area,
		_grave_count_fn.bind(GameConstants.Side.OPPONENT),
		opponent_graveyard.hover_glow
	)
	_register_zone_area(opponent_life.get_tooltip_area(), func() -> int: return opponent_deck.get_life_count())
	_register_banish_zone_area(opponent_banish)


func _register_banish_zone_area(banish: Node2D) -> void:
	if banish is BanishArea and banish.click_area:
		var zone := banish as BanishArea
		_register_zone_area(
			zone.click_area,
			_banish_count_fn.bind(zone.owner_side),
			zone.hover_glow
		)
	elif banish.has_method("get_tooltip_area"):
		_register_zone_area(banish.get_tooltip_area(), func() -> int: return 0)


func _register_zone_area(
	area: Area2D,
	count_fn: Callable,
	hover_glow: ZoneHoverGlow = null
) -> void:
	if area == null or not count_fn.is_valid():
		return
	_zone_areas.append({"area": area, "count_fn": count_fn, "hover_glow": hover_glow})


## 존 툴팁용 묘지 장수. EM.context presenter 우선, 없으면 덱 리스트.
func _grave_count_fn(side: GameConstants.Side) -> int:
	var ctx := _effect_context()
	if ctx:
		var nodes: Array = ctx.get_graveyard_card_nodes(side)
		if not nodes.is_empty():
			return nodes.size()
		var deck := ctx.get_deck(side)
		return deck.graveyard.size()
	return 0


## 존 툴팁용 밴시 장수. EM.context presenter 우선, 없으면 덱 리스트.
func _banish_count_fn(side: GameConstants.Side) -> int:
	var ctx := _effect_context()
	if ctx:
		var nodes: Array = ctx.get_banishzone_card_nodes(side)
		if not nodes.is_empty():
			return nodes.size()
		var deck := ctx.get_deck(side)
		return deck.banishzone.size()
	return 0


func _process(_delta: float) -> void:
	_poll_zone_tooltip()
	if _zone_tooltip_panel.visible:
		_zone_tooltip_panel.global_position = get_viewport().get_mouse_position() + CURSOR_TOOLTIP_OFFSET
	if _zone_browse_open_grace:
		_zone_browse_open_grace = false


func _poll_zone_tooltip() -> void:
	if _field_root == null or _zone_areas.is_empty():
		_zone_tooltip_panel.visible = false
		_set_zone_hover_glow(null)
		return

	var space_state := _field_root.get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = _field_root.get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = ZONE_TOOLTIP_MASK

	var hits := space_state.intersect_point(parameters, 32)
	for hit in hits:
		var collider: Object = hit.collider
		for entry in _zone_areas:
			var area: Area2D = entry.area
			if _collider_belongs_to_area(collider, area):
				_zone_tooltip_label.text = "%d장" % int(entry.count_fn.call())
				_zone_tooltip_panel.visible = true
				_set_zone_hover_glow(entry.get("hover_glow") as ZoneHoverGlow)
				return

	_zone_tooltip_panel.visible = false
	_set_zone_hover_glow(null)


func _set_zone_hover_glow(glow: ZoneHoverGlow) -> void:
	if _active_zone_hover_glow == glow:
		return
	if _active_zone_hover_glow != null and is_instance_valid(_active_zone_hover_glow):
		_active_zone_hover_glow.set_highlighted(false)
	_active_zone_hover_glow = glow
	if glow != null and is_instance_valid(glow):
		glow.set_highlighted(true)


func _collider_belongs_to_area(collider: Object, area: Area2D) -> bool:
	if collider == null or area == null:
		return false
	var node: Node = collider as Node
	while node:
		if node == area:
			return true
		node = node.get_parent()
	return false


func _on_effect_busy_changed(_busy: bool) -> void:
	refresh_turn_indicators()


func refresh_turn_indicators() -> void:
	_refresh_phase_button_turn_chrome()

	if _effect_notice == null or _effect_manager == null:
		return

	var notice: Dictionary = _effect_manager.get_opponent_effect_notice()
	if notice.get("visible", false):
		_effect_notice.show_notice(
			String(notice.get("card_name", "")),
			String(notice.get("trigger", ""))
		)
		var notice_card: Node = notice.get("card")
		if (
			notice_card
			and CardInfoRules.is_sidebar_eligible(notice_card)
			and not _effect_manager.blocks_sidebar()
			and not is_pointer_over_blocking_ui()
		):
			var dialog := get_effect_dialog()
			if dialog == null or not dialog.visible:
				if not _notice_sidebar_lock:
					_notice_sidebar_lock = true
				show_card_info(notice_card)
	else:
		_effect_notice.hide_notice()
		if _notice_sidebar_lock:
			hide_card_sidebar()
			_notice_sidebar_lock = false


## 페이즈 전환 토스트. duration<0 이면 chrome toast_duration.
func show_phase_toast(message: String, duration: float = -1.0) -> void:
	if _phase_toast == null or not _phase_toast.has_method("play"):
		return
	await _phase_toast.call("play", message, duration)


## 토스트 표시 중이면 true (클릭 차단 UI로 취급).
func is_phase_toast_visible() -> bool:
	return _phase_toast != null and _phase_toast.visible


## 카드 정보 사이드바를 연다. 셸 open 은 내용(show_card)이 동기화.
func show_card_info(card: Node) -> void:
	if not CardInfoRules.is_sidebar_eligible(card):
		return
	_close_match_menu(false)
	_sidebar_card = card
	if _card_sidebar == null or not _card_sidebar.has_method("show_card"):
		push_warning("GameUILayer: CardInfoSidebar missing")
		return
	_card_sidebar.show_card(card)
	_refresh_stack_browse_for_card(card)


func toggle_card_info(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		hide_card_sidebar()
		return
	if not CardInfoRules.is_sidebar_eligible(card):
		hide_card_sidebar()
		return
	if _sidebar_card == card and is_card_sidebar_visible():
		hide_card_sidebar()
	else:
		show_card_info(card)


## 카드 정보 사이드바를 닫는다. 셸 close 는 내용(hide_sidebar)이 동기화.
func hide_card_sidebar() -> void:
	_sidebar_card = null
	if _card_sidebar and _card_sidebar.has_method("hide_sidebar"):
		_card_sidebar.hide_sidebar()
	if _zone_browse_kind == ZoneBrowseKind.STACK:
		hide_zone_browse_sidebar()


## 줌 → DetailRoot → 사이드바. 한 단계라도 닫으면 true.
func consume_card_info_back() -> bool:
	if _card_sidebar and _card_sidebar.has_method("consume_back"):
		if _card_sidebar.consume_back():
			return true
	if is_card_sidebar_visible():
		hide_card_sidebar()
		return true
	return false


func should_keep_zone_browse_on_field_card_click(card: Node) -> bool:
	if _zone_browse_kind != ZoneBrowseKind.STACK:
		return false
	if card == null or not is_instance_valid(card):
		return false
	if _stack_browse_host == null or not is_instance_valid(_stack_browse_host):
		return false
	if card == _stack_browse_host:
		return true
	if card.get("stack_host") == _stack_browse_host:
		return true
	return false


func _refresh_stack_browse_for_card(card: Node) -> void:
	var host := _resolve_stack_host_for_display(card)
	if host == null:
		if _zone_browse_kind == ZoneBrowseKind.STACK:
			hide_zone_browse_sidebar()
		return
	var stacks: Array = []
	if host.get("stack_cards"):
		for stacked in host.stack_cards:
			if is_instance_valid(stacked):
				stacks.append(stacked)
	if stacks.is_empty():
		if _zone_browse_kind == ZoneBrowseKind.STACK:
			hide_zone_browse_sidebar()
		return
	_stack_browse_host = host
	_zone_browse_kind = ZoneBrowseKind.STACK
	var title := "%s 스택 (%d장)" % [str(host.card_name), stacks.size()]
	show_zone_browse(title, stacks)


func _resolve_stack_host_for_display(card: Node) -> Node:
	if card == null or not is_instance_valid(card):
		return null
	if card.get("stack_cards") and card.stack_cards.size() > 0:
		return card
	if card.get("stack_host") != null and is_instance_valid(card.stack_host):
		return card.stack_host
	return null


func is_card_sidebar_visible() -> bool:
	# 셸 기준 — 콘텐츠만 visible=true 이고 셸이 닫힌 꼬임은 false.
	if _card_info_shell and _card_info_shell.visible:
		return true
	return false


func should_skip_field_sidebar_toggle() -> bool:
	# 필드/슬롯 타겟 중엔 release 토글이 선택과 싸우지 않게.
	if is_field_target_prompt_visible():
		return true
	var mouse_pos := get_viewport().get_mouse_position()
	return is_pointer_over_blocking_ui_at(mouse_pos)


func is_pointer_over_blocking_ui_at(mouse_pos: Vector2) -> bool:
	if SceneTransition.is_blocking_input():
		return true
	if _match_versus_overlay and _match_versus_overlay.has_method("is_blocking_game_input"):
		if _match_versus_overlay.is_blocking_game_input():
			return true
	if _phase_toast and _phase_toast.visible:
		return true
	if _settings_button and _control_contains_mouse(_settings_button, mouse_pos):
		return true
	if _match_menu_dimmer and _match_menu_dimmer.visible and _control_contains_mouse(_match_menu_dimmer, mouse_pos):
		return true
	if _match_menu_shell and _match_menu_shell.visible and _control_contains_mouse(_match_menu_shell, mouse_pos):
		return true
	if _settings_overlay and _settings_overlay.visible and _control_contains_mouse(_settings_overlay, mouse_pos):
		return true
	if _zone_browse_shell and _zone_browse_shell.visible and _control_contains_mouse(_zone_browse_shell, mouse_pos):
		return true
	var target_sheet := _get_target_list_sheet()
	if target_sheet and target_sheet.visible and _control_contains_mouse(target_sheet, mouse_pos):
		return true
	if _field_target_prompt and _field_target_prompt.visible and _control_contains_mouse(_field_target_prompt, mouse_pos):
		return true
	if _card_info_shell and _card_info_shell.visible and _control_contains_mouse(_card_info_shell, mouse_pos):
		return true
	if _card_sidebar and _card_sidebar.has_method("is_detail_open") and _card_sidebar.is_detail_open():
		return true
	if _effect_dialog_shell and _effect_dialog_shell.visible and _control_contains_mouse(_effect_dialog_shell, mouse_pos):
		return true
	if _minimize_handle and _minimize_handle.visible and _control_contains_mouse(_minimize_handle, mouse_pos):
		return true
	return false


func is_pointer_over_blocking_ui() -> bool:
	return is_pointer_over_blocking_ui_at(get_viewport().get_mouse_position())


func _control_contains_mouse(control: Control, mouse_pos: Vector2) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	return control.get_global_rect().has_point(mouse_pos)


func get_effect_dialog() -> PanelContainer:
	return _effect_dialog


## 최소화 복귀 핸들 표시. SelectionPresenter 호환 API명 유지.
## 위치·크기: MinimizeHandle / UiShellConstants.MINIMIZE_HANDLE_*
func show_effect_restore_button(restore_callback: Callable, label_text: String = "효과 확인") -> void:
	_restore_callback = restore_callback
	if _minimize_handle:
		_minimize_handle.show_handle(restore_callback, label_text)


func hide_effect_restore_button() -> void:
	_restore_callback = Callable()
	if _minimize_handle:
		_minimize_handle.hide_handle()


func set_player_hand_hidden_for_selection(hidden: bool) -> void:
	if hidden:
		_clear_in_game_card_hover()
	if _player_hand and _player_hand.has_method("set_hidden_for_target_select"):
		_player_hand.set_hidden_for_target_select(hidden)


func begin_target_card_selection(
	title_text: String,
	display_cards: Array,
	selectable_cards: Array,
	needed: int,
	show_cancel: bool = false
) -> void:
	set_player_hand_hidden_for_selection(true)
	var bar := _get_target_select_bar()
	if bar and bar.has_method("show_selection"):
		bar.call("show_selection", title_text, display_cards, selectable_cards, needed, show_cancel)


func begin_activation_card_selection(
	title_text: String,
	display_cards: Array,
	selectable_cards: Array
) -> void:
	begin_target_card_selection(title_text, display_cards, selectable_cards, 1, true)


func end_target_card_selection() -> void:
	set_player_hand_hidden_for_selection(false)
	var bar := _get_target_select_bar()
	if bar and bar.has_method("hide_bar"):
		bar.call("hide_bar")
	hide_effect_restore_button()


func minimize_target_select_bar() -> void:
	var bar := _get_target_select_bar()
	if bar and bar.has_method("minimize_bar"):
		bar.call("minimize_bar")


func restore_target_select_bar() -> void:
	var bar := _get_target_select_bar()
	if bar and bar.has_method("restore_bar"):
		bar.call("restore_bar")


func update_target_selection_count(selected: int, needed: int, min_count: int = -1) -> void:
	var bar := _get_target_select_bar()
	if bar and bar.has_method("update_selection_count"):
		bar.call("update_selection_count", selected, needed, min_count)


func set_target_selected_cards(cards: Array) -> void:
	var bar := _get_target_select_bar()
	if bar and bar.has_method("set_selected_cards"):
		bar.call("set_selected_cards", cards)


func hide_target_select_bar() -> void:
	end_target_card_selection()


func is_target_select_bar_visible() -> bool:
	var sheet := _get_target_list_sheet()
	if sheet:
		return sheet.visible
	var bar := _get_target_select_bar()
	return bar != null and bar.visible


func connect_target_select_card(callable: Callable) -> void:
	var bar := _get_target_select_bar()
	if bar == null:
		return
	if bar.has_signal("card_pressed") and not bar.is_connected("card_pressed", callable):
		bar.connect("card_pressed", callable)


func connect_target_select_confirmed(callable: Callable) -> void:
	var bar := _get_target_select_bar()
	if bar == null:
		return
	if bar.has_signal("selection_confirmed") and not bar.is_connected("selection_confirmed", callable):
		bar.connect("selection_confirmed", callable)


func connect_target_select_minimized(callable: Callable) -> void:
	var bar := _get_target_select_bar()
	if bar == null:
		return
	if bar.has_signal("minimized") and not bar.is_connected("minimized", callable):
		bar.connect("minimized", callable)


func connect_target_select_canceled(callable: Callable) -> void:
	var bar := _get_target_select_bar()
	if bar == null:
		return
	if bar.has_signal("selection_canceled") and not bar.is_connected("selection_canceled", callable):
		bar.connect("selection_canceled", callable)


func begin_field_target_selection(
	title_text: String,
	message_text: String,
	needed: int,
	anchor_top: bool = false
) -> void:
	var prompt := _get_field_target_prompt()
	if prompt and prompt.has_method("show_prompt"):
		prompt.call("show_prompt", title_text, message_text, needed, anchor_top)


func end_field_target_selection() -> void:
	var prompt := _get_field_target_prompt()
	if prompt and prompt.has_method("hide_prompt"):
		prompt.call("hide_prompt")
	hide_effect_restore_button()


func minimize_field_target_prompt() -> void:
	var prompt := _get_field_target_prompt()
	if prompt and prompt.has_method("minimize_prompt"):
		prompt.call("minimize_prompt")


func restore_field_target_prompt() -> void:
	var prompt := _get_field_target_prompt()
	if prompt and prompt.has_method("restore_prompt"):
		prompt.call("restore_prompt")


func update_field_target_selection_count(selected: int, needed: int) -> void:
	var prompt := _get_field_target_prompt()
	if prompt and prompt.has_method("update_selection_count"):
		prompt.call("update_selection_count", selected, needed)


func is_field_target_prompt_visible() -> bool:
	var prompt := _get_field_target_prompt()
	return prompt != null and prompt.visible


func connect_field_target_confirmed(callable: Callable) -> void:
	var prompt := _get_field_target_prompt()
	if prompt == null:
		return
	if prompt.has_signal("selection_confirmed") and not prompt.is_connected("selection_confirmed", callable):
		prompt.connect("selection_confirmed", callable)


func connect_field_target_minimized(callable: Callable) -> void:
	var prompt := _get_field_target_prompt()
	if prompt == null:
		return
	if prompt.has_signal("minimized") and not prompt.is_connected("minimized", callable):
		prompt.connect("minimized", callable)


func show_banish_view(side: GameConstants.Side, cards: Array, title_text: String) -> void:
	_zone_browse_kind = ZoneBrowseKind.BANISH
	_zone_browse_side = side
	show_zone_browse(title_text, cards)


func show_graveyard_view(side: GameConstants.Side, cards: Array, title_text: String) -> void:
	_zone_browse_kind = ZoneBrowseKind.GRAVEYARD
	_zone_browse_side = side
	show_zone_browse(title_text, cards)


func show_zone_browse(title_text: String, cards: Array) -> void:
	_zone_browse_open_grace = true
	var zone := _get_zone_browse_sidebar()
	if zone and zone.has_method("show_zone"):
		zone.call("show_zone", title_text, cards)
	if _zone_browse_shell and _zone_browse_shell.has_method("open"):
		_zone_browse_shell.call("open")


func hide_zone_browse_sidebar() -> void:
	_zone_browse_kind = ZoneBrowseKind.NONE
	_stack_browse_host = null
	var zone := _get_zone_browse_sidebar()
	if zone and zone.has_method("hide_sidebar"):
		zone.call("hide_sidebar")


func try_close_zone_browse_on_outside_click() -> void:
	if not is_zone_browse_visible():
		return
	if _zone_browse_open_grace:
		return
	if should_keep_zone_browse_open_on_click():
		return
	hide_zone_browse_sidebar()


func should_keep_zone_browse_open_on_click(mouse_pos: Vector2 = Vector2.INF) -> bool:
	if mouse_pos == Vector2.INF:
		mouse_pos = get_viewport().get_mouse_position()
	var zone := _get_zone_browse_sidebar()
	if zone and zone.visible and _control_contains_mouse(zone, mouse_pos):
		return true
	if _zone_browse_shell and _zone_browse_shell.visible and _control_contains_mouse(_zone_browse_shell, mouse_pos):
		return true
	var target_sheet := _get_target_list_sheet()
	if target_sheet and target_sheet.visible and _control_contains_mouse(target_sheet, mouse_pos):
		return true
	var field_prompt := _get_field_target_prompt()
	if field_prompt and field_prompt.visible and _control_contains_mouse(field_prompt, mouse_pos):
		return true
	var dialog := get_effect_dialog()
	if dialog and dialog.visible and _control_contains_mouse(dialog, mouse_pos):
		return true
	if _minimize_handle and _minimize_handle.visible and _control_contains_mouse(_minimize_handle, mouse_pos):
		return true
	if _zone_browse_kind == ZoneBrowseKind.STACK:
		var field_card := _raycast_field_card_at(mouse_pos)
		if should_keep_zone_browse_on_field_card_click(field_card):
			return true
	if _is_pointer_over_browsed_world_zone():
		return true
	return false


func _raycast_field_card_at(mouse_pos: Vector2) -> Node:
	if _field_root == null:
		return null
	var cm := _field_root.get_node_or_null("CardManager")
	if cm and cm.has_method("raycast_check_for_card"):
		return cm.raycast_check_for_card()
	return null


func _is_pointer_over_browsed_world_zone() -> bool:
	if _field_root == null or _zone_browse_kind == ZoneBrowseKind.NONE:
		return false
	var target_area: Area2D = null
	match _zone_browse_kind:
		ZoneBrowseKind.GRAVEYARD:
			var graveyard: GraveyardArea = (
				_player_graveyard if _zone_browse_side == GameConstants.Side.PLAYER
				else _opponent_graveyard
			)
			if graveyard:
				target_area = graveyard.click_area
		ZoneBrowseKind.BANISH:
			var banish: Node2D = (
				_player_banish if _zone_browse_side == GameConstants.Side.PLAYER
				else _opponent_banish
			)
			if banish is BanishArea:
				target_area = banish.click_area
			elif banish and banish.has_method("get_tooltip_area"):
				target_area = banish.get_tooltip_area()
	if target_area == null:
		return false
	var space_state := _field_root.get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = _field_root.get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = ZONE_TOOLTIP_MASK
	for hit in space_state.intersect_point(parameters, 32):
		if _collider_belongs_to_area(hit.collider, target_area):
			return true
	return false


## 열려 있는 묘지 브라우즈 사이드바를 최신 노드로 갱신한다.
func refresh_zone_browse_for_graveyard(side: GameConstants.Side) -> void:
	if not is_zone_browse_visible():
		return
	if _zone_browse_kind != ZoneBrowseKind.GRAVEYARD or _zone_browse_side != side:
		return
	var cards: Array = []
	var ctx := _effect_context()
	if ctx:
		cards = ctx.get_graveyard_card_nodes(side)
	var zone := _get_zone_browse_sidebar()
	if zone and zone.has_method("refresh_zone"):
		zone.call("refresh_zone", _graveyard_title_for(side), cards)


## 묘지 브라우즈 타이틀(장수 포함)을 만든다.
func _graveyard_title_for(side: GameConstants.Side) -> String:
	var side_label := "플레이어" if side == GameConstants.Side.PLAYER else "상대"
	var ctx := _effect_context()
	if ctx == null:
		return "%s 묘지" % side_label
	var cards: Array = ctx.get_graveyard_card_nodes(side)
	var deck: DeckZone = ctx.get_deck(side)
	var count := cards.size() if not cards.is_empty() else deck.graveyard.size()
	return "%s 묘지 (%d장)" % [side_label, count]


func _on_graveyard_content_changed(side: GameConstants.Side) -> void:
	refresh_zone_browse_for_graveyard(side)


func is_zone_browse_visible() -> bool:
	var zone := _get_zone_browse_sidebar()
	if zone and zone.has_method("is_showing"):
		return bool(zone.call("is_showing"))
	return _zone_browse_shell != null and _zone_browse_shell.visible


## effect_manager 호환 — metadata 정리용 no-op UI
func hide_graveyard_panel() -> void:
	hide_zone_browse_sidebar()


func show_game_over(winner: GameConstants.Side, reason: String = "") -> void:
	_close_match_menu(true)
	hide_card_sidebar()
	hide_zone_browse_sidebar()
	if _match_versus_overlay:
		_match_versus_overlay.show_exit_result(winner, reason)


func _on_game_over_confirmed() -> void:
	SceneTransition.ensure_black()
	SceneTransition.arm_fade_in_after_scene_change(SceneTransition.DEFAULT_FADE_SEC)
	GameSession.return_to_main()


## 설정 버튼·좌측 메뉴·설정 오버레이 연결. 재시작은 싱글만. Dedicated UI 없음.
func _setup_match_menu() -> void:
	var session := GameSession.get_active()
	if not session.has_local_player_input():
		if _settings_button:
			_settings_button.visible = false
		return
	var is_single := session.play_mode == GameSessionBase.PlayMode.LOCAL_SINGLE
	if _match_menu_sidebar and _match_menu_sidebar.has_method("configure_for_singleplayer"):
		_match_menu_sidebar.configure_for_singleplayer(is_single)
	if _match_menu_sidebar:
		if _match_menu_sidebar.has_signal("settings_pressed"):
			_match_menu_sidebar.settings_pressed.connect(_on_match_menu_settings)
		if _match_menu_sidebar.has_signal("restart_pressed"):
			_match_menu_sidebar.restart_pressed.connect(_on_match_menu_restart)
		if _match_menu_sidebar.has_signal("surrender_pressed"):
			_match_menu_sidebar.surrender_pressed.connect(_on_match_menu_surrender)
	if _settings_screen and _settings_screen.has_method("set_embedded"):
		_settings_screen.set_embedded(true)
	if _settings_screen and _settings_screen.has_signal("close_requested"):
		_settings_screen.close_requested.connect(_on_settings_overlay_close_requested)
	if _settings_button:
		_settings_button.pressed.connect(_on_settings_button_pressed)
	if _settings_overlay:
		_settings_overlay.visible = false
	if _match_menu_dimmer:
		_match_menu_dimmer.visible = false
		_match_menu_dimmer.gui_input.connect(_on_match_menu_dimmer_gui_input)
	if _settings_overlay_dimmer:
		_settings_overlay_dimmer.gui_input.connect(_on_match_menu_dimmer_gui_input)


## 설정 버튼: 메뉴 토글. 닫을 때 설정 오버레이도 함께 닫음.
func _on_settings_button_pressed() -> void:
	# 셸 기준 — 콘텐츠만 visible 인 꼬임이면 닫기로 오인되어 "설정 무반응"처럼 보임.
	if is_match_menu_visible():
		_close_match_menu(true)
		return
	if _match_menu_sidebar == null:
		return
	hide_card_sidebar()
	if _match_menu_sidebar.has_method("configure_for_singleplayer"):
		var session := GameSession.get_active()
		_match_menu_sidebar.configure_for_singleplayer(
			session.play_mode == GameSessionBase.PlayMode.LOCAL_SINGLE
		)
	_open_match_menu()


## 좌 메뉴 + 화면 딤을 연다. 설정 버튼은 숨기고 메뉴가 그 높이까지 차지.
func _open_match_menu() -> void:
	_clear_in_game_card_hover()
	if _settings_button:
		_settings_button.visible = false
	if _match_menu_dimmer:
		_match_menu_dimmer.visible = true
	if _match_menu_sidebar:
		_match_menu_sidebar.show_menu()
	if _match_menu_shell and _match_menu_shell.has_method("open"):
		_match_menu_shell.call("open")


## 인게임 카드 호버 잔존 해제.
func _clear_in_game_card_hover() -> void:
	var cm := get_tree().get_first_node_in_group("card_manager") if get_tree() else null
	if cm and cm.has_method("clear_hover_state"):
		cm.clear_hover_state()


## 매치 메뉴가 열려 있는지 (셸 기준).
func is_match_menu_visible() -> bool:
	return _match_menu_shell != null and _match_menu_shell.visible


## 카드 정보 사이드바와 동일: 우클릭·바깥 클릭으로 닫기.
func hide_match_menu() -> void:
	_close_match_menu(true)


## 딤/바깥 영역 클릭 시 메뉴 닫기.
func try_close_match_menu_on_outside_click() -> void:
	if not is_match_menu_visible():
		return
	var mouse_pos := get_viewport().get_mouse_position()
	if _settings_button and _control_contains_mouse(_settings_button, mouse_pos):
		return
	if _match_menu_sidebar and _control_contains_mouse(_match_menu_sidebar, mouse_pos):
		return
	if _settings_overlay and _settings_overlay.visible:
		# 설정 본문(폼) 위 클릭은 유지, 딤 영역만 닫기.
		if _settings_screen and _control_contains_mouse(_settings_screen, mouse_pos):
			var center := _settings_screen.get_node_or_null("CenterContainer") as Control
			if center and _control_contains_mouse(center, mouse_pos):
				return
	_close_match_menu(true)


## 딤mer gui: 좌/우클릭으로 메뉴 닫기.
func _on_match_menu_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_close_match_menu(true)
			get_viewport().set_input_as_handled()


## 좌측 메뉴의 설정 → 우 존 브라우즈만 비우고 가운데에 settings_screen.
func _on_match_menu_settings() -> void:
	_show_settings_overlay()


## 싱글만: 동일 덱으로 로딩 씬 → game 재진입. get_deck_ids_for_side 우선, 없으면 이름 경로.
func _on_match_menu_restart() -> void:
	var session := GameSession.get_active()
	if session.play_mode != GameSessionBase.PlayMode.LOCAL_SINGLE:
		return
	var p_ids := session.get_deck_ids_for_side(GameConstants.Side.PLAYER)
	var o_ids := session.get_deck_ids_for_side(GameConstants.Side.OPPONENT)
	_close_match_menu(true)
	if not p_ids.is_empty():
		var merged_ids: Array[int] = []
		merged_ids.append_array(p_ids)
		merged_ids.append_array(o_ids)
		GameSession.begin_match_loading_ids(merged_ids)
	else:
		var merged: Array[String] = []
		merged.append_array(session.get_deck_names_for_side(GameConstants.Side.PLAYER))
		merged.append_array(session.get_deck_names_for_side(GameConstants.Side.OPPONENT))
		GameSession.begin_match_loading(merged)


## EffectDialogPanel로 항복 확인 후 request_surrender. 확인창 전에 메뉴·딤 닫음.
func _on_match_menu_surrender() -> void:
	var dialog := get_effect_dialog()
	if dialog == null or not dialog.has_method("configure"):
		return
	if dialog.visible or _surrender_dialog_armed:
		return
	_close_match_menu(true)
	_surrender_dialog_armed = true
	_clear_surrender_dialog_signals(dialog)
	var copy := UiChromeStyle.resolve(chrome_style).get_copy()
	dialog.configure(copy.surrender_title, copy.surrender_message, copy.yes, copy.no)
	if dialog.has_signal("confirmed"):
		dialog.confirmed.connect(_on_surrender_confirmed, CONNECT_ONE_SHOT)
	if dialog.has_signal("canceled"):
		dialog.canceled.connect(_on_surrender_canceled, CONNECT_ONE_SHOT)
	dialog.show_dialog()


## 항복 예 → 세션에 패배 요청.
func _on_surrender_confirmed() -> void:
	_surrender_dialog_armed = false
	var dialog := get_effect_dialog()
	_clear_surrender_dialog_signals(dialog)
	if dialog and dialog.has_method("hide_dialog"):
		dialog.hide_dialog()
	_close_match_menu(true)
	GameSession.get_active().request_surrender()


## 항복 아니오.
func _on_surrender_canceled() -> void:
	_surrender_dialog_armed = false
	var dialog := get_effect_dialog()
	_clear_surrender_dialog_signals(dialog)
	if dialog and dialog.has_method("hide_dialog"):
		dialog.hide_dialog()


## 항복 확인/취소 ONE_SHOT 잔여 연결 제거 (이후 효과 발동 예가 항복으로 가는 버그 방지).
func _clear_surrender_dialog_signals(dialog: PanelContainer) -> void:
	if dialog == null:
		return
	if dialog.has_signal("confirmed") and dialog.confirmed.is_connected(_on_surrender_confirmed):
		dialog.confirmed.disconnect(_on_surrender_confirmed)
	if dialog.has_signal("canceled") and dialog.canceled.is_connected(_on_surrender_canceled):
		dialog.canceled.disconnect(_on_surrender_canceled)


## 좌 메뉴는 유지한 채 설정 오버레이를 연다. 우 존 브라우즈 폭만큼 오른쪽을 비움.
func _show_settings_overlay() -> void:
	if _settings_overlay == null:
		return
	_settings_overlay.offset_left = UiShellConstants.SIDEBAR_WIDTH
	var right_pad := 0.0
	if is_zone_browse_visible():
		right_pad = UiShellConstants.SIDEBAR_WIDTH
	_settings_overlay.offset_right = -right_pad
	_settings_overlay.visible = true


## 설정 오버레이만 닫는다 (좌 메뉴는 유지).
func _hide_settings_overlay() -> void:
	if _settings_overlay:
		_settings_overlay.visible = false
	refresh_player_id_labels()


## 임베드 설정 닫기: 사이드바·딤·오버레이를 모두 닫는다.
func _on_settings_overlay_close_requested() -> void:
	_close_match_menu(true)


## 좌 메뉴·딤·설정 오버레이 닫기. 설정 버튼을 다시 표시한다.
func _close_match_menu(_hide_settings: bool = true) -> void:
	if _match_menu_shell and _match_menu_shell.visible and _match_menu_shell.has_method("close"):
		_match_menu_shell.call("close", "content")
	elif _match_menu_sidebar and _match_menu_sidebar.has_method("hide_menu"):
		_match_menu_sidebar.hide_menu()
	if _match_menu_dimmer:
		_match_menu_dimmer.visible = false
	_hide_settings_overlay()
	_restore_settings_button_visibility()


## 로컬 입력이 있는 매치에서만 설정 버튼을 다시 켠다.
func _restore_settings_button_visibility() -> void:
	if _settings_button == null:
		return
	var session := GameSession.get_active()
	_settings_button.visible = session != null and session.has_local_player_input()
