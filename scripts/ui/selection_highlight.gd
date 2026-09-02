class_name SelectionHighlight
extends RefCounted
## 선택 후보/확정 하이라이트 스타일.
## 월드 카드·슬롯 오버레이와 UI 셀 링이 이 상수를 공유한다.
##
## ── 조정 방법 (여기만 바꾸면 됨) ──
## - COLOR_CHOSEN / COLOR_CANDIDATE — 확정 · 미선택(후보) 테두리색
## - BORDER_WIDTH_CHOSEN / BORDER_WIDTH_CANDIDATE — 테두리 두께(px)
## - OVERLAY_OUTSET — 카드/슬롯 바운드보다 바깥으로 키울 거리(px).
##   양수면 테두리가 카드 면을 덜 가림. 키울수록 링이 바깥으로 커짐.
## - UI_CELL_BORDER_* — 악세서리·덱 격자 셀 선택 링 (시안)
##
## 월드 오버레이: configure_world_overlay → size = base + outset*2 (바깥 확장)
## UI 셀 링: configure_control_inset_ring → offset를 음수로 바깥 확장

const COLOR_CHOSEN := Color(1, 1, 0, 0.95)
## 미선택(후보) — 초록.
const COLOR_CANDIDATE := Color(0.2, 0.9, 0.35, 0.95)
## UI 격자 셀(악세서리·덱 선택) 선택 링 — 시안 계열. 여기서 조정.
const UI_CELL_BORDER_SELECTED := Color(0.22, 0.87, 0.95, 0.95)
const UI_CELL_BORDER_WIDTH := 3
const UI_CELL_RING_OUTSET := 2.0
const BORDER_WIDTH_CHOSEN := 4
const BORDER_WIDTH_CANDIDATE := 5
## 하이라이트를 카드/슬롯 바깥으로 키움 (안쪽 inset 대신).
const OVERLAY_OUTSET := 6.0
## 스프라이트 미확인 시 폴백 — Area2D CollisionShape(158×220)와 동일.
const OVERLAY_BASE_SIZE := Vector2(158, 220)


static func make_ui_cell_selected_stylebox() -> StyleBoxFlat:
	return _make_border_stylebox(UI_CELL_BORDER_SELECTED, UI_CELL_BORDER_WIDTH)


## 악세서리/덱 격자 셀 선택 링 Panel을 보장하고 on/off 한다.
static func set_ui_cell_selected(cell: Control, ring: Panel, on: bool) -> Panel:
	var panel := ring
	if panel == null and cell != null:
		panel = cell.get_node_or_null("SelectionRing") as Panel
	if panel == null and cell != null:
		panel = Panel.new()
		panel.name = "SelectionRing"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.visible = false
		cell.add_child(panel)
		configure_control_inset_ring(panel, UI_CELL_RING_OUTSET)
		panel.add_theme_stylebox_override("panel", make_ui_cell_selected_stylebox())
	if panel != null:
		panel.visible = on
	return panel


static func make_chosen_stylebox() -> StyleBoxFlat:
	return _make_border_stylebox(COLOR_CHOSEN, BORDER_WIDTH_CHOSEN)


static func make_candidate_stylebox() -> StyleBoxFlat:
	return _make_border_stylebox(COLOR_CANDIDATE, BORDER_WIDTH_CANDIDATE)


## 하위 호환 — 기존 호출부는 선택 확정(실선 노랑)과 동일.
static func make_border_stylebox() -> StyleBoxFlat:
	return make_chosen_stylebox()


## Sprite2D 텍스처×scale = 화면에 보이는 카드 이미지 크기.
static func overlay_size_from_sprite(sprite: Sprite2D) -> Vector2:
	if sprite == null or sprite.texture == null:
		return OVERLAY_BASE_SIZE
	var tex_size := sprite.texture.get_size()
	var s := sprite.scale.abs()
	var size := Vector2(tex_size.x * s.x, tex_size.y * s.y)
	if size.x <= 1.0 or size.y <= 1.0:
		return OVERLAY_BASE_SIZE
	return size


## 필드 카드/슬롯용 Panel — base_size보다 OUTSET만큼 바깥으로 키워 테두리가 면을 가리지 않게.
static func configure_world_overlay(panel: Panel, base_size: Vector2 = OVERLAY_BASE_SIZE) -> void:
	var outset := OVERLAY_OUTSET
	var size := base_size + Vector2(outset, outset) * 2.0
	if size.x < 8.0 or size.y < 8.0:
		size = base_size
	# Node2D 아래 Control은 offset으로 잡는 편이 size만보다 안정적.
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Control(셀 등) 링 — FULL_RECT에서 outset만큼 바깥으로 확장.
## outset_override < 0 이면 OVERLAY_OUTSET 사용.
static func configure_control_inset_ring(panel: Control, outset_override: float = -1.0) -> void:
	var pad := OVERLAY_OUTSET if outset_override < 0.0 else outset_override
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = -pad
	panel.offset_top = -pad
	panel.offset_right = pad
	panel.offset_bottom = pad
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _make_border_stylebox(color: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.draw_center = false
	style.set_border_width_all(width)
	style.border_color = color
	style.set_expand_margin_all(0)
	style.set_content_margin_all(0)
	return style
