class_name PackOpenScreen
extends Control
## 팩 개봉 오버레이.
## 1팩: 팩 이미지(+힌트 테두리) → 상단 찢기 → 칩 플립.
## 다팩: 2×5 그리드(힌트) 1회 → 화면 클릭 시 1번째 팩부터 단팩 연출 반복.
## Skip → 남은 연출 생략 후 즉시 OpenResult(finished).

signal finished
## 앞면 칩 클릭 → 상점 CardInfoRoot (name, instance_rarity).
signal chip_info_requested(card_name: String, rarity: int)

enum Phase {
	MULTI_GRID,
	PACK_ENTERING,
	PACK_IDLE,
	TEARING,
	CHIPS,
}

const CHIP_W := 120.0
const PACK_TEX_PATH := "res://assets_lite/ShopAsset/cardpack.png"
const GRID_CELL_SCENE := preload("res://scenes/ui/pack_grid_cell.tscn")
const PACK_DISPLAY_H := 320.0
const GRID_PACK_H := 150.0
const GRID_COLS := 5
## PackVisual 등장: 왼쪽에서 중앙으로 슬라이드.
const PACK_ENTER_SEC := 0.38
const PACK_ENTER_SLIDE_PX := 480.0
## 다팩 PackGrid 통째 등장 (PackVisual과 동일 톤).
const GRID_ENTER_SEC := 0.38
const GRID_ENTER_SLIDE_PX := 480.0
## ChipRow 칩 개별 스태거 등장.
const CHIP_ENTER_SEC := 0.32
const CHIP_ENTER_SLIDE_PX := 360.0
const CHIP_ENTER_STAGGER := 0.06
## --- 상단 찢기 연출 튜닝 (교체·미세조정은 여기) ---
## 절단 위치: 카드 뒷면 기준 상단:하단 = 20:80.
const TEAR_FRAC := 0.20
## 상단 조각이 위로 떠오르며 페이드되는 시간(초).
const TEAR_LIFT_SEC := 0.28
## 상단 조각 페이드아웃 시간(초).
const TEAR_FADE_SEC := 0.32
## 페이드가 리프트 시작 후 얼마나 늦게 시작할지 (리프트 시간 비율 0~1).
const TEAR_FADE_DELAY_RATIO := 0.15
## 상단 조각이 위로 뜨는 양(px).
const TEAR_LIFT_PX := 110.0
## 우측이 더 들리도록 시계 회전(도). 피벗은 좌측.
const TEAR_LIFT_ROT_DEG := 16.0
## 절단선 등급색 슬래시(빛) 가로 폭·두께.
const TEAR_SLASH_W := 64.0
const TEAR_SLASH_H := 20.0
## 슬래시가 팩을 가로지르는 시간(초).
const TEAR_SLASH_SEC := 0.28
## 슬래시가 팩 좌·우로 더 나가는 거리(px).
const TEAR_SLASH_OVERSHOOT := 110.0
## --- 힌트 ---
const BACK_GLOW_HINT_CHANCE := 0.7
const BACK_GLOW_PULSE_SEC := 1.1
## OpenResult(크롬 screen_bg)와 이전 팩오픈 암막의 중간 밝기. 불투명.
const PACK_OPEN_BG := Color(0.092, 0.092, 0.131, 1.0)

@onready var _click_catcher: Control = $ClickCatcher
@onready var _multi_grid_root: CenterContainer = $MultiGridRoot
@onready var _pack_grid: GridContainer = $MultiGridRoot/PackGrid
@onready var _pack_preview_root: Control = $PackPreviewRoot
@onready var _pack_visual: Control = $PackPreviewRoot/PackVisual
@onready var _pack_art: TextureRect = $PackPreviewRoot/PackVisual/Art
@onready var _pack_frame: Panel = $PackPreviewRoot/PackVisual/Frame
@onready var _tear_host: Control = $TearHost
@onready var _chip_center: CenterContainer = $Center
@onready var _chip_row: HBoxContainer = $Center/ChipRow
@onready var _pack_label: Label = $PackLabel
@onready var _skip_button: Button = $BottomRight/SkipButton

var _chrome: UiChromeStyle
var _granted_names: PackedStringArray = PackedStringArray()
var _granted_rarities: Array[int] = []
var _pack_size: int = 1
var _pack_count: int = 1
var _pack_index: int = 0  ## 0-based · 현재 단팩
var _swipe_active: bool = false
var _phase: int = Phase.PACK_IDLE
## 팩별 카드 힌트 bool 배열.
var _pack_card_hints: Array = []
## 팩 힌트 테두리 등급. 힌트 없으면 -1, 있으면 팩 내 max rarity.
var _pack_hint_tier: Array[int] = []
var _pack_opened: Array[bool] = []
var _pack_tex: Texture2D
var _tear_tween: Tween
var _pack_glow_tween: Tween
var _pack_enter_tween: Tween
var _grid_enter_tween: Tween
var _chip_enter_tween: Tween
var _grid_shown_once: bool = false


## 크롬을 입히고 클릭·Skip·팩 이미지를 연결한다.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_button.visible = true
	_skip_button.pressed.connect(_on_skip_pressed)
	_click_catcher.gui_input.connect(_on_click_catcher_gui_input)
	_pack_visual.gui_input.connect(_on_pack_visual_gui_input)
	_pack_tex = load(PACK_TEX_PATH) as Texture2D
	if _pack_tex:
		_pack_art.texture = _pack_tex
	_apply_pack_visual_size(PACK_DISPLAY_H)


## 스와이프 플립: 칩 단계에서만 동작한다.
func _input(event: InputEvent) -> void:
	if not visible or _phase != Phase.CHIPS:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_swipe_active = mb.pressed
		if mb.pressed:
			_try_flip_at_viewport(mb.position)
	elif event is InputEventMouseMotion and _swipe_active:
		var mm := event as InputEventMouseMotion
		_try_flip_at_viewport(mm.position)


## 구매 결과로 오버레이를 채운다. names/rarities는 평탄 배열(팩×pack_size).
func present(
	granted_names: Array,
	granted_rarities: Array,
	pack_size: int,
	pack_count: int,
	chrome_style: UiChromeStyle = null
) -> void:
	_chrome = UiChromeStyle.resolve(chrome_style)
	_chrome.apply_screen_tree(self)
	_apply_dark_backdrop()
	_skip_button.visible = true
	_granted_names = PackedStringArray()
	for n in granted_names:
		_granted_names.append(str(n))
	_granted_rarities = []
	for r in granted_rarities:
		_granted_rarities.append(clampi(int(r), CardRarity.Tier.N, CardRarity.Tier.UR))
	while _granted_rarities.size() < _granted_names.size():
		_granted_rarities.append(CardRarity.Tier.N)
	_pack_size = maxi(1, pack_size)
	_pack_count = maxi(1, pack_count)
	_pack_index = 0
	_swipe_active = false
	_grid_shown_once = false
	_kill_tear_tween()
	_kill_pack_glow_tween()
	_kill_grid_enter_tween()
	_kill_chip_enter_tween()
	_clear_tear_host()
	_roll_pack_hints()
	if _pack_count > 1:
		_show_multi_grid()
	else:
		_begin_pack_preview(0)


## 상점 크롬 ScreenBg를 팩 오픈용 어두운 불투명 배경으로 덮는다.
func _apply_dark_backdrop() -> void:
	var bg := get_node_or_null("ScreenBg") as ColorRect
	if bg == null:
		return
	bg.color = PACK_OPEN_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 팩 인덱스 내 카드 중 최고 레어도. 없으면 N.
func _max_rarity_of_pack(pack_i: int) -> int:
	var best := CardRarity.Tier.N
	for i in _pack_size:
		var idx := pack_i * _pack_size + i
		if idx < _granted_rarities.size():
			best = maxi(best, _granted_rarities[idx])
	return best


## 팩별 R+ 힌트·팩 아웃라인 등급을 미리 굴려 그리드/단팩/칩이 공유한다.
func _roll_pack_hints() -> void:
	_pack_card_hints.clear()
	_pack_hint_tier.clear()
	_pack_opened.clear()
	for p in _pack_count:
		var hints: Array[bool] = []
		var hinted_max := -1
		for i in _pack_size:
			var idx := p * _pack_size + i
			var rarity := CardRarity.Tier.N
			if idx < _granted_rarities.size():
				rarity = _granted_rarities[idx]
			var hint := (
				CardRarity.shows_display(rarity)
				and randf() < BACK_GLOW_HINT_CHANCE
			)
			hints.append(hint)
			if hint:
				hinted_max = maxi(hinted_max, rarity)
		_pack_card_hints.append(hints)
		_pack_hint_tier.append(hinted_max)
		_pack_opened.append(false)


## 다팩 2×5 그리드를 한 번만 보여 준다.
func _show_multi_grid() -> void:
	_phase = Phase.MULTI_GRID
	_grid_shown_once = true
	_hide_pack_preview()
	_hide_chips()
	_clear_tear_host()
	_kill_grid_enter_tween()
	_clear_pack_grid()
	_multi_grid_root.visible = true
	_pack_grid.columns = GRID_COLS
	_pack_grid.modulate.a = 0.0
	for p in _pack_count:
		var cell := _make_grid_pack_cell(p)
		_pack_grid.add_child(cell)
	_pack_label.text = "%d packs" % _pack_count
	# 레이아웃 확정 후 PackGrid 통째 슬라이드.
	call_deferred("_play_multi_grid_enter_slide")


## PackGrid를 왼쪽에서 중앙으로 슬라이드(+페이드). CenterContainer 정렬 후 position 트윈.
func _play_multi_grid_enter_slide() -> void:
	if not is_instance_valid(_pack_grid) or not _multi_grid_root.visible:
		return
	await get_tree().process_frame
	if not is_instance_valid(_pack_grid) or not _multi_grid_root.visible:
		return
	_kill_grid_enter_tween()
	var target := _pack_grid.position
	_pack_grid.position = Vector2(target.x - GRID_ENTER_SLIDE_PX, target.y)
	_pack_grid.modulate.a = 0.0
	_grid_enter_tween = create_tween()
	_grid_enter_tween.set_parallel(true)
	_grid_enter_tween.tween_property(
		_pack_grid, "position", target, GRID_ENTER_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_grid_enter_tween.tween_property(
		_pack_grid, "modulate:a", 1.0, GRID_ENTER_SEC * 0.55
	).set_ease(Tween.EASE_OUT)


## 그리드용 축소 팩 셀(이미지+힌트 테두리). 클릭은 ClickCatcher가 처리.
func _make_grid_pack_cell(pack_i: int) -> Control:
	var cell := GRID_CELL_SCENE.instantiate() as PackGridCell
	cell.configure(_pack_tex, _hint_tier_of(pack_i), _pack_size_for_height(GRID_PACK_H))
	return cell


## 단팩 이미지(+힌트) 단계로 들어간다.
func _begin_pack_preview(pack_i: int) -> void:
	_pack_index = clampi(pack_i, 0, _pack_count - 1)
	_phase = Phase.PACK_ENTERING
	_swipe_active = false
	_kill_grid_enter_tween()
	_multi_grid_root.visible = false
	_pack_grid.modulate.a = 1.0
	_hide_chips()
	_clear_tear_host()
	_kill_tear_tween()
	_show_pack_preview_idle()
	_pack_label.text = "%d/%d" % [_pack_index + 1, _pack_count]


## 정지 상태 팩 이미지·테두리를 표시한다 (찢기 전, 테두리=통짜). 왼쪽에서 슬라이드 인.
func _show_pack_preview_idle() -> void:
	_apply_pack_visual_size(PACK_DISPLAY_H)
	_pack_preview_root.visible = true
	_pack_visual.visible = true
	_pack_art.modulate = Color.WHITE
	var tier := _hint_tier_of(_pack_index)
	_kill_pack_glow_tween()
	_apply_pack_hint_foil(tier)
	if CardRarity.ENABLE_STYLEBOX_FRAME and tier >= 0:
		_pack_frame.visible = true
		_pack_frame.modulate = Color(1, 1, 1, 0.85)
		_pack_frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(tier, 3.0))
		_start_pack_frame_pulse()
	else:
		_pack_frame.visible = false
	# 한 프레임 뒤 레이아웃 size 확정 후 슬라이드.
	call_deferred("_play_pack_enter_slide")


## PackVisual을 PackPreviewRoot 중앙에 둘 좌표.
func _pack_visual_center_pos() -> Vector2:
	var area := _pack_preview_root.size
	if area.x < 1.0 or area.y < 1.0:
		area = get_viewport_rect().size
	var sz := _pack_visual.size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = _pack_visual.custom_minimum_size
	return (area - sz) * 0.5


## 왼쪽 밖에서 중앙으로 슬라이드(+살짝 페이드). 끝나면 PACK_IDLE.
func _play_pack_enter_slide() -> void:
	if not is_instance_valid(_pack_visual) or not _pack_preview_root.visible:
		return
	_kill_pack_enter_tween()
	var target := _pack_visual_center_pos()
	_pack_visual.position = Vector2(target.x - PACK_ENTER_SLIDE_PX, target.y)
	_pack_visual.modulate.a = 0.35
	_pack_enter_tween = create_tween()
	_pack_enter_tween.set_parallel(true)
	_pack_enter_tween.tween_property(
		_pack_visual, "position", target, PACK_ENTER_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pack_enter_tween.tween_property(
		_pack_visual, "modulate:a", 1.0, PACK_ENTER_SEC * 0.55
	).set_ease(Tween.EASE_OUT)
	_pack_enter_tween.chain().tween_callback(_on_pack_enter_finished)


## 등장 연출 종료 → 클릭으로 찢기 가능.
func _on_pack_enter_finished() -> void:
	_kill_pack_enter_tween()
	if _phase == Phase.PACK_ENTERING:
		_phase = Phase.PACK_IDLE
	if is_instance_valid(_pack_visual):
		_pack_visual.position = _pack_visual_center_pos()
		_pack_visual.modulate.a = 1.0


## 팩 프리뷰를 숨긴다.
func _hide_pack_preview() -> void:
	_kill_pack_glow_tween()
	_kill_pack_enter_tween()
	_apply_pack_hint_foil(-1)
	_pack_preview_root.visible = false
	_pack_visual.visible = false
	_pack_frame.visible = false
	_pack_visual.modulate.a = 1.0


## 팩 아트에 힌트 아웃라인. tier < R 이면 제거.
func _apply_pack_hint_foil(tier: int) -> void:
	if _pack_art == null:
		return
	if CardRarity.shows_display(tier):
		CardRarityFoil.apply(_pack_art, tier, true)
	else:
		CardRarityFoil.clear(_pack_art)


## 칩 행을 숨긴다.
func _hide_chips() -> void:
	_kill_chip_enter_tween()
	_clear_chips()
	_chip_center.visible = false


## 현재 팩 칩(뒷면)·라벨을 갱신한다. 힌트는 사전 롤 재사용.
func _show_current_pack_chips() -> void:
	_phase = Phase.CHIPS
	_hide_pack_preview()
	_clear_tear_host()
	_kill_chip_enter_tween()
	_clear_chips()
	_swipe_active = false
	_chip_center.visible = true
	var start := _pack_index * _pack_size
	var chip_size := Vector2(CHIP_W, CHIP_W / DeckCardChip.CARD_ASPECT)
	var hints: Array = []
	if _pack_index < _pack_card_hints.size():
		hints = _pack_card_hints[_pack_index] as Array
	for i in _pack_size:
		var name_i := start + i
		var card_name := ""
		if name_i < _granted_names.size():
			card_name = _granted_names[name_i]
		if card_name.is_empty():
			continue
		var rarity := CardRarity.Tier.N
		if name_i < _granted_rarities.size():
			rarity = _granted_rarities[name_i]
		var hint := false
		if i < hints.size():
			hint = bool(hints[i])
		var chip := DeckCardChip.instantiate_chip()
		chip.setup(card_name, true, -1, chip_size, rarity)
		chip.set_owned_count(-1)
		chip.enable_pack_reveal(hint)
		chip.info_requested.connect(_on_chip_info_requested)
		# 레이아웃 전에 최종 자리가 보이지 않게.
		chip.modulate.a = 0.0
		_chip_row.add_child(chip)
	_pack_opened[_pack_index] = true
	_pack_label.text = "%d/%d" % [_pack_index + 1, _pack_count]
	call_deferred("_play_chip_row_enter_slide")


## ChipRow 칩을 왼쪽에서 스태거 슬라이드 인. HBox 정렬 후 position 트윈.
func _play_chip_row_enter_slide() -> void:
	if not is_instance_valid(_chip_row) or not _chip_center.visible:
		return
	await get_tree().process_frame
	if not is_instance_valid(_chip_row) or not _chip_center.visible:
		return
	_kill_chip_enter_tween()
	var chips: Array[Control] = []
	for child in _chip_row.get_children():
		if child is Control:
			chips.append(child as Control)
	if chips.is_empty():
		return
	_chip_enter_tween = create_tween()
	_chip_enter_tween.set_parallel(true)
	for i in chips.size():
		var chip := chips[i]
		var rest := chip.position
		chip.position = Vector2(rest.x - CHIP_ENTER_SLIDE_PX, rest.y)
		chip.modulate.a = 0.0
		var delay := float(i) * CHIP_ENTER_STAGGER
		_chip_enter_tween.tween_property(
			chip, "position", rest, CHIP_ENTER_SEC
		).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_chip_enter_tween.tween_property(
			chip, "modulate:a", 1.0, CHIP_ENTER_SEC * 0.55
		).set_delay(delay).set_ease(Tween.EASE_OUT)


## 칩 행을 비운다.
func _clear_chips() -> void:
	_kill_chip_enter_tween()
	for child in _chip_row.get_children():
		_chip_row.remove_child(child)
		child.queue_free()


## 그리드 자식을 비운다.
func _clear_pack_grid() -> void:
	_kill_grid_enter_tween()
	for child in _pack_grid.get_children():
		_pack_grid.remove_child(child)
		child.queue_free()
	_pack_grid.modulate.a = 1.0


## TearHost 자식을 비운다.
func _clear_tear_host() -> void:
	_tear_host.visible = false
	for child in _tear_host.get_children():
		_tear_host.remove_child(child)
		child.queue_free()


## 팩 힌트 등급. 없으면 -1.
func _hint_tier_of(pack_i: int) -> int:
	if pack_i < 0 or pack_i >= _pack_hint_tier.size():
		return -1
	return _pack_hint_tier[pack_i]


## 높이 기준 팩 표시 크기(텍스처 비율 유지).
func _pack_size_for_height(height: float) -> Vector2:
	var aspect := DeckCardChip.CARD_ASPECT
	if _pack_tex != null:
		var sz := _pack_tex.get_size()
		if sz.y > 0.0:
			aspect = sz.x / sz.y
	return Vector2(height * aspect, height)


## PackVisual 최소 크기를 맞춘다.
func _apply_pack_visual_size(height: float) -> void:
	var size := _pack_size_for_height(height)
	_pack_visual.custom_minimum_size = size
	_pack_visual.size = size


## 현재 팩 칩이 모두 앞면이면 true.
func _all_chips_revealed() -> bool:
	for child in _chip_row.get_children():
		if child is DeckCardChip:
			var chip := child as DeckCardChip
			if not chip.is_face_up():
				return false
	return _chip_row.get_child_count() > 0


## 미개봉 팩 중 가장 인덱스를 찾는다. 없으면 -1.
func _next_unopened_pack() -> int:
	for i in _pack_count:
		if i < _pack_opened.size() and not _pack_opened[i]:
			return i
	return -1


## 뷰포트 좌표 아래 칩을 찾아 플립한다.
func _try_flip_at_viewport(_viewport_pos: Vector2) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var chip := _find_chip_ancestor(hovered)
	if chip != null:
		chip.flip_to_front()


## 노드 상위로 DeckCardChip을 찾는다.
func _find_chip_ancestor(node: Node) -> DeckCardChip:
	var n: Node = node
	while n:
		if n is DeckCardChip:
			return n as DeckCardChip
		n = n.get_parent()
	return null


## 칩 단계: 다음 미개봉 팩 프리뷰 또는 finished.
func _advance_or_finish() -> void:
	if _phase != Phase.CHIPS:
		return
	if not _all_chips_revealed():
		return
	var next_i := _next_unopened_pack()
	if next_i < 0:
		finished.emit()
		queue_free()
		return
	_begin_pack_preview(next_i)


## 좌클릭: 다팩 그리드=1팩부터 시작 · 칩 단계=다음 팩/완료.
func _on_click_catcher_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _phase == Phase.MULTI_GRID:
				_begin_pack_preview(0)
				accept_event()
				return
			_advance_or_finish()
			accept_event()


## 단팩 이미지 클릭 → 상단 찢기 연출 시작.
func _on_pack_visual_gui_input(event: InputEvent) -> void:
	if _phase != Phase.PACK_IDLE:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_start_pack_tear_fx()
			accept_event()


## 교체 가능: 팩 상단을 위로 들어 올리며 페이드 + 절단선 슬래시.
## 텍스처를 TEAR_FRAC 비율로 나눈 TextureRect 두 장으로 연출한다.
func _start_pack_tear_fx() -> void:
	if _phase != Phase.PACK_IDLE:
		return
	_phase = Phase.TEARING
	_kill_pack_glow_tween()
	_kill_pack_enter_tween()
	_kill_tear_tween()
	var pack_size := _pack_visual.size
	if pack_size.x <= 1.0 or pack_size.y <= 1.0:
		pack_size = _pack_visual.custom_minimum_size
	var global_pos := _pack_visual.get_global_rect().position
	var pack_pos := global_pos - global_position
	_pack_preview_root.visible = false
	_pack_visual.visible = false
	_pack_frame.visible = false
	_clear_tear_host()
	_tear_host.visible = true
	var tear_h := maxf(1.0, floorf(pack_size.y * TEAR_FRAC))
	var stay_h := maxf(1.0, pack_size.y - tear_h)
	var cut_y := pack_pos.y + tear_h
	var tex_size := Vector2(1.0, 1.0)
	if _pack_tex != null:
		tex_size = _pack_tex.get_size()
	var tear_tex_h := maxf(1.0, floorf(tex_size.y * TEAR_FRAC))
	var stay_tex_h := maxf(1.0, tex_size.y - tear_tex_h)
	# 하단 80%: 고정 이미지.
	var stay_piece := _make_tear_piece(
		Rect2(pack_pos.x, cut_y, pack_size.x, stay_h),
		Rect2(0.0, tear_tex_h, tex_size.x, stay_tex_h)
	)
	# 상단 20%: 리프트·회전 대상.
	var top_piece := _make_tear_piece(
		Rect2(pack_pos.x, pack_pos.y, pack_size.x, tear_h),
		Rect2(0.0, 0.0, tex_size.x, tear_tex_h)
	)
	top_piece.pivot_offset = Vector2(top_piece.size.x * 0.1, top_piece.size.y)
	_tear_host.add_child(stay_piece)
	_tear_host.add_child(top_piece)
	var slash := _make_tear_slash_light(
		pack_pos.x,
		cut_y,
		pack_size.x,
		_max_rarity_of_pack(_pack_index)
	)
	_tear_host.add_child(slash)
	_tear_tween = create_tween()
	_tear_tween.set_parallel(true)
	_tear_tween.tween_property(
		top_piece, "position:y", top_piece.position.y - TEAR_LIFT_PX, TEAR_LIFT_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tear_tween.tween_property(
		top_piece, "rotation", deg_to_rad(TEAR_LIFT_ROT_DEG), TEAR_LIFT_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tear_tween.tween_property(
		top_piece, "modulate:a", 0.0, TEAR_FADE_SEC
	).set_delay(TEAR_LIFT_SEC * TEAR_FADE_DELAY_RATIO).set_ease(Tween.EASE_IN)
	var slash_end_x := pack_pos.x + pack_size.x + TEAR_SLASH_OVERSHOOT
	_tear_tween.tween_property(
		slash, "position:x", slash_end_x, TEAR_SLASH_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tear_tween.tween_property(
		slash, "modulate:a", 0.0, TEAR_SLASH_SEC * 0.5
	).set_delay(TEAR_SLASH_SEC * 0.5).set_ease(Tween.EASE_IN)
	_tear_tween.chain().tween_callback(_on_pack_tear_finished)


## 절단선을 가로지르는 최고 레어도 accent 빛. 팩보다 좌우로 더 길게 스윕.
func _make_tear_slash_light(pack_x: float, cut_y: float, pack_w: float, tier: int) -> Control:
	var accent := CardRarity.accent_of(tier)
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.position = Vector2(
		pack_x - TEAR_SLASH_W - TEAR_SLASH_OVERSHOOT,
		cut_y - TEAR_SLASH_H * 0.5
	)
	host.size = Vector2(TEAR_SLASH_W, TEAR_SLASH_H)
	host.z_index = 8
	# 바깥 글로우(강하게 해서 직사각 실루엣을 덮음).
	var glow := Panel.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_sb := StyleBoxFlat.new()
	glow_sb.bg_color = Color(accent.r, accent.g, accent.b, 0.35)
	glow_sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.85)
	glow_sb.shadow_size = 36
	glow_sb.corner_radius_top_left = 10
	glow_sb.corner_radius_top_right = 10
	glow_sb.corner_radius_bottom_right = 10
	glow_sb.corner_radius_bottom_left = 10
	glow.add_theme_stylebox_override("panel", glow_sb)
	host.add_child(glow)
	# 코어 빔.
	var core := ColorRect.new()
	core.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	core.offset_top = TEAR_SLASH_H * 0.28
	core.offset_bottom = -TEAR_SLASH_H * 0.28
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	core.color = Color(accent.r, accent.g, accent.b, 0.95).lightened(0.35)
	host.add_child(core)
	# 하이라이트 흰 심.
	var tip := ColorRect.new()
	tip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tip.offset_top = TEAR_SLASH_H * 0.38
	tip.offset_bottom = -TEAR_SLASH_H * 0.38
	tip.offset_left = TEAR_SLASH_W * 0.35
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.color = Color(1, 1, 1, 0.85)
	host.add_child(tip)
	return host


## 팩 텍스처 일부(region)를 표시 크기(piece_rect)에 그대로 맞춘 조각.
func _make_tear_piece(piece_rect: Rect2, tex_region: Rect2) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = _pack_tex
	atlas.region = tex_region
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# KEEP_SIZE는 최소 크기=텍스처 픽셀이라 조각이 확대되어 보임. IGNORE로 표시 박스만 사용.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.custom_minimum_size = piece_rect.size
	art.size = piece_rect.size
	art.position = piece_rect.position
	art.texture = atlas
	return art


## 찢기 종료 → 칩 개봉 화면.
func _on_pack_tear_finished() -> void:
	_kill_tear_tween()
	_clear_tear_host()
	_show_current_pack_chips()


## 팩 프레임 약한 펄스(칩 뒷면 힌트와 동일 톤).
func _start_pack_frame_pulse() -> void:
	if not _pack_frame.visible:
		return
	_kill_pack_glow_tween()
	_pack_glow_tween = create_tween()
	_pack_glow_tween.set_loops()
	_pack_glow_tween.tween_property(
		_pack_frame, "modulate:a", 1.0, BACK_GLOW_PULSE_SEC * 0.5
	)
	_pack_glow_tween.tween_property(
		_pack_frame, "modulate:a", 0.7, BACK_GLOW_PULSE_SEC * 0.5
	)


## 찢기 트윈을 중단한다.
func _kill_tear_tween() -> void:
	if _tear_tween != null and _tear_tween.is_valid():
		_tear_tween.kill()
	_tear_tween = null


## 팩 등장 슬라이드 트윈을 중단한다.
func _kill_pack_enter_tween() -> void:
	if _pack_enter_tween != null and _pack_enter_tween.is_valid():
		_pack_enter_tween.kill()
	_pack_enter_tween = null


## 다팩 그리드 등장 트윈을 중단한다.
func _kill_grid_enter_tween() -> void:
	if _grid_enter_tween != null and _grid_enter_tween.is_valid():
		_grid_enter_tween.kill()
	_grid_enter_tween = null


## 칩 행 등장 트윈을 중단한다.
func _kill_chip_enter_tween() -> void:
	if _chip_enter_tween != null and _chip_enter_tween.is_valid():
		_chip_enter_tween.kill()
	_chip_enter_tween = null


## 팩 프레임 펄스 트윈을 중단한다.
func _kill_pack_glow_tween() -> void:
	if _pack_glow_tween != null and _pack_glow_tween.is_valid():
		_pack_glow_tween.kill()
	_pack_glow_tween = null


## Skip: 남은 팩·플립·찢기를 건너뛰고 결과 화면으로 이동한다.
func _on_skip_pressed() -> void:
	_swipe_active = false
	_kill_tear_tween()
	_kill_pack_enter_tween()
	_kill_grid_enter_tween()
	_kill_chip_enter_tween()
	_kill_pack_glow_tween()
	_clear_tear_host()
	finished.emit()
	queue_free()


## 앞면 칩 정보 요청을 상점으로 전달한다.
func _on_chip_info_requested(card_name: String, rarity: int) -> void:
	chip_info_requested.emit(card_name, rarity)
