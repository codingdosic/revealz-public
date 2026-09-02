class_name DeckEditorScreen
extends Control
## 덱 편집 화면. 좌 정보 · 중 6×5 일러스트 · 우 검색·필터.
## 진입: DeckEditorScreen.open(id) / open_new — 목록·New/Delete는 deck_select.
## format mono|none. none은 빌딩 제한 없음.
## FilterSection: [필터|보유|정렬|취소] · 아래 검색창+지우기.
## 필터 팝업 칩은 deck_editor_screen.tscn FilterGroups에 정적 배치 (spd만 런타임).
## 정렬 팝업: 기준(획득일 더미·레어도·SPD·수량) + 오름/내림.
## HBoxContainer2 피드백은 PhaseToast. 포맷/추가/제거는 무표시.
## 룩: UiChromeStyle (단색 ScreenBg · Toolbar/Filter Section · 카드칩 미변경).


const EDITOR_SCENE := "res://scenes/screen/deck_editor_screen.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"
const LOADING_GATE_SCENE := preload("res://scenes/ui/loading_gate.tscn")
## class_name 전역 등록 전에 분석기가 못 보는 경우 대비 (이름 충돌 피함).
const CollStore := preload("res://scripts/collection_store.gd")
## CardInfo 폭 = UiShellConstants.SIDEBAR_WIDTH (인게임과 동일).
const DECK_COLS := 6
const DECK_ROWS := 5
## card_data.trigger_type 플래그: TOKEN (OPEN=1 … VANILLA=64 다음).
const TRIGGER_TOKEN := 128

## MenuHost.push_file 전에 설정하는 복귀 경로 · 열 덱.
static var pending_return_scene: String = MAIN_SCENE
static var pending_deck_id: String = ""
static var pending_open_new: bool = false

@export var chrome_style: UiChromeStyle

@onready var _info_host: Control = $HBox/LeftScroll/LeftPane
@onready var _center_pane: Control = $HBox/CenterPane
@onready var _right_pane: Control = $HBox/RightPane
@onready var _deck_section: Control = $HBox/CenterPane/DeckSection
@onready var _name_edit: LineEdit = $HBox/CenterPane/DeckSection/VBoxContainer/NameEdit
@onready var _format_combo: OptionButton = $HBox/CenterPane/ToolbarSection/TopBar/VBoxContainer/HBoxContainer/FormatCombo
@onready var _deck_host: Control = $HBox/CenterPane/DeckSection/VBoxContainer/DeckHost
@onready var _deck_scroll: ScrollContainer = $HBox/CenterPane/DeckSection/VBoxContainer/DeckHost/MarginContainer/ScrollContainer
@onready var _deck_grid: GridContainer = $HBox/CenterPane/DeckSection/VBoxContainer/DeckHost/MarginContainer/ScrollContainer/DeckGrid
@onready var _search_edit: LineEdit = $HBox/RightPane/FilterSection/VBox/SearchRow/SearchEdit
@onready var _ordering_button: Button = $HBox/RightPane/FilterSection/VBox/Bar/OrderingButton
@onready var _clear_search_button: Button = $HBox/RightPane/FilterSection/VBox/SearchRow/ClearSearchButton
@onready var _filter_popup: Control = $FilterPopup
@onready var _filter_popup_button: Button = $HBox/RightPane/FilterSection/VBox/Bar/FilterPopupButton
@onready var _own_status_button: Button = $HBox/RightPane/FilterSection/VBox/Bar/OwnStatusButton
@onready var _clear_filters_button: Button = $HBox/RightPane/FilterSection/VBox/Bar/ClearFiltersButton
@onready var _filter_popup_close: Button = $FilterPopup/Panel/Margin/VBox/TitleRow/CloseButton
@onready var _filter_popup_panel: PanelContainer = $FilterPopup/Panel
@onready var _filter_popup_title: Label = $FilterPopup/Panel/Margin/VBox/TitleRow/TitleLabel
@onready var _filter_groups: VBoxContainer = $FilterPopup/Panel/Margin/VBox/Scroll/FilterGroups
@onready var _filter_scroll: ScrollContainer = $FilterPopup/Panel/Margin/VBox/Scroll
@onready var _sort_popup: Control = $SortPopup
@onready var _sort_popup_panel: PanelContainer = $SortPopup/Panel
@onready var _sort_popup_title: Label = $SortPopup/Panel/Margin/VBox/TitleRow/TitleLabel
@onready var _sort_popup_close: Button = $SortPopup/Panel/Margin/VBox/TitleRow/CloseButton
@onready var _sort_key_title: Label = $SortPopup/Panel/Margin/VBox/KeySection/Title
@onready var _sort_key_acquire: Button = $SortPopup/Panel/Margin/VBox/KeySection/ChipFlow/Acquire
@onready var _sort_key_rarity: Button = $SortPopup/Panel/Margin/VBox/KeySection/ChipFlow/Rarity
@onready var _sort_key_spd: Button = $SortPopup/Panel/Margin/VBox/KeySection/ChipFlow/Spd
@onready var _sort_key_qty: Button = $SortPopup/Panel/Margin/VBox/KeySection/ChipFlow/Qty
@onready var _sort_dir_asc: Button = $SortPopup/Panel/Margin/VBox/DirSection/Asc
@onready var _sort_dir_desc: Button = $SortPopup/Panel/Margin/VBox/DirSection/Desc
@onready var _result_section: Control = $HBox/RightPane/ResultSection
@onready var _result_scroll: ScrollContainer = $HBox/RightPane/ResultSection/MarginContainer/ResultScroll
@onready var _results: GridContainer = $HBox/RightPane/ResultSection/MarginContainer/ResultScroll/Results
@onready var _phase_toast: PhaseToast = $PhaseToast

## OwnStatusButton 사이클: 전체 → 소지 → 미소지 → 전체.
enum OwnFilter { ALL, OWNED, UNOWNED }
## 검색 결과 정렬. DEFAULT=색→id. ACQUIRE는 더미(DEFAULT와 동일).
enum SortKey { DEFAULT, ACQUIRE, RARITY, SPD, QTY }
enum SortDir { ASC, DESC }

const _CAT_COLOR := &"color"
const _CAT_CARD_TYPE := &"cardType"
const _CAT_TYPE := &"type"
const _CAT_TRIGGER := &"trigger"
const _CAT_SPD := &"spd"
const _CAT_RARITY := &"rarity"

var _info_shell: SidebarShell = null
var _info_sidebar: Control = null
var _current: Dictionary = {}
var _return_scene: String = MAIN_SCENE
var _chip_size: Vector2 = Vector2(72, 100)
var _gate: LoadingGate
var _own_filter: OwnFilter = OwnFilter.ALL
## 카테고리별 선택값. 비어 있으면 All. 값: String 또는 int.
var _sel_colors: Dictionary = {}
var _sel_card_types: Dictionary = {}
var _sel_tribes: Dictionary = {}
var _sel_triggers: Dictionary = {}
var _sel_spds: Dictionary = {}
var _sel_rarities: Dictionary = {}
var _filter_chip_buttons: Array[Button] = []
var _sort_key: SortKey = SortKey.DEFAULT
var _sort_dir: SortDir = SortDir.ASC
var _sort_key_buttons: Array[Button] = []


## 기존 덱 id로 에디터를 연다. id 비우면 첫 선택가능 덱(prepare 직행 폴백).
static func open(tree: SceneTree, return_scene: String = MAIN_SCENE, deck_id: String = "") -> void:
	if tree == null:
		return
	pending_return_scene = return_scene
	pending_deck_id = deck_id.strip_edges()
	pending_open_new = false
	MenuHost.push_file(EDITOR_SCENE)


## 빈 신규 유저 덱으로 에디터를 연다 (+ 셀 경로).
static func open_new(tree: SceneTree, return_scene: String = MAIN_SCENE) -> void:
	if tree == null:
		return
	pending_return_scene = return_scene
	pending_deck_id = ""
	pending_open_new = true
	MenuHost.push_file(EDITOR_SCENE)


## 사이드바·포맷·필터·덱을 초기화한다. 카탈로그는 LoadingGate 아래 비동기 로드.
func _ready() -> void:
	_return_scene = pending_return_scene
	var open_new := pending_open_new
	var deck_id := pending_deck_id
	pending_return_scene = MAIN_SCENE
	pending_open_new = false
	pending_deck_id = ""
	_apply_ui_chrome()
	_gate = LOADING_GATE_SCENE.instantiate() as LoadingGate
	add_child(_gate)
	if _gate.has_method("apply_chrome"):
		_gate.call("apply_chrome", chrome_style)
	_setup_info_sidebar()
	_populate_format_combo()
	_setup_section_dnd()
	_deck_host.resized.connect(_on_deck_host_resized)
	var needs_catalog := CardRegistry.catalog_count() <= 0
	if needs_catalog:
		_gate.show_gate("카드를 불러오는 중…", false, false)
		await CardRegistry.ensure_loaded_async(_on_catalog_load_progress)
		_gate.hide_gate()
	else:
		# 이미 로드됨 — 동기 no-op으로 플래그만 맞춤.
		CardRegistry.ensure_loaded()
	_setup_filter_groups()
	_setup_sort_popup()
	CollStore.ensure_loaded()
	_sync_status_button_label()
	_apply_pending_deck(open_new, deck_id)
	call_deferred("_on_deck_host_resized")


## pending_open_new / deck_id / 폴백(첫 선택가능 덱)으로 편집 대상을 연다.
func _apply_pending_deck(open_new: bool, deck_id: String) -> void:
	if open_new:
		_begin_new_deck()
		return
	if not deck_id.is_empty():
		_load_deck_by_id(deck_id)
		return
	var list := DeckStore.list_selectable_decks()
	if list.size() > 0:
		_load_deck_by_id(String(list[0].get("id", "")))
	else:
		_begin_new_deck()


## 중앙·우측 정적 UI + 토스트에 크롬 적용. 루트에 ScreenBg. 카드칩은 제외.
func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_background(self)
	if _center_pane:
		chrome_style.apply_screen_tree(_center_pane, false)
	if _right_pane:
		chrome_style.apply_screen_tree(_right_pane, false)
	var left_scroll := $HBox/LeftScroll as ScrollContainer
	if left_scroll:
		chrome_style.apply_scroll_container(left_scroll)
	var back := get_node_or_null("BackButton") as Button
	if back:
		chrome_style.apply_back_button(back)
	if _phase_toast and _phase_toast.has_method("apply_chrome"):
		_phase_toast.call("apply_chrome", chrome_style)
	_apply_filter_popup_chrome()


## 필터·정렬 팝업 패널·버튼·칩에 크롬.
func _apply_filter_popup_chrome() -> void:
	if chrome_style == null:
		return
	if _filter_popup_panel:
		chrome_style.apply_panel(_filter_popup_panel)
	if _filter_popup_title:
		chrome_style.apply_title_label(_filter_popup_title)
	if _filter_scroll:
		chrome_style.apply_scroll_container(_filter_scroll)
	if _sort_popup_panel:
		chrome_style.apply_panel(_sort_popup_panel)
	if _sort_popup_title:
		chrome_style.apply_title_label(_sort_popup_title)
	if _sort_key_title:
		chrome_style.apply_muted_label(_sort_key_title)
	chrome_style.apply_buttons([
		_own_status_button, _clear_filters_button,
		_filter_popup_close, _clear_search_button, _sort_popup_close,
	])
	if _search_edit:
		chrome_style.apply_line_edit(_search_edit)
	_refresh_filter_glow_chrome()


## 선택 칩·필터/정렬 버튼 테두리 발광 갱신.
func _refresh_filter_glow_chrome() -> void:
	if chrome_style == null:
		return
	for chip in _filter_chip_buttons:
		if is_instance_valid(chip):
			chrome_style.apply_filter_chip(chip, chip.button_pressed)
	for chip in _sort_key_buttons:
		if is_instance_valid(chip):
			chrome_style.apply_filter_chip(chip, chip.button_pressed)
	if _sort_dir_asc:
		chrome_style.apply_filter_chip(_sort_dir_asc, _sort_dir_asc.button_pressed)
	if _sort_dir_desc:
		chrome_style.apply_filter_chip(_sort_dir_desc, _sort_dir_desc.button_pressed)
	if _filter_popup_button:
		chrome_style.apply_filter_gate_button(_filter_popup_button, _has_active_popup_filters())
	if _ordering_button:
		chrome_style.apply_filter_gate_button(_ordering_button, _has_active_sort())


## 팝업 다중선택 중 하나라도 켜져 있으면 true (보유/검색 제외).
func _has_active_popup_filters() -> bool:
	return (
		not _sel_colors.is_empty()
		or not _sel_card_types.is_empty()
		or not _sel_tribes.is_empty()
		or not _sel_triggers.is_empty()
		or not _sel_spds.is_empty()
		or not _sel_rarities.is_empty()
	)


## 기본(색→id)이 아닌 실효 정렬이면 true. 획득일 더미는 하이라이트 없음.
func _has_active_sort() -> bool:
	return (
		_sort_key == SortKey.RARITY
		or _sort_key == SortKey.SPD
		or _sort_key == SortKey.QTY
	)



## 카탈로그 로드 진행 → 게이트 문구 %.
func _on_catalog_load_progress(done: int, total: int, _label: String) -> void:
	if _gate == null:
		return
	var t := maxi(total, 1)
	var pct := int(round((100.0 * float(done)) / float(t)))
	_gate.update_message("카드를 불러오는 중… %d%%" % pct)


## HBoxContainer2용 토스트. Back·포맷/가감은 호출하지 않음.
func _toast(message: String) -> void:
	if _phase_toast == null:
		return
	_phase_toast.play(message)


## 좌측 스크롤에 embedded SidebarShell + 동일 CardInfo 내용을 붙인다.
## 폭=SIDEBAR_WIDTH. 상단 inset으로 좌상단 Back과 겹치지 않게.
func _setup_info_sidebar() -> void:
	var left_scroll := $HBox/LeftScroll as ScrollContainer
	if left_scroll:
		left_scroll.custom_minimum_size.x = UiShellConstants.SIDEBAR_WIDTH
	# HBox offset_top(8) + margin ≈ 인게임 SIDEBAR_TOP_INSET 아래부터 (Back 12+40 클리어).
	if _info_host is MarginContainer:
		var top_margin := maxi(
			int(UiShellConstants.SIDEBAR_TOP_INSET),
			int(UiShellConstants.SCREEN_BACK_MARGIN + UiShellConstants.SCREEN_BACK_SIZE - 8.0)
		)
		(_info_host as MarginContainer).add_theme_constant_override("margin_top", top_margin)
		(_info_host as MarginContainer).add_theme_constant_override(
			"margin_bottom", int(UiShellConstants.SIDEBAR_BOTTOM_INSET)
		)
	var mounted := CardInfoMount.mount_embedded(_info_host, chrome_style)
	_info_shell = mounted.get("shell") as SidebarShell
	_info_sidebar = mounted.get("content") as Control
	_info_shell.closed.connect(_on_info_shell_closed)
	# outside-dismiss + set_input_as_handled 가 칩 클릭을 가로채
	# 사이드바 갱신이 막힘 → 칩 위 클릭은 dismiss 면제 (인게임과 동일 패턴).
	var policy: UiDismissPolicy = _info_shell.get_dismiss_policy()
	policy.is_outside_click_exempt = _is_info_outside_click_exempt


## DetailRoot/줌이 떠 있으면 바깥 클릭으로 사이드바를 닫지 않는다.
## (카드 일러 우측은 셸 rect 밖이라, 면제 없으면 확대 대신 사이드바가 닫힘.)
## 덱/검색 칩 위 클릭도 사이드바 outside-dismiss 제외.
func _is_info_outside_click_exempt(global_pos: Vector2) -> bool:
	if _info_sidebar and _info_sidebar.has_method("is_detail_open") and _info_sidebar.is_detail_open():
		return true
	for host in [_deck_grid, _results]:
		if host == null:
			continue
		for child in host.get_children():
			if child is DeckCardChip:
				var chip := child as DeckCardChip
				if chip.card_name.is_empty():
					continue
				if chip.get_global_rect().has_point(global_pos):
					return true
	return false


## 사이드바 셸이 content 이유로 닫히면 no-op, 그 외 hide.
func _on_info_shell_closed(reason: String) -> void:
	if reason == "content":
		return
	if _info_sidebar and _info_sidebar.has_method("hide_sidebar"):
		_info_sidebar.hide_sidebar()


## 정보 사이드바를 숨긴다.
func _hide_info_sidebar() -> void:
	if _info_sidebar and _info_sidebar.has_method("hide_sidebar"):
		_info_sidebar.hide_sidebar()


## Format 콤보: mono / none.
func _populate_format_combo() -> void:
	_format_combo.clear()
	_format_combo.add_item("mono", 0)
	_format_combo.set_item_metadata(0, DeckStore.FORMAT_MONO)
	_format_combo.add_item("none", 1)
	_format_combo.set_item_metadata(1, DeckStore.FORMAT_NONE)
	_format_combo.select(0)


## DeckSection↔ResultSection DnD.
## Result→Deck = 추가, Deck→Result = 제거. 섹션·스크롤·그리드·칩에 forwarding.
func _setup_section_dnd() -> void:
	var targets: Array = [
		_deck_section,
		_deck_host,
		_deck_host.get_node_or_null("MarginContainer") if _deck_host else null,
		_deck_scroll,
		_deck_grid,
		_result_section,
		_result_section.get_node_or_null("MarginContainer") if _result_section else null,
		_result_scroll,
		_results,
	]
	for node in targets:
		if node is Control:
			_forward_section_drop(node as Control)


## get_drag는 비워 기존 _get_drag_data 유지. can_drop/drop만 섹션 규칙으로 위임.
func _forward_section_drop(control: Control) -> void:
	if control == null:
		return
	control.set_drag_forwarding(Callable(), _section_can_drop, _section_drop)


## 글로벌 좌표가 DeckSection(중앙 덱 패널) 안인지.
func _is_over_deck_section(global_pos: Vector2) -> bool:
	return _deck_section != null and _deck_section.get_global_rect().has_point(global_pos)


## 글로벌 좌표가 ResultSection(검색 결과 패널) 안인지.
func _is_over_result_section(global_pos: Vector2) -> bool:
	return _result_section != null and _result_section.get_global_rect().has_point(global_pos)


## 섹션 DnD 허용.
## - 검색 칩 → DeckSection: 추가
## - 덱 슬롯 → ResultSection: 제거
func _section_can_drop(_at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d := data as Dictionary
	if String(d.get("card_name", "")).is_empty():
		return false
	var pos := get_global_mouse_position()
	if _is_deck_slot_drag(data):
		return _is_over_result_section(pos)
	return _is_over_deck_section(pos)


## 섹션 DnD 처리 (규칙同 _section_can_drop).
func _section_drop(_at: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d := data as Dictionary
	var pos := get_global_mouse_position()
	if _is_deck_slot_drag(data):
		if _is_over_result_section(pos):
			_remove_at_slot(int(d.get("slot_index", -1)))
	elif _is_over_deck_section(pos):
		_try_add_card(String(d.get("card_name", "")), int(d.get("rarity", CardRarity.Tier.N)))


## 드래그 데이터가 덱 슬롯에서 시작했는지.
func _is_deck_slot_drag(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d := data as Dictionary
	return bool(d.get("is_deck_slot", false)) and int(d.get("slot_index", -1)) >= 0


## 씬에 배치된 필터 섹션·칩을 연결한다. spd만 카탈로그 기준으로 ChipFlow에 채움.
func _setup_filter_groups() -> void:
	if _filter_groups == null:
		return
	_filter_chip_buttons.clear()
	_populate_spd_chips()
	for section in _filter_groups.get_children():
		if not (section is Control) or not section.has_meta("filter_category"):
			continue
		var category := StringName(section.get_meta("filter_category"))
		var flow := section.get_node_or_null("ChipFlow") as HFlowContainer
		if flow == null:
			continue
		var title := section.get_node_or_null("Title") as Label
		if title and chrome_style:
			chrome_style.apply_muted_label(title)
		for child in flow.get_children():
			var btn := child as Button
			if btn == null or not btn.has_meta("filter_value"):
				continue
			_disconnect_all_toggled(btn)
			var value: Variant = btn.get_meta("filter_value")
			btn.toggled.connect(_on_filter_chip_toggled.bind(category, value))
			_filter_chip_buttons.append(btn)
	_sync_filter_chip_pressed()
	_apply_filter_popup_chrome()


func _disconnect_all_toggled(btn: Button) -> void:
	for c in btn.toggled.get_connections():
		btn.toggled.disconnect(c["callable"])


## spd ChipFlow만 런타임 채움 (카탈로그 의존). 다른 카테고리는 씬 정적 칩.
func _populate_spd_chips() -> void:
	var section := _filter_groups.get_node_or_null("SpdSection") as Control
	if section == null:
		return
	var flow := section.get_node_or_null("ChipFlow") as HFlowContainer
	if flow == null:
		return
	while flow.get_child_count() > 0:
		var child := flow.get_child(0)
		flow.remove_child(child)
		child.free()
	var speeds: Array[int] = []
	for card_name in CardRegistry.list_card_names_for_filter("all", true):
		var data := CardRegistry.get_by_name(card_name)
		if data == null:
			continue
		var spd := int(data.stat_spd)
		if not speeds.has(spd):
			speeds.append(spd)
	speeds.sort()
	for spd in speeds:
		var btn := Button.new()
		btn.text = str(spd)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_meta("filter_value", spd)
		flow.add_child(btn)


## 선택 딕셔너리에 맞춰 씬 칩 pressed 상태를 맞춘다.
func _sync_filter_chip_pressed() -> void:
	for section in _filter_groups.get_children():
		if not section.has_meta("filter_category"):
			continue
		var category := StringName(section.get_meta("filter_category"))
		var bag := _selection_bag(category)
		var flow := section.get_node_or_null("ChipFlow") as HFlowContainer
		if flow == null:
			continue
		for child in flow.get_children():
			var btn := child as Button
			if btn == null or not btn.has_meta("filter_value"):
				continue
			btn.set_pressed_no_signal(bag.has(btn.get_meta("filter_value")))
	_refresh_filter_glow_chrome()


## 칩 토글 — 카테고리 내 다중 선택(OR). 비우면 All.
func _on_filter_chip_toggled(pressed: bool, category: StringName, value: Variant) -> void:
	var bag := _selection_bag(category)
	if bag == null:
		return
	if pressed:
		bag[value] = true
	else:
		bag.erase(value)
	_refresh_filter_glow_chrome()
	_refresh_search_results()


func _selection_bag(category: StringName) -> Dictionary:
	match category:
		_CAT_COLOR:
			return _sel_colors
		_CAT_CARD_TYPE:
			return _sel_card_types
		_CAT_TYPE:
			return _sel_tribes
		_CAT_TRIGGER:
			return _sel_triggers
		_CAT_SPD:
			return _sel_spds
		_CAT_RARITY:
			return _sel_rarities
		_:
			return {}


## id로 덱을 로드해 그리드·이름·포맷 UI를 채운다.
func _load_deck_by_id(deck_id: String) -> void:
	_current = DeckStore.load_deck(deck_id)
	if _current.is_empty():
		push_warning("[DeckEditor] Failed to load deck id=%s" % deck_id)
		_begin_new_deck()
		return
	_name_edit.text = String(_current.get("name", ""))
	var readonly := bool(_current.get("readonly", false))
	_name_edit.editable = not readonly
	_format_combo.disabled = readonly
	_select_format(String(_current.get("format", DeckStore.FORMAT_MONO)))
	_rebuild_deck_grid()
	_refresh_search_results()
	call_deferred("_on_deck_host_resized")


## 빈 유저 덱 초안을 연다 (미저장). 선택 화면 + 셀에서 진입.
func _begin_new_deck() -> void:
	_current = DeckStore.make_empty_user_deck("black", "New Deck")
	_name_edit.text = String(_current.get("name", ""))
	_name_edit.editable = true
	_format_combo.disabled = false
	_select_format(String(_current.get("format", DeckStore.FORMAT_MONO)))
	_rebuild_deck_grid()
	_refresh_search_results()
	_toast("New deck (unsaved)")
	call_deferred("_on_deck_host_resized")


## FormatCombo UI를 format 문자열에 맞춘다 (시그널 없이).
func _select_format(format: String) -> void:
	var key := DeckStore.normalize_format(format)
	for i in _format_combo.item_count:
		if String(_format_combo.get_item_metadata(i)) == key:
			_format_combo.select(i)
			return


## 현재 포맷 키.
func _current_format() -> String:
	return DeckStore.normalize_format(String(_current.get("format", DeckStore.FORMAT_MONO)))


## 덱 그리드 재구성. mono=30슬롯, none=보유 장수만. 슬롯에 카피 등급 표시.
func _rebuild_deck_grid() -> void:
	for child in _deck_grid.get_children():
		child.queue_free()
	var names := DeckStore.card_names_of(_current)
	var rarities := DeckStore.card_rarities_of(_current)
	var format := _current_format()
	if format == DeckStore.FORMAT_MONO:
		for i in DeckStore.DECK_SIZE:
			var card_name := names[i] if i < names.size() else ""
			var rarity := rarities[i] if i < rarities.size() else CardRarity.Tier.N
			_deck_grid.add_child(_make_chip(card_name, true, i, _chip_size, rarity))
	else:
		for i in names.size():
			var rarity := rarities[i] if i < rarities.size() else CardRarity.Tier.N
			_deck_grid.add_child(_make_chip(names[i], true, i, _chip_size, rarity))
		_deck_grid.add_child(_make_chip("", true, names.size(), _chip_size, CardRarity.Tier.N))


## 검색 결과: 보유 등급마다 칩 분리. 미소지는 흑백 1칩(N).
## 카테고리 내 다중선택은 OR, 카테고리 간은 AND. 선택 없음=All.
func _refresh_search_results() -> void:
	for child in _results.get_children():
		child.queue_free()
	var names: Array[String] = CardRegistry.list_card_names_for_filter("all", true)
	var query := _search_edit.text.strip_edges().to_lower()
	var entries: Array[Dictionary] = []
	for card_name in names:
		if not query.is_empty() and not card_name.to_lower().contains(query):
			continue
		if _is_token_card_name(card_name):
			continue
		var data := CardRegistry.get_by_name(card_name)
		if data == null:
			continue
		if not _passes_own_filter(card_name):
			continue
		if not _sel_colors.is_empty():
			var color_key := CardRegistry.color_key_for_card_name(card_name)
			if not _sel_colors.has(color_key):
				continue
		if not _sel_card_types.is_empty() and not _sel_card_types.has(String(data.card_type)):
			continue
		if not _sel_tribes.is_empty() and not _sel_tribes.has(String(data.type)):
			continue
		if not _sel_triggers.is_empty():
			var flags := int(data.trigger_type)
			var hit := false
			for flag in _sel_triggers.keys():
				if (flags & int(flag)) != 0:
					hit = true
					break
			if not hit:
				continue
		if not _sel_spds.is_empty() and not _sel_spds.has(int(data.stat_spd)):
			continue
		_append_search_entries_for_card(entries, card_name, int(data.id))
	entries.sort_custom(_compare_search_entries)
	for entry in entries:
		_results.add_child(
			_make_chip(
				String(entry.get("name", "")),
				false,
				-1,
				_chip_size,
				int(entry.get("rarity", CardRarity.Tier.N))
			)
		)


## 보유 등급마다 검색 엔트리 추가. 미소지면 N 1건(레어 필터 통과 시).
func _append_search_entries_for_card(entries: Array[Dictionary], card_name: String, card_id: int) -> void:
	var any_owned := CollStore.owns_any(card_id)
	if any_owned:
		for rarity in range(CardRarity.Tier.N, CardRarity.Tier.UR + 1):
			if not _passes_rarity_filter_tier(rarity):
				continue
			var count := CollStore.get_count(card_id, rarity)
			if count <= 0:
				continue
			entries.append({"name": card_name, "rarity": rarity, "qty": count})
		return
	if not _passes_rarity_filter_tier(CardRarity.Tier.N):
		return
	entries.append({"name": card_name, "rarity": CardRarity.Tier.N, "qty": 0})


## 검색 칩 엔트리 비교. 활성 키(레어/SPD/수량)면 1차 키(+방향), 동점·기본은 색→id→레어.
func _compare_search_entries(a: Dictionary, b: Dictionary) -> bool:
	var name_a := String(a.get("name", ""))
	var name_b := String(b.get("name", ""))
	var rar_a := int(a.get("rarity", CardRarity.Tier.N))
	var rar_b := int(b.get("rarity", CardRarity.Tier.N))
	if _has_active_sort():
		var primary := _compare_search_primary(
			name_a, rar_a, int(a.get("qty", 0)),
			name_b, rar_b, int(b.get("qty", 0))
		)
		if primary != 0:
			return primary < 0 if _sort_dir == SortDir.ASC else primary > 0
	if name_a != name_b:
		return _compare_search_by_color_then_id(name_a, name_b)
	return rar_a < rar_b


## 활성 정렬 1차 키 비교. a<b → -1, a>b → 1, 동점 → 0.
func _compare_search_primary(
	name_a: String, rar_a: int, qty_a: int,
	name_b: String, rar_b: int, qty_b: int
) -> int:
	match _sort_key:
		SortKey.RARITY:
			if rar_a != rar_b:
				return -1 if rar_a < rar_b else 1
		SortKey.SPD:
			var sa := _card_spd_of(name_a)
			var sb := _card_spd_of(name_b)
			if sa != sb:
				return -1 if sa < sb else 1
		SortKey.QTY:
			if qty_a != qty_b:
				return -1 if qty_a < qty_b else 1
		_:
			pass
	return 0


## 카드 SPD. 없으면 0.
func _card_spd_of(card_name: String) -> int:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return 0
	return int(data.stat_spd)


## Color: All 정렬 — DeckStore.BASE_COLORS 순, 동색은 id 오름차순. colorless/미상은 맨 뒤.
func _compare_search_by_color_then_id(a: String, b: String) -> bool:
	var ca := _search_color_rank(a)
	var cb := _search_color_rank(b)
	if ca != cb:
		return ca < cb
	var id_a := _card_id_of(a)
	var id_b := _card_id_of(b)
	if id_a != id_b:
		return id_a < id_b
	return a < b


## 검색 정렬용 색 순위. BASE_COLORS 인덱스, colorless/미상은 맨 뒤.
func _search_color_rank(card_name: String) -> int:
	var key := CardRegistry.color_key_for_card_name(card_name)
	if key.is_empty():
		return DeckStore.BASE_COLORS.size()
	var idx := DeckStore.BASE_COLORS.find(key)
	if idx < 0:
		return DeckStore.BASE_COLORS.size()
	return idx


## 칩 생성·시그널. 검색: 등급별 보유 수·미소지 흑백.
func _make_chip(
	card_name: String,
	is_deck_slot: bool,
	slot_index: int,
	chip_size: Vector2,
	rarity: int = CardRarity.Tier.N
) -> DeckCardChip:
	var chip := DeckCardChip.instantiate_chip()
	chip.setup(card_name, is_deck_slot, slot_index, chip_size, rarity)
	if not is_deck_slot and not card_name.is_empty():
		var owned := CollStore.get_count_by_name(card_name, rarity)
		chip.set_owned_count(owned)
		if owned <= 0:
			chip.set_grayscale(true)
	chip.info_requested.connect(_on_info_requested)
	chip.add_requested.connect(_try_add_card)
	chip.remove_requested.connect(_remove_at_slot)
	# 칩이 드롭 타깃을 가로채도 섹션 규칙이 적용되도록 forwarding.
	_forward_section_drop(chip)
	return chip


## 사이드바에 CardData + 클릭한 칩의 카피 등급 표시.
func _on_info_requested(card_name: String, rarity: int = CardRarity.Tier.N) -> void:
	var data := CardRegistry.get_by_name(card_name)
	if _info_sidebar and _info_sidebar.has_method("show_card_data"):
		_info_sidebar.show_card_data(data, rarity)


## DeckHost 크기에 맞춰 칩을 6×5가 스크롤 없이 들어가게 축소한다.
func _on_deck_host_resized() -> void:
	var host_size := _deck_host.size
	if host_size.x < 32.0 or host_size.y < 32.0:
		return
	var hsep := float(_deck_grid.get_theme_constant("h_separation"))
	var vsep := float(_deck_grid.get_theme_constant("v_separation"))
	var cell_w := (host_size.x - hsep * float(DECK_COLS - 1)) / float(DECK_COLS)
	var cell_h := (host_size.y - vsep * float(DECK_ROWS - 1)) / float(DECK_ROWS)
	var aspect := DeckCardChip.CARD_ASPECT
	var w := cell_w
	var h := w / aspect
	if h > cell_h:
		h = cell_h
		w = h * aspect
	_chip_size = Vector2(floor(w), floor(h))
	for child in _deck_grid.get_children():
		if child is DeckCardChip:
			(child as DeckCardChip).set_chip_size(_chip_size)
	for child in _results.get_children():
		if child is DeckCardChip:
			(child as DeckCardChip).set_chip_size(_chip_size)
	# 왜 좌상단 고정: 장수 감소 시 중앙 배치하면 슬롯이 밀려 우클릭 제거가 불편함.
	_deck_grid.position = Vector2.ZERO


## 포맷 콤보 변경 — 현재 편집 덱에 반영 (토스트 없음).
func _on_format_combo_item_selected(index: int) -> void:
	if bool(_current.get("readonly", false)):
		_select_format(String(_current.get("format", DeckStore.FORMAT_MONO)))
		return
	var fmt := String(_format_combo.get_item_metadata(index))
	_current["format"] = DeckStore.normalize_format(fmt)
	_rebuild_deck_grid()
	_refresh_search_results()
	call_deferred("_on_deck_host_resized")


## 이름 검색.
func _on_search_text_changed(_new_text: String) -> void:
	_refresh_search_results()


## 검색어만 비운다.
func _on_clear_search_pressed() -> void:
	if _search_edit == null or _search_edit.text.is_empty():
		return
	_search_edit.text = ""
	_refresh_search_results()


## 필터 팝업 열기.
func _on_filter_popup_button_pressed() -> void:
	_open_filter_popup()


## 필터 팝업 닫기.
func _on_filter_popup_close_pressed() -> void:
	_close_filter_popup()


## 딤머 클릭 시 팝업 닫기.
func _on_filter_popup_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_filter_popup()


func _open_filter_popup() -> void:
	if _filter_popup == null:
		return
	_close_sort_popup()
	_filter_popup.visible = true
	_filter_popup.move_to_front()


func _close_filter_popup() -> void:
	if _filter_popup:
		_filter_popup.visible = false


## 정렬 팝업 칩·방향 버튼을 연결한다.
func _setup_sort_popup() -> void:
	_sort_key_buttons.clear()
	var key_map := {
		_sort_key_acquire: SortKey.ACQUIRE,
		_sort_key_rarity: SortKey.RARITY,
		_sort_key_spd: SortKey.SPD,
		_sort_key_qty: SortKey.QTY,
	}
	for btn in key_map.keys():
		var button := btn as Button
		if button == null:
			continue
		_disconnect_all_toggled(button)
		button.toggled.connect(_on_sort_key_toggled.bind(key_map[btn]))
		_sort_key_buttons.append(button)
	if _sort_dir_asc:
		_disconnect_all_toggled(_sort_dir_asc)
		_sort_dir_asc.toggled.connect(_on_sort_dir_toggled.bind(SortDir.ASC))
	if _sort_dir_desc:
		_disconnect_all_toggled(_sort_dir_desc)
		_sort_dir_desc.toggled.connect(_on_sort_dir_toggled.bind(SortDir.DESC))
	_sync_sort_popup_pressed()
	_apply_filter_popup_chrome()


## 정렬 기준 칩. 획득일은 더미(선택만, 순서 변화 없음). 재클릭 시 기본 정렬.
func _on_sort_key_toggled(pressed: bool, key: SortKey) -> void:
	if pressed:
		_sort_key = key
	elif _sort_key == key:
		_sort_key = SortKey.DEFAULT
	_sync_sort_popup_pressed()
	_refresh_search_results()


## 오름/내림. 한쪽만 유지.
func _on_sort_dir_toggled(pressed: bool, dir: SortDir) -> void:
	if pressed:
		_sort_dir = dir
	elif _sort_dir == dir:
		# 둘 다 꺼지지 않게 유지
		_sort_dir = dir
	_sync_sort_popup_pressed()
	_refresh_search_results()


## 팝업 칩 pressed 상태를 _sort_key/_sort_dir에 맞춘다.
func _sync_sort_popup_pressed() -> void:
	var key_map := {
		_sort_key_acquire: SortKey.ACQUIRE,
		_sort_key_rarity: SortKey.RARITY,
		_sort_key_spd: SortKey.SPD,
		_sort_key_qty: SortKey.QTY,
	}
	for btn in key_map.keys():
		var button := btn as Button
		if button == null:
			continue
		var want: bool = int(key_map[btn]) == int(_sort_key)
		if button.button_pressed != want:
			button.set_pressed_no_signal(want)
	if _sort_dir_asc and _sort_dir_asc.button_pressed != (_sort_dir == SortDir.ASC):
		_sort_dir_asc.set_pressed_no_signal(_sort_dir == SortDir.ASC)
	if _sort_dir_desc and _sort_dir_desc.button_pressed != (_sort_dir == SortDir.DESC):
		_sort_dir_desc.set_pressed_no_signal(_sort_dir == SortDir.DESC)
	_refresh_filter_glow_chrome()


## 정렬 팝업 열기.
func _on_ordering_button_pressed() -> void:
	_open_sort_popup()


func _on_sort_popup_close_pressed() -> void:
	_close_sort_popup()


func _on_sort_popup_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_sort_popup()


func _open_sort_popup() -> void:
	if _sort_popup == null:
		return
	_close_filter_popup()
	_sort_popup.visible = true
	_sort_popup.move_to_front()


func _close_sort_popup() -> void:
	if _sort_popup:
		_sort_popup.visible = false


## 취소: 다중선택·검색·보유·정렬을 초기화하고 결과를 다시 그린다.
func _on_clear_filters_pressed() -> void:
	_sel_colors.clear()
	_sel_card_types.clear()
	_sel_tribes.clear()
	_sel_triggers.clear()
	_sel_spds.clear()
	_sel_rarities.clear()
	if _search_edit:
		_search_edit.text = ""
	_own_filter = OwnFilter.ALL
	_sort_key = SortKey.DEFAULT
	_sort_dir = SortDir.ASC
	_sync_status_button_label()
	_sync_filter_chip_pressed()
	_sync_sort_popup_pressed()
	_refresh_search_results()


## OwnStatusButton: 전체 → 소지 → 미소지 → 전체.
func _on_status_button_pressed() -> void:
	match _own_filter:
		OwnFilter.ALL:
			_own_filter = OwnFilter.OWNED
		OwnFilter.OWNED:
			_own_filter = OwnFilter.UNOWNED
		_:
			_own_filter = OwnFilter.ALL
	_sync_status_button_label()
	_refresh_search_results()


## OwnStatusButton 라벨을 현재 OwnFilter에 맞춘다.
func _sync_status_button_label() -> void:
	if _own_status_button == null:
		return
	match _own_filter:
		OwnFilter.OWNED:
			_own_status_button.text = "Owned"
		OwnFilter.UNOWNED:
			_own_status_button.text = "Not owned"
		_:
			_own_status_button.text = "All"


## 레어도 필터 통과 여부. 선택 없으면 All. tier=인스턴스 등급.
func _passes_rarity_filter_tier(tier: int) -> bool:
	if _sel_rarities.is_empty():
		return true
	return _sel_rarities.has(tier)


## 보유 필터 통과 여부. 토큰은 카탈로그에서 이미 제외.
func _passes_own_filter(card_name: String) -> bool:
	match _own_filter:
		OwnFilter.ALL:
			return true
		OwnFilter.OWNED:
			return CollStore.owns_name_any(card_name)
		OwnFilter.UNOWNED:
			return not CollStore.owns_name_any(card_name)
		_:
			return true


## 비우기.
func _on_clear_button_pressed() -> void:
	if bool(_current.get("readonly", false)):
		_toast("Builtin deck — read only")
		return
	DeckStore.set_deck_cards(_current, [], [])
	_rebuild_deck_grid()
	_toast("Cleared")
	call_deferred("_on_deck_host_resized")


## 덱 카드를 CardData.id 오름차순으로 정렬한다 (등급은 카드와 함께 이동).
func _on_sort_button_pressed() -> void:
	if bool(_current.get("readonly", false)):
		_toast("Builtin deck — read only")
		return
	var names := DeckStore.card_names_of(_current)
	var rarities := DeckStore.card_rarities_of(_current)
	if names.is_empty():
		_toast("Nothing to sort")
		return
	var order: Array[int] = []
	for i in names.size():
		order.append(i)
	order.sort_custom(func(ia: int, ib: int) -> bool:
		var id_a := _card_id_of(names[ia])
		var id_b := _card_id_of(names[ib])
		if id_a != id_b:
			return id_a < id_b
		if names[ia] != names[ib]:
			return names[ia] < names[ib]
		var ra := rarities[ia] if ia < rarities.size() else CardRarity.Tier.N
		var rb := rarities[ib] if ib < rarities.size() else CardRarity.Tier.N
		return ra < rb
	)
	var sorted_names: Array[String] = []
	var sorted_rarities: Array[int] = []
	for i in order:
		sorted_names.append(names[i])
		sorted_rarities.append(rarities[i] if i < rarities.size() else CardRarity.Tier.N)
	DeckStore.set_deck_cards(_current, sorted_names, sorted_rarities)
	_rebuild_deck_grid()
	_toast("Sorted by id")
	call_deferred("_on_deck_host_resized")


## 저장. 점검 중이면 서버 푸시 전 차단 안내.
func _on_save_button_pressed() -> void:
	await MetaSync.refresh_async(false, false)
	if MetaSync.block_kind == "maintenance":
		_toast("점검 중 — 저장할 수 없습니다")
		return
	_current["name"] = _name_edit.text.strip_edges()
	_current["format"] = _current_format()
	if bool(_current.get("readonly", false)) or DeckStore.is_builtin_id(String(_current.get("id", ""))):
		var base := String(_current.get("base_color", "black"))
		var cloned := DeckStore.clone_builtin_as_user(base, _current["name"])
		DeckStore.set_deck_cards(
			cloned,
			DeckStore.card_names_of(_current),
			DeckStore.card_rarities_of(_current)
		)
		cloned["format"] = _current["format"]
		_current = cloned
	_sync_names_from_grid()
	if _current_format() == DeckStore.FORMAT_MONO:
		var synced := DeckStore.mono_base_from_card_names(DeckStore.card_names_of(_current))
		if not synced.is_empty():
			_current["base_color"] = synced
	var result := DeckStore.save_deck(_current)
	if not bool(result.get("ok", false)):
		_toast(String(result.get("error", "Save failed")))
		return
	_toast("Saved")


## 복귀 (토스트 없음). 필터/정렬 팝업이 열려 있으면 먼저 닫음.
func _on_back_button_pressed() -> void:
	if _info_sidebar and _info_sidebar.has_method("consume_back") and _info_sidebar.consume_back():
		return
	if _sort_popup and _sort_popup.visible:
		_close_sort_popup()
		return
	if _filter_popup and _filter_popup.visible:
		_close_filter_popup()
		return
	MenuHost.pop_or_file(_return_scene)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _info_sidebar and _info_sidebar.has_method("consume_back") and _info_sidebar.consume_back():
		get_viewport().set_input_as_handled()
		return
	if _sort_popup and _sort_popup.visible:
		_close_sort_popup()
		get_viewport().set_input_as_handled()
		return
	if _filter_popup and _filter_popup.visible:
		_close_filter_popup()
		get_viewport().set_input_as_handled()


## 카드 추가. TOKEN·미소지·(id,rarity) 보유 초과 불가. mono는 동일 id≤MAX_COPIES(등급 무관).
func _try_add_card(card_name: String, rarity: int = CardRarity.Tier.N) -> void:
	if bool(_current.get("readonly", false)):
		return
	if card_name.is_empty() or _is_token_card_name(card_name):
		return
	var tier := clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	if not CollStore.owns_name(card_name, tier):
		return
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return
	var card_id := int(data.id)
	var names := DeckStore.card_names_of(_current)
	var rarities := DeckStore.card_rarities_of(_current)
	var id_copies := 0
	var rarity_copies := 0
	for i in names.size():
		if names[i] != card_name:
			continue
		id_copies += 1
		var slot_r := rarities[i] if i < rarities.size() else CardRarity.Tier.N
		if slot_r == tier:
			rarity_copies += 1
	var owned := CollStore.get_count(card_id, tier)
	if rarity_copies >= owned:
		return
	var format := _current_format()
	if format == DeckStore.FORMAT_MONO:
		if names.size() >= DeckStore.DECK_SIZE:
			return
		if id_copies >= DeckStore.MAX_COPIES:
			return
		var mono_base := DeckStore.mono_base_from_card_names(names)
		if not mono_base.is_empty() and not CardRegistry.card_allowed_in_mono(card_name, mono_base):
			return
	names.append(card_name)
	rarities.append(tier)
	DeckStore.set_deck_cards(_current, names, rarities)
	if format == DeckStore.FORMAT_MONO:
		var synced := DeckStore.mono_base_from_card_names(names)
		if not synced.is_empty():
			_current["base_color"] = synced
	_rebuild_deck_grid()
	call_deferred("_on_deck_host_resized")


## 슬롯 제거. none의 빈 안내 슬롯은 무시. 피드백 무표시.
## mono: 제거 후 남은 유채색으로 base_color를 다시 맞춘다.
func _remove_at_slot(slot_index: int) -> void:
	if bool(_current.get("readonly", false)):
		return
	var names := DeckStore.card_names_of(_current)
	var rarities := DeckStore.card_rarities_of(_current)
	if slot_index < 0 or slot_index >= names.size():
		return
	names.remove_at(slot_index)
	if slot_index < rarities.size():
		rarities.remove_at(slot_index)
	DeckStore.set_deck_cards(_current, names, rarities)
	if _current_format() == DeckStore.FORMAT_MONO:
		var synced := DeckStore.mono_base_from_card_names(names)
		if not synced.is_empty():
			_current["base_color"] = synced
	_rebuild_deck_grid()
	call_deferred("_on_deck_host_resized")


## 그리드에서 이름·등급 수집 (빈 슬롯 제외) 후 동기화.
func _sync_names_from_grid() -> void:
	var names: Array[String] = []
	var rarities: Array[int] = []
	for child in _deck_grid.get_children():
		if child is DeckCardChip:
			var chip := child as DeckCardChip
			if chip.card_name.is_empty():
				continue
			names.append(chip.card_name)
			rarities.append(chip.instance_rarity)
	DeckStore.set_deck_cards(_current, names, rarities)


## TOKEN 트리거 플래그가 켜진 카드면 true (덱 추가 목록에서 제외).
func _is_token_card_name(card_name: String) -> bool:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return false
	return (data.trigger_type & TRIGGER_TOKEN) != 0


## 정렬용 CardData.id. 미로드/미등록은 큰 값으로 뒤로.
func _card_id_of(card_name: String) -> int:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return 999999
	return int(data.id)
