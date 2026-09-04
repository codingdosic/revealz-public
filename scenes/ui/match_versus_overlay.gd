class_name MatchVersusOverlay
extends CanvasLayer
## 매치 VS / 승패 오버레이. 진입 · 종료 공용.
## 씬 트리: Headline / CoinArea / ReasonLabel / BadgeRow / Confirm.

signal confirmed

const ENTRY_DIM_ALPHA := 0.97
const EXIT_DIM_ALPHA := 0.90
const VS_HOLD_SEC := 0.9
const VS_FADE_SEC := 0.45
const COIN_FLIP_COUNT := 5
const COIN_FLIP_HALF_SEC := 0.09
const COIN_RESULT_HOLD_SEC := 2.0
const INTRO_FADE_OUT_SEC := 0.35
const BADGE_SLIDE_SEC := 0.4
const ENTRY_FADE_SEC := 0.75
const HEADLINE_ENTRY_SCALE_START := 0.42
const HEADLINE_ENTRY_SCALE_SEC := 0.65
## 승패 화면 딤 진입 · 확인 후 전체 덮기 페이드.
const EXIT_REVEAL_FADE_SEC := 0.28
const EXIT_CONFIRM_FADE_SEC := 0.35
const COIN_TILT_DEG := -45.0
const COIN_FACE_PLAYER := true
const COIN_FACE_OPPONENT := false
const HEADLINE_DEFEAT_COLOR := Color(0.95, 0.22, 0.26, 1.0)

@export var chrome_style: UiChromeStyle

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _headline: Label = $Root/CenterAnchor/MainVBox/HeadlineLabel
@onready var _coin_pivot: Control = $Root/CenterAnchor/MainVBox/CoinArea/CoinPivot
@onready var _coin_front: PanelContainer = $Root/CenterAnchor/MainVBox/CoinArea/CoinPivot/CoinFront
@onready var _coin_back: PanelContainer = $Root/CenterAnchor/MainVBox/CoinArea/CoinPivot/CoinBack
@onready var _player_badge: PlayerBadge = $Root/CenterAnchor/MainVBox/BadgeRow/PlayerBadgeSlot/PlayerBadge
@onready var _opponent_badge: PlayerBadge = $Root/CenterAnchor/MainVBox/BadgeRow/OpponentBadgeSlot/OpponentBadge
@onready var _reason_label: Label = $Root/CenterAnchor/MainVBox/ReasonLabel
@onready var _confirm_button: Button = $Root/ConfirmAnchor/ConfirmButton

var _coin_showing_player_face := true
var _dimmer_alpha := ENTRY_DIM_ALPHA
var _exit_busy := false


func _ready() -> void:
	layer = 100
	hide_overlay()
	_apply_badge_layout()
	_reset_coin_pivot_transform()
	if _confirm_button and not _confirm_button.pressed.is_connected(_on_confirm_pressed):
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _opponent_badge and _opponent_badge.has_method("set_layout_mirrored"):
		_opponent_badge.set_layout_mirrored(true)
	apply_chrome(chrome_style)


func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	_apply_badge_layout()
	_apply_dimmer_tint()
	_apply_coin_styles()
	if _player_badge:
		_player_badge.apply_chrome(chrome_style)
	if _opponent_badge:
		_opponent_badge.apply_chrome(chrome_style)
	if _reason_label:
		chrome_style.apply_muted_label(_reason_label)
	if _confirm_button:
		chrome_style.apply_button(_confirm_button)
		_confirm_button.text = chrome_style.get_copy().confirm
	if _headline:
		_headline.add_theme_color_override("font_color", chrome_style.accent)


func _apply_headline_color(is_defeat: bool) -> void:
	if _headline == null:
		return
	if is_defeat:
		_headline.add_theme_color_override("font_color", HEADLINE_DEFEAT_COLOR)
	elif chrome_style:
		_headline.add_theme_color_override("font_color", chrome_style.accent)


func hide_overlay() -> void:
	visible = false
	_set_input_block(false)
	set_process(false)


## 오버레이가 떠 있는 동안 Root/Dimmer가 포인터를 먹는다.
func _set_input_block(blocked: bool) -> void:
	if _root:
		_root.mouse_filter = (
			Control.MOUSE_FILTER_STOP if blocked else Control.MOUSE_FILTER_IGNORE
		)
	if _dimmer:
		_dimmer.mouse_filter = (
			Control.MOUSE_FILTER_STOP if blocked else Control.MOUSE_FILTER_IGNORE
		)


## 인게임 InputManager/CardManager가 아래 씬 입력을 막을지 판별.
func is_blocking_game_input() -> bool:
	return visible


func _apply_badge_layout() -> void:
	var badge_size := Vector2(PlayerBadge.BADGE_WIDTH, PlayerBadge.BADGE_HEIGHT)
	for badge in [_player_badge, _opponent_badge]:
		if badge == null:
			continue
		badge.custom_minimum_size = badge_size
		badge.size = badge_size


func _apply_dimmer_tint() -> void:
	if _dimmer == null or chrome_style == null:
		return
	var base := chrome_style.screen_bg
	_dimmer.color = Color(base.r, base.g, base.b, _dimmer_alpha)


func _apply_coin_styles() -> void:
	if chrome_style == null:
		return
	_apply_coin_panel_style(_coin_front, chrome_style.cell_border_player)
	_apply_coin_panel_style(_coin_back, chrome_style.cell_border_opponent)


func _apply_coin_panel_style(panel: PanelContainer, face_color: Color) -> void:
	if panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = face_color
	style.border_color = chrome_style.panel_border
	style.set_border_width_all(int(maxi(chrome_style.panel_border_width, 1.0)))
	style.set_corner_radius_all(40)
	panel.add_theme_stylebox_override("panel", style)


func _reset_coin_pivot_transform() -> void:
	if _coin_pivot == null:
		return
	_coin_pivot.rotation = deg_to_rad(COIN_TILT_DEG)
	_coin_pivot.scale = Vector2.ONE
	_coin_pivot.modulate = Color(1, 1, 1, 1)


func _badge_offscreen_x(is_player: bool) -> float:
	var vw := get_viewport().get_visible_rect().size.x
	return -vw if is_player else vw


func _snap_badges_offscreen() -> void:
	if _player_badge:
		_player_badge.position = Vector2(_badge_offscreen_x(true), 0.0)
		_player_badge.modulate.a = 1.0
	if _opponent_badge:
		_opponent_badge.position = Vector2(_badge_offscreen_x(false), 0.0)
		_opponent_badge.modulate.a = 1.0


func _snap_badges_rest() -> void:
	if _player_badge:
		_player_badge.position = Vector2.ZERO
		_player_badge.modulate.a = 1.0
	if _opponent_badge:
		_opponent_badge.position = Vector2.ZERO
		_opponent_badge.modulate.a = 1.0


## GameSession 표시명·아이콘으로 배지를 채운다.
func bind_badges_from_session() -> void:
	var local_id := "—"
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
	if _player_badge:
		_player_badge.configure(local_id, local_icon, false)
	if _opponent_badge:
		_opponent_badge.configure(opp_id, opp_icon, false)
	_apply_badge_layout()


## 진입: 배지 슬라이드인 + VS → 코인 플립 → 선후공 안내 → 슬라이드아웃.
func play_entry_intro(local_first: GameConstants.Side) -> void:
	_prepare_entry_visuals()
	bind_badges_from_session()
	_dimmer_alpha = ENTRY_DIM_ALPHA
	_apply_dimmer_tint()
	_snap_badges_offscreen()
	visible = true
	set_process(false)
	_set_input_block(true)
	if _dimmer:
		_dimmer.modulate.a = 0.0

	await _play_entry_reveal()
	await get_tree().create_timer(VS_HOLD_SEC).timeout
	await _fade_headline_to_blank()
	await _play_coin_toss(local_first)
	_set_reason_text(build_turn_order_message(local_first))
	await get_tree().create_timer(COIN_RESULT_HOLD_SEC).timeout
	await _fade_out_intro()
	hide_overlay()


## 인게임 종료: VICTORY/DEFEAT + 사유 + 확인. 배지 슬라이드인.
func show_exit_result(winner: GameConstants.Side, reason: String = "") -> void:
	_exit_busy = false
	var is_victory := winner == GameConstants.Side.PLAYER
	_prepare_exit_visuals(is_victory, reason)
	bind_badges_from_session()
	_dimmer_alpha = EXIT_DIM_ALPHA
	_apply_dimmer_tint()
	_snap_badges_offscreen()
	visible = true
	_set_input_block(true)
	if _dimmer:
		_dimmer.modulate.a = 0.0
	if _confirm_button:
		_confirm_button.disabled = false
	await _play_exit_reveal()


func show_result(winner: GameConstants.Side, reason: String = "") -> void:
	show_exit_result(winner, reason)


func hide_result() -> void:
	hide_overlay()


func _play_entry_reveal() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	if _dimmer:
		tw.tween_property(_dimmer, "modulate:a", 1.0, ENTRY_FADE_SEC)
	if _player_badge:
		tw.tween_property(_player_badge, "position:x", 0.0, BADGE_SLIDE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _opponent_badge:
		tw.tween_property(_opponent_badge, "position:x", 0.0, BADGE_SLIDE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _headline:
		tw.tween_property(_headline, "scale", Vector2.ONE, HEADLINE_ENTRY_SCALE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_headline, "modulate:a", 1.0, HEADLINE_ENTRY_SCALE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished


func _snap_headline_entry_hidden() -> void:
	if _headline == null:
		return
	_headline.pivot_offset = _headline.custom_minimum_size * 0.5
	_headline.scale = Vector2(HEADLINE_ENTRY_SCALE_START, HEADLINE_ENTRY_SCALE_START)
	_headline.modulate.a = 0.0


func _snap_headline_rest() -> void:
	if _headline == null:
		return
	_headline.scale = Vector2.ONE
	_headline.modulate.a = 1.0


## 승패 화면: 딤만 빠르게 올리고 배지는 슬라이드인.
func _play_exit_reveal() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	if _dimmer:
		tw.tween_property(_dimmer, "modulate:a", 1.0, EXIT_REVEAL_FADE_SEC)
	if _player_badge:
		tw.tween_property(_player_badge, "position:x", 0.0, BADGE_SLIDE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _opponent_badge:
		tw.tween_property(_opponent_badge, "position:x", 0.0, BADGE_SLIDE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished


func _prepare_entry_visuals() -> void:
	if _headline:
		_headline.text = "VS"
		_snap_headline_entry_hidden()
	_apply_headline_color(false)
	_reset_coin_pivot_transform()
	if _coin_pivot:
		_coin_pivot.visible = false
	_set_coin_face(COIN_FACE_PLAYER)
	_set_reason_text("")
	if _confirm_button:
		_confirm_button.visible = false
		_confirm_button.disabled = false


func _prepare_exit_visuals(is_victory: bool, reason: String) -> void:
	if _headline:
		_headline.text = "VICTORY" if is_victory else "DEFEAT"
		_snap_headline_rest()
	_apply_headline_color(not is_victory)
	if _coin_pivot:
		_coin_pivot.visible = false
	_set_reason_text(build_reason_message(is_victory, reason))
	if _confirm_button:
		_confirm_button.visible = true


static func build_turn_order_message(local_first: GameConstants.Side) -> String:
	if local_first == GameConstants.Side.PLAYER:
		return "당신이 선공입니다."
	return "당신이 후공입니다."


static func build_reason_message(is_victory: bool, reason: String) -> String:
	if reason == "surrender":
		if is_victory:
			return "상대가 항복하여 승리했습니다."
		return "항복하여 패배했습니다."
	if reason == "forfeit":
		if is_victory:
			return "상대의 접속이 종료되어 승리했습니다."
		return "접속이 종료되어 패배 처리되었습니다."
	if is_victory:
		return "대전에서 승리했습니다."
	return "라이프가 모두 소진되어 패배했습니다."


## 메시지 영역은 항상 자리 유지 — visible 토글 없이 텍스트만 대입.
func _set_reason_text(text: String) -> void:
	if _reason_label == null:
		return
	_reason_label.visible = true
	_reason_label.text = text
	_reason_label.modulate.a = 1.0


func _fade_headline_to_blank() -> void:
	if _headline == null:
		return
	var tw := create_tween()
	tw.tween_property(_headline, "modulate:a", 0.0, VS_FADE_SEC)
	await tw.finished
	_headline.text = ""
	_snap_headline_rest()


func _play_coin_toss(local_first: GameConstants.Side) -> void:
	if _coin_pivot == null:
		return
	var winner_face := (
		COIN_FACE_PLAYER
		if local_first == GameConstants.Side.PLAYER
		else COIN_FACE_OPPONENT
	)
	_reset_coin_pivot_transform()
	_coin_pivot.visible = true
	_set_coin_face(COIN_FACE_PLAYER)
	for i in COIN_FLIP_COUNT:
		var land_on_player := i == COIN_FLIP_COUNT - 1 and winner_face == COIN_FACE_PLAYER
		var land_on_opponent := i == COIN_FLIP_COUNT - 1 and winner_face == COIN_FACE_OPPONENT
		if land_on_player:
			await _flip_coin_to_face(COIN_FACE_PLAYER)
		elif land_on_opponent:
			await _flip_coin_to_face(COIN_FACE_OPPONENT)
		else:
			await _flip_coin_to_face(not _coin_showing_player_face)


func _flip_coin_to_face(player_face: bool) -> void:
	if _coin_pivot == null:
		return
	var tw := create_tween()
	tw.tween_property(_coin_pivot, "scale:x", 0.0, COIN_FLIP_HALF_SEC).set_trans(Tween.TRANS_SINE)
	await tw.finished
	_set_coin_face(player_face)
	var tw2 := create_tween()
	tw2.tween_property(_coin_pivot, "scale:x", 1.0, COIN_FLIP_HALF_SEC).set_trans(Tween.TRANS_SINE)
	await tw2.finished


func _set_coin_face(player_face: bool) -> void:
	_coin_showing_player_face = player_face
	if _coin_front:
		_coin_front.visible = player_face
	if _coin_back:
		_coin_back.visible = not player_face


func _fade_out_intro() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	if _dimmer:
		tw.tween_property(_dimmer, "modulate:a", 0.0, INTRO_FADE_OUT_SEC)
	if _coin_pivot and _coin_pivot.visible:
		tw.tween_property(_coin_pivot, "modulate:a", 0.0, INTRO_FADE_OUT_SEC)
	if _reason_label:
		tw.tween_property(_reason_label, "modulate:a", 0.0, INTRO_FADE_OUT_SEC)
	if _player_badge:
		tw.tween_property(_player_badge, "position:x", _badge_offscreen_x(true), BADGE_SLIDE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if _opponent_badge:
		tw.tween_property(_opponent_badge, "position:x", _badge_offscreen_x(false), BADGE_SLIDE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	if _dimmer:
		_dimmer.modulate.a = 1.0
	if _coin_pivot:
		_coin_pivot.modulate.a = 1.0
		_coin_pivot.visible = false
	_set_reason_text("")
	_snap_badges_rest()


func _on_confirm_pressed() -> void:
	if _exit_busy:
		return
	_exit_busy = true
	if _confirm_button:
		_confirm_button.disabled = true
	await _fade_exit_to_black()
	confirmed.emit()


## 배지 슬라이드 없이 전체 검정으로 덮은 뒤 다음 화면으로.
func _fade_exit_to_black() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	if _dimmer:
		tw.tween_property(_dimmer, "color", Color(0, 0, 0, 1), EXIT_CONFIRM_FADE_SEC)
		tw.tween_property(_dimmer, "modulate:a", 1.0, EXIT_CONFIRM_FADE_SEC)
	for node in [_headline, _reason_label, _confirm_button, _player_badge, _opponent_badge]:
		if node:
			tw.tween_property(node, "modulate:a", 0.0, EXIT_CONFIRM_FADE_SEC)
	await tw.finished
