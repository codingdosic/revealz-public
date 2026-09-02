extends PanelContainer
## 존(묘지·배니시·스택) 브라우즈 사이드바 (우측).
## 틀·닫기=SidebarShell. 배경·테두리=이 패널. 그리드=graveyard_card_cell + CardGridView.

@export var chrome_style: UiChromeStyle

@onready var _title: Label = $Margin/VBox/TitleLabel
@onready var _scroll: ScrollContainer = $Margin/VBox/ScrollContainer
@onready var _grid: GridContainer = $Margin/VBox/ScrollContainer/GridContainer
@onready var _empty_label: Label = $Margin/VBox/EmptyLabel

var _cells: Array = []
var _game_ui: Node


## 부트: 숨김 · 크롬.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 10
	visible = false
	apply_chrome(chrome_style)


## 크롬 팔레트·문구로 패널·타이틀·빈 존 라벨·스크롤바를 갱신한다.
func apply_chrome(style: UiChromeStyle) -> void:
	chrome_style = UiChromeStyle.resolve(style)
	chrome_style.apply_panel(self)
	chrome_style.apply_title_label(_title)
	chrome_style.apply_muted_label(_empty_label)
	_empty_label.text = chrome_style.get_copy().zone_empty
	if _scroll:
		chrome_style.apply_scroll_container(_scroll)


## GameUILayer 등에서 셀 클릭 → 카드정보 연결용.
func bind_game_ui(game_ui: Node) -> void:
	_game_ui = game_ui


## 존 목록을 채우고 사이드바를 연다.
func show_zone(title_text: String, cards: Array) -> void:
	_title.text = title_text
	var count := CardGridView.populate_view(_grid, _cells, cards, _on_cell_pressed, chrome_style)
	_empty_label.visible = count == 0
	_scroll.visible = count > 0
	visible = true
	SidebarContentUtil.sync_shell(self, true)


## 이미 열린 존을 같은 API로 갱신한다.
func refresh_zone(title_text: String, cards: Array) -> void:
	if not visible:
		return
	show_zone(title_text, cards)


## 사이드바·그리드를 닫는다. 패널 visible은 셸 close 연출 후에 꺼진다.
func hide_sidebar() -> void:
	var shell := SidebarContentUtil.find_shell(self)
	if shell != null and shell.visible:
		shell.call("close", "content")
		return
	visible = false
	CardGridView.clear_grid(_grid, _cells)


## 셸 또는 콘텐츠 기준 표시 여부.
func is_showing() -> bool:
	var shell := SidebarContentUtil.find_shell(self)
	if shell:
		return shell.visible
	return visible


## 셀 클릭 시 카드정보 사이드바 토글.
func _on_cell_pressed(card: Node) -> void:
	if _game_ui == null or not is_instance_valid(card):
		return
	if _game_ui.has_method("toggle_card_info") and CardInfoRules.is_sidebar_eligible(card):
		_game_ui.toggle_card_info(card)
