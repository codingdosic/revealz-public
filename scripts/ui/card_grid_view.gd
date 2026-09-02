class_name CardGridView
extends RefCounted
## ZoneBrowse 등 2열 카드 그리드. 셀=graveyard_card_cell.
##
## 튜닝: COMPACT_CELL_SIZE — ZoneBrowse 폭(SIDEBAR_WIDTH−마진−스크롤바)에 맞출 것.
## 2*x + h_separation(6) ≲ 174 (VScrollbar 여유 포함).

const CELL_SCENE := preload("res://scenes/ui/graveyard_card_cell.tscn")
const GRID_COLUMNS := 2
## 묘지/밴 사이드바 2열. x를 키우면 우측 열 잘림·가로 스크롤 생김.
const COMPACT_CELL_SIZE := Vector2(84, 100)


## ZoneBrowse 등 2열 카드 그리드를 비운다.
static func clear_grid(grid: GridContainer, cells: Array) -> void:
	for cell in cells:
		if is_instance_valid(cell):
			cell.queue_free()
	cells.clear()
	if grid:
		for child in grid.get_children():
			child.queue_free()


## 카드를 셀로 채운다. chrome 은 셀 소유 테두리색용. 유효 장수 반환.
static func populate_view(
	grid: GridContainer,
	cells: Array,
	cards: Array,
	on_cell_pressed: Callable,
	chrome: UiChromeStyle = null
) -> int:
	clear_grid(grid, cells)
	if grid == null:
		return 0
	grid.columns = GRID_COLUMNS
	var resolved := UiChromeStyle.resolve(chrome)
	var valid_count := 0
	for card in cards:
		if not is_instance_valid(card):
			continue
		valid_count += 1
		var cell: PanelContainer = CELL_SCENE.instantiate()
		cell.custom_minimum_size = COMPACT_CELL_SIZE
		cell.set("chrome_style", resolved)
		grid.add_child(cell)
		cell.setup(card, false, false, false)
		cells.append(cell)
		if on_cell_pressed.is_valid():
			cell.card_pressed.connect(on_cell_pressed)
	return valid_count
