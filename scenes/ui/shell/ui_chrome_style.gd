class_name UiChromeStyle
extends Resource
## 인게임 UI 크롬(패널·버튼·토스트) StyleBox 팔레트.
## 인스펙터에서 색·라운드·보더를 조색하고 .tres 복제로 안을 비교할 수 있다.
## 기본안: ui_chrome_cyan.tres (Cyan Frame / 기존 다크 + 시안 액센트).
## 패널·시트·토스트: 라운드 없음 + 상단 사선(chamfer). 버튼도 동일 챔퍼.

const DEFAULT_PATH := "res://scenes/ui/shell/ui_chrome_cyan.tres"

@export_group("Panel")
## 사이드바·팝업 패널 배경.
@export var panel_bg: Color = Color(0.08, 0.08, 0.12, 0.92)
## 패널 테두리 (시안 프레임).
@export var panel_border: Color = Color(0.38, 0.52, 0.68, 1.0)
@export_range(0.0, 8.0, 0.1) var panel_border_width: float = 1.0
## 레거시 필드(미사용) — 라운드 제거. 챔퍼는 chamfer_top_left.
@export_range(0, 24, 1) var panel_corner_radius: int = 0
@export_range(0, 32, 1) var panel_margin: int = 0
## 좌상단 사선 컷 길이(px). 0 이면 완전 직각. (기본 14의 약 80% ≈ 11)
@export_range(0, 48, 1) var chamfer_top_left: int = 11

@export_group("Button")
@export var button_bg: Color = Color(0.11, 0.13, 0.18, 1.0)
@export var button_bg_hover: Color = Color(0.14, 0.22, 0.30, 1.0)
@export var button_bg_pressed: Color = Color(0.08, 0.18, 0.26, 1.0)
@export var button_bg_disabled: Color = Color(0.07, 0.07, 0.09, 0.75)
@export var button_border: Color = Color(0.40, 0.50, 0.62, 1.0)
## hover/focus 형광 시안.
@export var button_border_hover: Color = Color(0.22, 0.87, 0.95, 1.0)
@export var button_border_pressed: Color = Color(0.16, 0.72, 0.82, 1.0)
@export var button_border_disabled: Color = Color(0.25, 0.25, 0.30, 1.0)
@export_range(0.0, 6.0, 0.1) var button_border_width: float = 1.0
## 버튼은 직각 필드 미사용 — 챔퍼는 chamfer_top_left.
@export_range(0, 16, 1) var button_corner_radius: int = 0
@export_range(0, 24, 1) var button_margin_h: int = 12
@export_range(0, 24, 1) var button_margin_v: int = 6

@export_group("Font")
@export var font_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var font_muted: Color = Color(0.88, 0.90, 0.94, 1.0)
@export var font_hover: Color = Color(0.85, 0.98, 1.0, 1.0)
@export var font_disabled: Color = Color(0.48, 0.50, 0.55, 1.0)

@export_group("Sheet")
## TargetListSheet·FieldTargetPrompt 바텀시트 배경 (패널보다 살짝 어둡게).
@export var sheet_bg: Color = Color(0.04, 0.04, 0.07, 0.96)
## 시트 상단 보더 (시안 프레임 톤).
@export var sheet_border: Color = Color(0.32, 0.48, 0.64, 1.0)

@export_group("Screen")
## Screen 전체 단색 배경 (뷰포트 기본 회색 대체). 패널보다 살짝 어둡고 불투명.
@export var screen_bg: Color = Color(0.045, 0.05, 0.07, 1.0)
## Label+행 묶음(Section) 배경 — screen과 button 사이.
@export var section_bg: Color = Color(0.075, 0.085, 0.11, 0.96)
@export var section_border: Color = Color(0.34, 0.46, 0.60, 1.0)
@export_range(0.0, 6.0, 0.1) var section_border_width: float = 0.5
@export_range(0, 24, 1) var section_margin_h: int = 12
@export_range(0, 24, 1) var section_margin_v: int = 10

@export_group("Toast")
@export var toast_bg: Color = Color(0.05, 0.05, 0.08, 0.90)
@export var toast_border: Color = Color(0.35, 0.58, 0.75, 1.0)
@export var toast_font: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.2, 3.0, 0.05) var toast_duration: float = 1.0
@export_range(12, 48, 1) var toast_font_size: int = 22

@export_group("Accent")
## 하이라이트·활성 강조 (형광 시안).
@export var accent: Color = Color(0.22, 0.871, 0.949, 1.0)

@export_group("Cell")
## 묘지/선택 바 카드 셀 배경.
@export var cell_bg: Color = Color(0.12, 0.12, 0.16, 0.9)
## 플레이어 소유 셀 테두리.
@export var cell_border_player: Color = Color(0.25, 0.45, 1.0, 1.0)
## 상대 소유 셀 테두리.
@export var cell_border_opponent: Color = Color(1.0, 0.25, 0.25, 1.0)

@export_group("Copy")
## 버튼·라벨 문구. null 이면 UiCopy 기본(.tres).
@export var copy: UiCopy


## 기본 Cyan Frame .tres 를 로드한다. 실패 시 인메모리 기본값.
static func load_default() -> UiChromeStyle:
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded := load(DEFAULT_PATH)
		if loaded is UiChromeStyle:
			return loaded as UiChromeStyle
	return UiChromeStyle.new()


## null 이면 기본 크롬 반환.
static func resolve(style: UiChromeStyle) -> UiChromeStyle:
	if style != null:
		return style
	return load_default()


## 이 크롬에 묶인 UiCopy (없으면 기본).
func get_copy() -> UiCopy:
	return UiCopy.resolve(copy)


## 패널용 챔퍼 StyleBox. mirror_h=true 면 우상단 챔퍼.
## diagonal_pair=true 면 대각 반대 모서리도 챔퍼.
func make_panel_stylebox(mirror_h: bool = false, diagonal_pair: bool = false) -> StyleBox:
	var style := UiChamferStyleBox.new()
	style.bg_color = panel_bg
	style.border_color = panel_border
	style.border_width = float(panel_border_width)
	style.chamfer_tl = float(chamfer_top_left)
	style.mirror_h = mirror_h
	style.diagonal_pair = diagonal_pair
	style.border_left = true
	style.border_top = true
	style.border_right = true
	style.border_bottom = true
	style.content_margin_left = float(panel_margin)
	style.content_margin_right = float(panel_margin)
	style.content_margin_top = float(panel_margin)
	style.content_margin_bottom = float(panel_margin)
	return style


## 바텀시트용 챔퍼 StyleBox — 상단(+챔퍼) 보더만.
func make_sheet_stylebox() -> StyleBox:
	var style := UiChamferStyleBox.new()
	style.bg_color = sheet_bg
	style.border_color = sheet_border
	style.border_width = maxf(2.0, panel_border_width)
	style.chamfer_tl = float(chamfer_top_left)
	style.mirror_h = false
	style.border_left = false
	style.border_top = true
	style.border_right = false
	style.border_bottom = false
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


## PanelContainer 에 시트 StyleBox 적용.
func apply_sheet_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_sheet_stylebox())


## Label+컨트롤 묶음용 챔퍼 StyleBox (여백 포함).
func make_section_stylebox() -> StyleBox:
	var style := UiChamferStyleBox.new()
	style.bg_color = section_bg
	style.border_color = section_border
	style.border_width = float(section_border_width)
	style.chamfer_tl = float(chamfer_top_left)
	style.mirror_h = false
	style.border_left = true
	style.border_top = true
	style.border_right = true
	style.border_bottom = true
	style.content_margin_left = float(section_margin_h)
	style.content_margin_right = float(section_margin_h)
	style.content_margin_top = float(section_margin_v)
	style.content_margin_bottom = float(section_margin_v)
	return style


## Section PanelContainer 에 묶음 StyleBox 적용.
func apply_section_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_section_stylebox())


## Screen 루트에 단색 ScreenBg(ColorRect)를 두거나 색만 갱신한다. 배치는 full-rect.
func apply_screen_background(root: Control) -> void:
	if root == null:
		return
	var bg := root.get_node_or_null("ScreenBg") as ColorRect
	if bg == null:
		bg = ColorRect.new()
		bg.name = "ScreenBg"
		root.add_child(bg)
		root.move_child(bg, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = screen_bg


## 페이즈 토스트용 챔퍼 StyleBox.
func make_toast_stylebox() -> StyleBox:
	var style := UiChamferStyleBox.new()
	style.bg_color = toast_bg
	style.border_color = toast_border
	style.border_width = maxf(1.0, panel_border_width)
	style.chamfer_tl = float(chamfer_top_left)
	style.mirror_h = false
	style.border_left = true
	style.border_top = true
	style.border_right = true
	style.border_bottom = true
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


## 버튼 상태별 챔퍼 StyleBox. state: normal|hover|pressed|disabled|focus
## margin_h/v < 0 이면 button_margin_* 기본값. chamfer < 0 이면 chamfer_top_left.
func make_button_stylebox(
	state: StringName = &"normal",
	margin_h: int = -1,
	margin_v: int = -1,
	chamfer: float = -1.0,
	diagonal_pair: bool = false
) -> StyleBox:
	var style := UiChamferStyleBox.new()
	match String(state):
		"hover", "focus":
			style.bg_color = button_bg_hover
			style.border_color = button_border_hover
		"pressed":
			style.bg_color = button_bg_pressed
			style.border_color = button_border_pressed
		"disabled":
			style.bg_color = button_bg_disabled
			style.border_color = button_border_disabled
		_:
			style.bg_color = button_bg
			style.border_color = button_border
	style.border_width = float(button_border_width)
	style.chamfer_tl = float(chamfer_top_left) if chamfer < 0.0 else chamfer
	style.mirror_h = false
	style.diagonal_pair = diagonal_pair
	style.border_left = true
	style.border_top = true
	style.border_right = true
	style.border_bottom = true
	var mh := button_margin_h if margin_h < 0 else margin_h
	var mv := button_margin_v if margin_v < 0 else margin_v
	style.content_margin_left = float(mh)
	style.content_margin_right = float(mh)
	style.content_margin_top = float(mv)
	style.content_margin_bottom = float(mv)
	return style


## PanelContainer 에 패널 StyleBox 적용. mirror_h=true 면 우상단 챔퍼.
func apply_panel(panel: PanelContainer, mirror_h: bool = false) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_panel_stylebox(mirror_h))


## 이름 배지용 — 여백 + 챔퍼 방향(좌측 배지는 mirror).
func apply_id_badge(panel: PanelContainer, mirror_h: bool = false) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _make_id_badge_stylebox(mirror_h))


## 라인 파워 라벨(PanelContainer) — 컴팩트 대각 챔퍼 패널. 글자색은 phase_manager가 갱신.
func apply_power_label(panel: PanelContainer) -> void:
	if panel == null:
		return
	var style := make_panel_stylebox(false, true) as UiChamferStyleBox
	if style:
		style.content_margin_left = 4.0
		style.content_margin_right = 4.0
		style.content_margin_top = 1.0
		style.content_margin_bottom = 1.0
		style.chamfer_tl = mini(float(chamfer_top_left), 6.0)
		style.border_width = maxf(1.0, float(panel_border_width))
	panel.add_theme_stylebox_override("panel", style)


## 인게임 확정(Phase) 버튼 — 크기 유지 + 대각 챔퍼 크롬.
## local_side: PLAYER=파란(ALLY) · OPPONENT=빨간(OPPONENT).
## disabled도 턴 색을 진하게 유지 (비활성은 명도·알파만 살짝 낮춤).
func apply_phase_button(button: Button, local_side: int = GameConstants.Side.PLAYER) -> void:
	if button == null:
		return
	button.flat = false
	var chamfer := mini(float(chamfer_top_left), 8.0)
	var margin_h := mini(6, button_margin_h)
	var margin_v := mini(4, button_margin_v)
	button.focus_mode = Control.FOCUS_NONE
	var turn := (
		GameConstants.ALLY_COLOR
		if local_side == GameConstants.Side.PLAYER
		else GameConstants.OPPONENT_COLOR
	)
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		# disabled도 normal 팔레트에서 틴트 — button_bg_disabled(회색) 베이스면 채도가 죽음.
		var box_state: StringName = &"normal" if state == &"focus" or state == &"disabled" else state
		var style := make_button_stylebox(box_state, margin_h, margin_v, chamfer, true) as UiChamferStyleBox
		if style:
			# cyan tres border 0.3은 확정 버튼에서 거의 안 보임 → 최소 1px.
			style.border_width = maxf(1.0, float(button_border_width))
			_tint_phase_button_style(style, state, turn)
		button.add_theme_stylebox_override(String(state), style)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_hover)
	button.add_theme_color_override("font_pressed_color", font_color)
	# 비활성도 턴 색 가독성 유지 — 기본 font_disabled(회색) 대신 밝은 톤.
	button.add_theme_color_override("font_disabled_color", Color(font_color.r, font_color.g, font_color.b, 0.78))
	button.add_theme_color_override("font_focus_color", font_color)


## Phase 버튼 배경·테두리를 턴 색(청/적)으로 틴트.
func _tint_phase_button_style(style: UiChamferStyleBox, state: StringName, turn: Color) -> void:
	if style == null:
		return
	var fill := 0.32
	var border_a := 0.95
	match String(state):
		"hover", "focus":
			fill = 0.42
			border_a = 1.0
		"pressed":
			fill = 0.50
			border_a = 1.0
		"disabled":
			# normal과 비슷한 채도 유지 — 살짝만 어둡게.
			fill = 0.30
			border_a = 0.88
		_:
			pass
	var turn_rgb := Color(turn.r, turn.g, turn.b, style.bg_color.a)
	style.bg_color = style.bg_color.lerp(turn_rgb, fill)
	if String(state) == "disabled":
		style.bg_color = Color(
			style.bg_color.r * 0.85,
			style.bg_color.g * 0.85,
			style.bg_color.b * 0.85,
			style.bg_color.a
		)
	style.border_color = Color(turn.r, turn.g, turn.b, border_a)


## PlayerBadge — 패널 룩 + 챔퍼. mirror_h=true → 우상단(아이콘 좌측 · 챔퍼 우측).
func apply_player_badge(badge: Button, mirror_h: bool = false) -> void:
	if badge == null:
		return
	badge.focus_mode = Control.FOCUS_NONE
	badge.add_theme_stylebox_override("normal", _make_player_badge_stylebox(&"normal", mirror_h))
	badge.add_theme_stylebox_override("hover", _make_player_badge_stylebox(&"hover", mirror_h))
	badge.add_theme_stylebox_override("pressed", _make_player_badge_stylebox(&"pressed", mirror_h))
	badge.add_theme_stylebox_override("disabled", _make_player_badge_stylebox(&"disabled", mirror_h))
	badge.add_theme_stylebox_override("focus", _make_player_badge_stylebox(&"normal", mirror_h))


func _make_id_badge_stylebox(mirror_h: bool) -> StyleBox:
	var style := make_panel_stylebox(mirror_h) as UiChamferStyleBox
	if style:
		style.content_margin_left = 10.0
		style.content_margin_right = 10.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
	return style


func _make_player_badge_stylebox(state: StringName, mirror_h: bool) -> StyleBox:
	var style := UiChamferStyleBox.new()
	match String(state):
		"hover":
			style.bg_color = button_bg_hover
			style.border_color = button_border_hover
		"pressed":
			style.bg_color = button_bg_pressed
			style.border_color = button_border_pressed
		"disabled":
			style.bg_color = button_bg_disabled
			style.border_color = button_border_disabled
		_:
			style.bg_color = panel_bg
			style.border_color = panel_border
	style.border_width = float(panel_border_width)
	style.chamfer_tl = float(chamfer_top_left)
	style.mirror_h = mirror_h
	style.border_left = true
	style.border_top = true
	style.border_right = true
	style.border_bottom = true
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


## Button 에 normal/hover/pressed/disabled/focus StyleBox·글자색 적용.
## focus_mode=NONE — 클릭 후 포커스 하이라이트가 남지 않게.
func apply_button(button: Button) -> void:
	_apply_button_with_margins(button, button_margin_h, button_margin_v, float(chamfer_top_left))


## 밀집 UI(탭·소분류·격자 셀)용 — 마진 축소 + 챔퍼 없음(좁은 폭에서 좌상단 잘림 방지).
func apply_button_compact(button: Button) -> void:
	_apply_button_with_margins(button, mini(6, button_margin_h), mini(4, button_margin_v), 0.0)


## 필터 칩 — selected면 배경은 유지하고 테두리만 시안 발광.
func apply_filter_chip(button: Button, selected: bool = false) -> void:
	if button == null:
		return
	button.focus_mode = Control.FOCUS_NONE
	var margin_h := mini(6, button_margin_h)
	var margin_v := mini(4, button_margin_v)
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		var box_state: StringName = &"hover" if state == &"hover" else &"normal"
		if state == &"pressed":
			box_state = &"pressed"
		elif state == &"disabled":
			box_state = &"disabled"
		var style := make_button_stylebox(box_state, margin_h, margin_v, 0.0) as UiChamferStyleBox
		if style and selected:
			# 테두리만 발광 — fill은 normal 유지, 보더는 hover 시안.
			if state != &"disabled":
				style.bg_color = button_bg
				style.border_color = button_border_hover
				style.border_width = maxf(2.0, float(button_border_width) * 3.0)
		elif style:
			style.border_width = maxf(1.0, float(button_border_width))
		button.add_theme_stylebox_override(String(state), style)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_hover)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_color_override("font_disabled_color", font_disabled)
	button.add_theme_color_override("font_focus_color", font_color)


## 필터 진입 버튼 — active면 테두리 시안 발광 (팝업 내 선택 있음).
func apply_filter_gate_button(button: Button, active: bool = false) -> void:
	if button == null:
		return
	button.focus_mode = Control.FOCUS_NONE
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		var box_state: StringName = state
		if state == &"focus":
			box_state = &"normal"
		var style := make_button_stylebox(box_state, button_margin_h, button_margin_v, float(chamfer_top_left)) as UiChamferStyleBox
		if style and active and state != &"disabled":
			style.border_color = button_border_hover
			style.border_width = maxf(2.0, float(button_border_width) * 3.0)
		elif style:
			style.border_width = maxf(1.0, float(button_border_width))
		button.add_theme_stylebox_override(String(state), style)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_hover)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_color_override("font_disabled_color", font_disabled)
	button.add_theme_color_override("font_focus_color", font_color)


## 지정 마진·챔퍼로 버튼 크롬·글자색을 적용한다.
func _apply_button_with_margins(
	button: Button,
	margin_h: int,
	margin_v: int,
	chamfer: float,
	diagonal_pair: bool = false
) -> void:
	if button == null:
		return
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override(
		"normal", make_button_stylebox(&"normal", margin_h, margin_v, chamfer, diagonal_pair)
	)
	button.add_theme_stylebox_override(
		"hover", make_button_stylebox(&"hover", margin_h, margin_v, chamfer, diagonal_pair)
	)
	button.add_theme_stylebox_override(
		"pressed", make_button_stylebox(&"pressed", margin_h, margin_v, chamfer, diagonal_pair)
	)
	button.add_theme_stylebox_override(
		"disabled", make_button_stylebox(&"disabled", margin_h, margin_v, chamfer, diagonal_pair)
	)
	button.add_theme_stylebox_override(
		"focus", make_button_stylebox(&"normal", margin_h, margin_v, chamfer, diagonal_pair)
	)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_hover)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_color_override("font_disabled_color", font_disabled)
	button.add_theme_color_override("font_focus_color", font_color)


## 좌상단 Screen Back — 기호·정사각·타이트 마진. 위치는 씬 앵커 기준.
func apply_back_button(button: Button) -> void:
	if button == null:
		return
	var side := UiShellConstants.SCREEN_BACK_SIZE
	button.text = UiShellConstants.SCREEN_BACK_SYMBOL
	button.tooltip_text = get_copy().back_tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(side, side)
	var pad := 4
	var style_n := make_button_stylebox(&"normal") as UiChamferStyleBox
	var style_h := make_button_stylebox(&"hover") as UiChamferStyleBox
	var style_p := make_button_stylebox(&"pressed") as UiChamferStyleBox
	var style_d := make_button_stylebox(&"disabled") as UiChamferStyleBox
	for s in [style_n, style_h, style_p, style_d]:
		if s:
			s.content_margin_left = float(pad)
			s.content_margin_right = float(pad)
			s.content_margin_top = float(pad)
			s.content_margin_bottom = float(pad)
	button.add_theme_stylebox_override("normal", style_n)
	button.add_theme_stylebox_override("hover", style_h)
	button.add_theme_stylebox_override("pressed", style_p)
	button.add_theme_stylebox_override("disabled", style_d)
	button.add_theme_stylebox_override("focus", style_n)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_hover)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_font_size_override("font_size", 22)


## OptionButton 본체 + 드롭다운 PopupMenu 크롬.
func apply_option_button(option: OptionButton) -> void:
	if option == null:
		return
	apply_button(option)
	var popup := option.get_popup()
	if popup == null:
		return
	popup.add_theme_stylebox_override("panel", make_panel_stylebox())
	popup.add_theme_stylebox_override("hover", make_button_stylebox(&"hover"))
	popup.add_theme_color_override("font_color", font_color)
	popup.add_theme_color_override("font_hover_color", font_hover)
	popup.add_theme_color_override("font_disabled_color", font_disabled)
	popup.add_theme_color_override("font_accelerator_color", font_muted)
	popup.add_theme_color_override("font_separator_color", section_border)


## HSlider 트랙·그랩 크롬.
func apply_h_slider(slider: HSlider) -> void:
	if slider == null:
		return
	var track := _make_flat(screen_bg, section_border, 1.0, 2, 2)
	var fill := _make_flat(button_bg_pressed, accent, 1.0, 2, 2)
	var grabber := _make_flat(button_bg_hover, button_border_hover, 1.0, 4, 4)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_icon_override("grabber", _make_grabber_image(grabber))
	slider.add_theme_icon_override("grabber_highlight", _make_grabber_image(grabber))
	slider.add_theme_icon_override("grabber_disabled", _make_grabber_image(
		_make_flat(button_bg_disabled, button_border_disabled, 1.0, 4, 4)
	))


## ScrollContainer 의 H/V 스크롤바 크롬.
func apply_scroll_container(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	_apply_scroll_bar(scroll.get_v_scroll_bar())
	_apply_scroll_bar(scroll.get_h_scroll_bar())


## ScrollBar 트랙·그랩 StyleBox.
func _apply_scroll_bar(bar: ScrollBar) -> void:
	if bar == null:
		return
	var track := _make_flat(Color(screen_bg.r, screen_bg.g, screen_bg.b, 0.85), section_border, 0.5, 2, 2)
	var grab := _make_flat(button_bg, button_border, 1.0, 3, 3)
	var grab_h := _make_flat(button_bg_hover, button_border_hover, 1.0, 3, 3)
	var grab_p := _make_flat(button_bg_pressed, button_border_pressed, 1.0, 3, 3)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_h)
	bar.add_theme_stylebox_override("grabber_pressed", grab_p)
	bar.add_theme_color_override("font_color", font_muted)


## 묘지/선택 바 셀용 StyleBoxFlat (소유자 테두리).
func make_cell_stylebox(owner_side: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = cell_bg
	style.set_border_width_all(1)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	if owner_side == GameConstants.Side.PLAYER:
		style.border_color = cell_border_player
	else:
		style.border_color = cell_border_opponent
	return style


## 단색 StyleBoxFlat 헬퍼.
func _make_flat(bg: Color, border: Color, border_w: float, margin_h: int, margin_v: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(round(border_w)))
	style.set_content_margin_all(0)
	style.content_margin_left = float(margin_h)
	style.content_margin_right = float(margin_h)
	style.content_margin_top = float(margin_v)
	style.content_margin_bottom = float(margin_v)
	return style


## 슬라이더 grabber용 작은 텍스처 (StyleBox → Image).
func _make_grabber_image(style: StyleBoxFlat) -> ImageTexture:
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	img.fill(style.bg_color)
	# 테두리 1px.
	var bc := style.border_color
	for x in range(12):
		img.set_pixel(x, 0, bc)
		img.set_pixel(x, 15, bc)
	for y in range(16):
		img.set_pixel(0, y, bc)
		img.set_pixel(11, y, bc)
	return ImageTexture.create_from_image(img)


## 버튼 배열에 apply_button.
func apply_buttons(buttons: Array) -> void:
	for item in buttons:
		if item is Button:
			apply_button(item as Button)


## 제목/본문 라벨 글자색.
func apply_title_label(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", font_color)


## 보조 본문 라벨 글자색.
func apply_muted_label(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", font_muted)


## LineEdit 배경·글자색 (레이아웃/앵커 미변경).
func apply_line_edit(edit: LineEdit) -> void:
	if edit == null:
		return
	var normal := make_button_stylebox(&"normal")
	var focus := make_button_stylebox(&"focus")
	edit.add_theme_stylebox_override("normal", normal)
	edit.add_theme_stylebox_override("focus", focus)
	edit.add_theme_stylebox_override("read_only", make_button_stylebox(&"disabled"))
	edit.add_theme_color_override("font_color", font_color)
	edit.add_theme_color_override("font_placeholder_color", font_disabled)
	edit.add_theme_color_override("caret_color", accent)


## TextEdit 배경·글자색 (읽기 전용 account key 등).
func apply_text_edit(edit: TextEdit) -> void:
	if edit == null:
		return
	var normal := make_button_stylebox(&"normal")
	var focus := make_button_stylebox(&"focus")
	edit.add_theme_stylebox_override("normal", normal)
	edit.add_theme_stylebox_override("focus", focus)
	edit.add_theme_stylebox_override("read_only", make_button_stylebox(&"disabled"))
	edit.add_theme_color_override("font_color", font_color)
	edit.add_theme_color_override("font_placeholder_color", font_disabled)
	edit.add_theme_color_override("caret_color", accent)


## Screen 루트: (옵션) 단색 배경 + 하위 Button·Label·LineEdit·*Section 패널 크롬.
## include_background=false 이면 하위 페인만 스타일 (덱에디터 Center/Right용).
func apply_screen_tree(root: Node, include_background: bool = true) -> void:
	if root == null:
		return
	if include_background and root is Control:
		apply_screen_background(root as Control)
	_apply_screen_node_recursive(root)


## 이름이 Section으로 끝나는 PanelContainer 여부.
func _is_section_panel(node: Node) -> bool:
	if not (node is PanelContainer):
		return false
	var n := String(node.name)
	return n.ends_with("Section")


## Screen 트리 한 노드 처리 후 자식 순회.
func _apply_screen_node_recursive(node: Node) -> void:
	# ScreenBg는 스타일 대상 아님.
	if node.name == &"ScreenBg":
		return
	if node is CardInfoDetail:
		return
	if node.name == &"BackButton" and node is Button:
		apply_back_button(node as Button)
	elif _is_section_panel(node):
		apply_section_panel(node as PanelContainer)
	elif node is OptionButton:
		apply_option_button(node as OptionButton)
	elif node is LineEdit:
		apply_line_edit(node as LineEdit)
	elif node is TextEdit:
		apply_text_edit(node as TextEdit)
	elif node is HSlider:
		apply_h_slider(node as HSlider)
	elif node is ScrollContainer:
		apply_scroll_container(node as ScrollContainer)
	elif node is Button:
		if node is PlayerBadge:
			pass
		else:
			apply_button(node as Button)
	elif node is Label:
		var label := node as Label
		var n := String(label.name)
		if n.begins_with("Title") or n == "TitleLabel":
			apply_title_label(label)
		else:
			apply_muted_label(label)
	for child in node.get_children():
		_apply_screen_node_recursive(child)
