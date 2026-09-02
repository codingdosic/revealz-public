extends Control
## 상점 화면 — 상단 탭 · 좌측 소분류 · 중앙 격자 · 상세(갤러리·설명·Buy/MultiBuy).
## 격자 셀 = shop_product_cell.tscn. 상세 이미지는 ShopProduct Gallery 필드.
## Buy/MultiBuy → 확인 PopupShell → ShopService.purchase → PackOpen → OpenResult.
## PackOpen 중 상점 Back 숨김 · CardInfo 열리면(PackOpen/OpenResult) 인포 닫기용으로만 표시.
## OpenResult 자체 Back은 결과 종료용. CardInfoRoot는 형제라 자식 Back z로는 클릭 불가.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const DEFAULT_CATALOG := preload("res://resources/shop/default_catalog.tres")
const PRODUCT_CELL_SCENE := preload("res://scenes/screen/shop_product_cell.tscn")
const NAV_TOGGLE_SCENE := preload("res://scenes/ui/nav_toggle_button.tscn")
const PACK_OPEN_SCENE := preload("res://scenes/screen/pack_open_screen.tscn")
const OPEN_RESULT_SCENE := preload("res://scenes/screen/open_result_screen.tscn")
const PHASE_TOAST_SCENE := preload("res://scenes/ui/phase_toast.tscn")
const POPUP_SHELL_SCENE := preload("res://scenes/ui/shell/popup_shell.tscn")
const CARD_BACK := preload("res://assets_lite/ShopAsset/card_back.png")
const MULTI_PACK_COUNT := 10
## 상세 갤러리: main(0번) 유지 / sample 유지(초).
const GALLERY_MAIN_HOLD_SEC := 10.0
const GALLERY_SAMPLE_HOLD_SEC := 3.0
## 상점 Back — CardInfoRoot(z=40)보다 위 · 기본은 tscn z=20.
const SHOP_BACK_Z_NORMAL := 20
const SHOP_BACK_Z_ABOVE_INFO := 50

@export var chrome_style: UiChromeStyle
@export var catalog: ShopCatalog

@onready var _back_button: Button = $BackButton
@onready var _browse_root: Control = $BrowseRoot
@onready var _detail_root: Control = $DetailRoot
@onready var _card_info: CardInfoDetail = $CardInfoRoot
@onready var _gold_label: Label = $GoldSection/GoldLabel
@onready var _tab_bar: HBoxContainer = $BrowseRoot/Margin/VBox/TabSection/TabBar
@onready var _sub_list: VBoxContainer = $BrowseRoot/Margin/VBox/Body/SubSection/SubScroll/SubList
@onready var _grid: GridContainer = $BrowseRoot/Margin/VBox/Body/GridSection/GridArea/GridScroll/ProductGrid
@onready var _empty_label: Label = $BrowseRoot/Margin/VBox/Body/GridSection/GridArea/EmptyLabel
@onready var _detail_title: Label = $DetailRoot/Margin/HBoxContainer/GallerySection/VBoxContainer/TitleLabel
@onready var _main_image: TextureRect = $DetailRoot/Margin/HBoxContainer/GallerySection/VBoxContainer/MainImage
@onready var _sample_1: TextureRect = $DetailRoot/Margin/HBoxContainer/GallerySection/VBoxContainer/ImageContainer/SampleImage1
@onready var _sample_2: TextureRect = $DetailRoot/Margin/HBoxContainer/GallerySection/VBoxContainer/ImageContainer/SampleImage2
@onready var _sample_3: TextureRect = $DetailRoot/Margin/HBoxContainer/GallerySection/VBoxContainer/ImageContainer/SampleImage3
@onready var _sample_4: TextureRect = $DetailRoot/Margin/HBoxContainer/GallerySection/VBoxContainer/ImageContainer/SampleImage4
@onready var _sample_5: TextureRect = $DetailRoot/Margin/HBoxContainer/GallerySection/VBoxContainer/ImageContainer/SampleImage5
@onready var _detail_desc: Label = $DetailRoot/Margin/HBoxContainer/VBoxContainer2/InfoSection/VBoxContainer/DescLabel
@onready var _buy_button: Button = $DetailRoot/Margin/HBoxContainer/VBoxContainer2/BuyButtonSection/VBoxContainer/BuyButton
@onready var _multi_buy_button: Button = $DetailRoot/Margin/HBoxContainer/VBoxContainer2/BuyButtonSection/VBoxContainer/MultiBuyButton

var _phase_toast: PhaseToast
var _buy_popup: PopupShell
var _gate_popup: PopupShell
var _pack_open: PackOpenScreen = null
var _open_result: OpenResultScreen = null
var _pending_grant_names: Array = []
var _pending_grant_rarities: Array = []
var _tab_index: int = 0
var _sub_index: int = 0
var _selected_product: ShopProduct = null
var _pending_pack_count: int = 1
var _tab_button_group: ButtonGroup = ButtonGroup.new()
var _sub_button_group: ButtonGroup = ButtonGroup.new()
## 갤러리 [main, s1..s5] — null은 슬라이드 스킵.
var _gallery_textures: Array[Texture2D] = []
var _gallery_index: int = 0
var _gallery_timer: Timer = null
var _gallery_thumbs: Array[TextureRect] = []


## 크롬·토스트·팝업·카탈로그로 브라우즈 UI를 채운다.
func _ready() -> void:
	_apply_ui_chrome()
	_setup_toast()
	_setup_buy_popup()
	_setup_gate_popup()
	_setup_sample_clicks()
	_setup_card_info_root()
	ScreenRmbBack.install(self, _on_back_button_pressed, _should_ignore_rmb_back)
	if catalog == null:
		catalog = DEFAULT_CATALOG
	_refresh_gold_labels()
	_show_browse()
	_rebuild_tabs()
	_select_tab(0)
	MetaSync.retain_online_watch()
	if not MetaSync.online_gate_changed.is_connected(_on_online_gate_changed):
		MetaSync.online_gate_changed.connect(_on_online_gate_changed)
	_apply_online_gate_ui(false)


func _exit_tree() -> void:
	MetaSync.release_online_watch()
	if MetaSync.online_gate_changed.is_connected(_on_online_gate_changed):
		MetaSync.online_gate_changed.disconnect(_on_online_gate_changed)


## 점검/서버오류 전환 시 구매 잠금 · 팝업.
func _on_online_gate_changed() -> void:
	_apply_online_gate_ui(true)


## 게이트 상태에 맞춰 Buy 잠금. announce면 차단 팝업.
func _apply_online_gate_ui(announce: bool) -> void:
	_refresh_buy_buttons()
	if not announce:
		return
	if MetaSync.can_use_shop():
		return
	_show_gate_popup(MetaSync.block_message)


## 점검/서버오류 안내 팝업.
func _setup_gate_popup() -> void:
	_gate_popup = POPUP_SHELL_SCENE.instantiate() as PopupShell
	add_child(_gate_popup)
	if _gate_popup.has_method("apply_chrome"):
		_gate_popup.call("apply_chrome", chrome_style)


## 온라인 게이트 차단 팝업.
func _show_gate_popup(message: String) -> void:
	if _gate_popup == null:
		return
	var copy := chrome_style.get_copy()
	var title := "점검 중" if MetaSync.block_kind == "maintenance" else "서버 오류"
	var body := message
	if body.is_empty():
		body = "서버 오류"
	_gate_popup.configure_confirm(
		title,
		body,
		Callable(),
		Callable(),
		copy.confirm,
		copy.cancel,
		{"confirm_only": true, "full_dimmer": true}
	)
	_gate_popup.open()



## CardInfo가 열려 있거나 구매 팝업이 떠 있으면 스크린 Back 처리를 허용(우선 닫기).
## 팩 플로우만 떠 있으면 스크린 Back을 무시한다.
func _should_ignore_rmb_back() -> bool:
	if _is_card_info_open():
		return false
	if _is_buy_popup_open():
		return false
	return _is_pack_flow_open()


## PackOpen 또는 OpenResult가 떠 있으면 true.
func _is_pack_flow_open() -> bool:
	if _pack_open != null and is_instance_valid(_pack_open):
		return true
	if _open_result != null and is_instance_valid(_open_result):
		return true
	return false


## 구매 확인 팝업이 보이면 true.
func _is_buy_popup_open() -> bool:
	return _buy_popup != null and is_instance_valid(_buy_popup) and _buy_popup.visible


## CardInfo DetailRoot가 보이는지.
func _is_card_info_open() -> bool:
	return _card_info != null and is_instance_valid(_card_info) and _card_info.is_open()


## CardInfo DetailRoot 크롬·닫힘 콜백.
func _setup_card_info_root() -> void:
	if _card_info == null:
		return
	_card_info.z_index = 40
	_card_info.apply_chrome(chrome_style)
	if not _card_info.closed.is_connected(_on_card_info_closed):
		_card_info.closed.connect(_on_card_info_closed)


## DetailRoot가 닫히면 팩 플로우 Back z를 되돌린다.
func _on_card_info_closed() -> void:
	_sync_pack_flow_back_above_card_info(false)
	_sync_shop_back_for_pack_flow()


## Cyan 크롬을 입힌다.
func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)
	if _card_info:
		_card_info.apply_chrome(chrome_style)


## 탭·소분류용 NavToggleButton 프리팹을 띄워 라벨·그룹·크롬을 넣는다.
func _spawn_nav_toggle(label: String, group: ButtonGroup, expand_fill: bool) -> NavToggleButton:
	var btn := NAV_TOGGLE_SCENE.instantiate() as NavToggleButton
	btn.configure(label, group, expand_fill)
	btn.apply_chrome(chrome_style)
	return btn


## 런타임 생성 Label에 muted 크롬을 적용한다.
func _style_muted_label(label: Label) -> void:
	if label == null or chrome_style == null:
		return
	chrome_style.apply_muted_label(label)


## PhaseToast를 자식으로 붙인다.
func _setup_toast() -> void:
	_phase_toast = PHASE_TOAST_SCENE.instantiate() as PhaseToast
	add_child(_phase_toast)
	if _phase_toast.has_method("apply_chrome"):
		_phase_toast.call("apply_chrome", chrome_style)


## 구매 확인 PopupShell을 준비한다.
func _setup_buy_popup() -> void:
	_buy_popup = POPUP_SHELL_SCENE.instantiate() as PopupShell
	add_child(_buy_popup)
	if _buy_popup.has_method("apply_chrome"):
		_buy_popup.call("apply_chrome", chrome_style)


## 썸네일(sample_1~5만). 클릭 시 갤러리 인덱스 1~5.
func _setup_sample_clicks() -> void:
	_gallery_thumbs = [_sample_1, _sample_2, _sample_3, _sample_4, _sample_5]
	for i in _gallery_thumbs.size():
		var rect := _gallery_thumbs[i]
		if rect == null:
			continue
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		# 썸네일 i → gallery index i+1 (0=main은 썸네일 없음).
		rect.gui_input.connect(_on_sample_gui_input.bind(i + 1))
	_gallery_timer = Timer.new()
	_gallery_timer.name = "GallerySlideTimer"
	_gallery_timer.one_shot = true
	_gallery_timer.timeout.connect(_on_gallery_slide_timeout)
	add_child(_gallery_timer)


## 토스트 메시지를 표시한다. duration<0 이면 크롬 기본.
func _toast(message: String, duration: float = -1.0) -> void:
	if _phase_toast == null:
		return
	_phase_toast.play(message, duration)


## 브라우즈 GoldLabel을 갱신한다.
func _refresh_gold_labels() -> void:
	if _gold_label:
		_gold_label.text = "gold: %d" % WalletStore.get_gold()


## 목록 모드로 전환한다.
func _show_browse() -> void:
	_stop_gallery_slideshow()
	_selected_product = null
	_browse_root.visible = true
	_detail_root.visible = false
	_refresh_gold_labels()


## 상세 모드로 전환하고 상품·갤러리·버튼 문구를 채운다.
## 갤러리 = detail_main + sample_1~5 (빈 슬롯 슬라이드 스킵).
func _show_detail(product: ShopProduct) -> void:
	if product == null:
		return
	_selected_product = product
	_browse_root.visible = false
	_detail_root.visible = true
	_detail_title.text = product.display_name if not product.display_name.is_empty() else product.product_id
	_detail_desc.text = product.description
	_setup_gallery_from_product(product)
	_refresh_gold_labels()
	_refresh_buy_buttons()


## 상품 갤러리 텍스처·썸네일(sample만)을 채우고 슬라이드를 시작한다.
func _setup_gallery_from_product(product: ShopProduct) -> void:
	_gallery_textures = product.get_gallery_textures()
	# 썸네일은 sample_1~5 (gallery index 1~5).
	for i in _gallery_thumbs.size():
		var thumb := _gallery_thumbs[i]
		if thumb == null:
			continue
		var gallery_i := i + 1
		var tex: Texture2D = null
		if gallery_i < _gallery_textures.size():
			tex = _gallery_textures[gallery_i]
		if tex != null:
			thumb.texture = tex
			thumb.visible = true
		else:
			thumb.texture = null
			thumb.visible = false
	_gallery_index = _first_filled_gallery_index(0)
	_apply_gallery_index(_gallery_index)
	_start_gallery_slideshow()


## 채워진 갤러리 슬롯 중 start 이상(순환) 첫 인덱스를 찾는다. 없으면 -1.
func _first_filled_gallery_index(start: int) -> int:
	var n := _gallery_textures.size()
	if n <= 0:
		return -1
	var from := posmod(start, n)
	for step in n:
		var i := (from + step) % n
		if _gallery_textures[i] != null:
			return i
	return -1


## MainImage에 갤러리 인덱스를 반영한다.
func _apply_gallery_index(index: int) -> void:
	if index < 0 or index >= _gallery_textures.size():
		_main_image.texture = CARD_BACK
		_gallery_index = 0
		return
	var tex := _gallery_textures[index]
	_main_image.texture = tex if tex != null else CARD_BACK
	_gallery_index = index


## 현재 슬롯 유지 시간(main=10초, sample=3초).
func _gallery_hold_sec_for(index: int) -> float:
	if index == 0:
		return GALLERY_MAIN_HOLD_SEC
	return GALLERY_SAMPLE_HOLD_SEC


## 갤러리 자동 슬라이드를 현재 슬롯 유지 시간으로 시작한다.
func _start_gallery_slideshow() -> void:
	if _gallery_timer == null:
		return
	_gallery_timer.stop()
	if _first_filled_gallery_index(0) < 0:
		return
	_gallery_timer.wait_time = _gallery_hold_sec_for(_gallery_index)
	_gallery_timer.start()


## 갤러리 자동 슬라이드를 멈춘다.
func _stop_gallery_slideshow() -> void:
	if _gallery_timer:
		_gallery_timer.stop()


## 유지 시간 후 다음(비어 있지 않은) 갤러리 이미지로 넘긴다.
func _on_gallery_slide_timeout() -> void:
	if not _detail_root.visible:
		_stop_gallery_slideshow()
		return
	var next := _first_filled_gallery_index(_gallery_index + 1)
	if next < 0:
		return
	if next == _gallery_index:
		return
	_apply_gallery_index(next)
	_start_gallery_slideshow()


## 텍스처 또는 card_back.
func _texture_or_back(tex: Texture2D) -> Texture2D:
	return tex if tex != null else CARD_BACK


## Buy/MultiBuy 문구·활성 상태를 가격·잔액·서버 게이트·보유 여부에 맞춘다.
func _refresh_buy_buttons() -> void:
	if _selected_product == null:
		return
	var is_accessory := _selected_product is ShopAccessoryProduct
	_multi_buy_button.visible = not is_accessory
	if is_accessory and _is_product_owned(_selected_product):
		_buy_button.text = "보유 중"
		_buy_button.disabled = true
		_multi_buy_button.disabled = true
		return
	var unit := maxi(0, int(_selected_product.price_gold))
	var gold := WalletStore.get_gold()
	if is_accessory:
		_buy_button.text = "구매 - %d G" % unit
	else:
		_buy_button.text = "1 pack - %d" % unit
		_multi_buy_button.text = "%d pack - %d" % [MULTI_PACK_COUNT, unit * MULTI_PACK_COUNT]
	var gated := not MetaSync.can_use_shop()
	_buy_button.disabled = gated or gold < unit
	if not is_accessory:
		_multi_buy_button.disabled = gated or gold < unit * MULTI_PACK_COUNT


## 상단 탭 버튼을 카탈로그에서 다시 만든다.
func _rebuild_tabs() -> void:
	_clear_children(_tab_bar)
	if catalog == null:
		return
	for i in catalog.tabs.size():
		var tab: ShopTab = catalog.tabs[i]
		var label := tab.display_name if tab and not tab.display_name.is_empty() else ("Tab %d" % i)
		var btn := _spawn_nav_toggle(label, _tab_button_group, false)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		_tab_bar.add_child(btn)


## 탭을 고르고 소분류·격자를 갱신한다.
func _select_tab(index: int) -> void:
	if catalog == null or catalog.tabs.is_empty():
		_tab_index = 0
		_clear_children(_sub_list)
		_rebuild_grid([])
		return
	_tab_index = clampi(index, 0, catalog.tabs.size() - 1)
	for i in _tab_bar.get_child_count():
		var btn := _tab_bar.get_child(i) as Button
		if btn:
			btn.set_pressed_no_signal(i == _tab_index)
	_rebuild_subcategories()
	_select_sub(0)


## 좌측 소분류 버튼을 현재 탭 기준으로 다시 만든다.
func _rebuild_subcategories() -> void:
	_clear_children(_sub_list)
	var tab := _current_tab()
	if tab == null or tab.subcategories.is_empty():
		var empty := Label.new()
		empty.text = "(소분류 없음)"
		_sub_list.add_child(empty)
		_style_muted_label(empty)
		return
	for i in tab.subcategories.size():
		var sub: ShopSubcategory = tab.subcategories[i]
		var label := sub.display_name if sub and not sub.display_name.is_empty() else ("Sub %d" % i)
		var btn := _spawn_nav_toggle(label, _sub_button_group, true)
		btn.pressed.connect(_on_sub_pressed.bind(i))
		_sub_list.add_child(btn)


## 소분류를 고르고 격자를 채운다.
func _select_sub(index: int) -> void:
	var tab := _current_tab()
	if tab == null or tab.subcategories.is_empty():
		_sub_index = 0
		_rebuild_grid([])
		return
	_sub_index = clampi(index, 0, tab.subcategories.size() - 1)
	for i in _sub_list.get_child_count():
		var btn := _sub_list.get_child(i) as Button
		if btn:
			btn.set_pressed_no_signal(i == _sub_index)
	var sub: ShopSubcategory = tab.subcategories[_sub_index]
	var products: Array[ShopProduct] = []
	if sub != null:
		products = sub.products
	_rebuild_grid(products)


## 중앙 상품 격자를 채운다. 비면 EmptyLabel.
func _rebuild_grid(products: Array[ShopProduct]) -> void:
	_clear_children(_grid)
	var visible_products: Array[ShopProduct] = []
	for p in products:
		if p != null:
			visible_products.append(p)
	_empty_label.visible = visible_products.is_empty()
	_grid.visible = not visible_products.is_empty()
	for product in visible_products:
		_grid.add_child(_spawn_product_cell(product))


## 상품 셀 씬을 띄워 데이터·크롬을 넣고 격자에 추가할 노드를 반환한다.
func _spawn_product_cell(product: ShopProduct) -> Control:
	var cell := PRODUCT_CELL_SCENE.instantiate() as ShopProductCell
	cell.bind(product, CARD_BACK, _is_product_owned(product))
	cell.apply_chrome(chrome_style)
	cell.product_pressed.connect(_on_product_cell_pressed)
	return cell


## 치장품 상품이면 AccessoryStore 보유 여부.
func _is_product_owned(product: ShopProduct) -> bool:
	if product is ShopAccessoryProduct:
		return (product as ShopAccessoryProduct).is_owned()
	return false


## 현재 선택 탭. 없으면 null.
func _current_tab() -> ShopTab:
	if catalog == null or catalog.tabs.is_empty():
		return null
	if _tab_index < 0 or _tab_index >= catalog.tabs.size():
		return null
	return catalog.tabs[_tab_index]


## 자식 노드를 모두 제거한다.
func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## 상단 탭 클릭.
func _on_tab_pressed(index: int) -> void:
	_select_tab(index)


## 좌측 소분류 클릭.
func _on_sub_pressed(index: int) -> void:
	_select_sub(index)


## 격자 상품 클릭 → 상세.
func _on_product_cell_pressed(product: ShopProduct) -> void:
	_show_detail(product)


## 썸네일 좌클릭 → 해당 슬롯을 MainImage에 표시하고 슬라이드를 재개한다.
func _on_sample_gui_input(event: InputEvent, gallery_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if gallery_index < 0 or gallery_index >= _gallery_textures.size():
				return
			if _gallery_textures[gallery_index] == null:
				return
			_apply_gallery_index(gallery_index)
			_start_gallery_slideshow()
			accept_event()


## 1팩 구매 확인 팝업을 연다.
func _on_buy_button_pressed() -> void:
	_open_buy_confirm(1)


## 10팩 구매 확인 팝업을 연다.
func _on_multi_buy_button_pressed() -> void:
	_open_buy_confirm(MULTI_PACK_COUNT)


## 구매 확인 팝업(잔량 n→m)을 띄운다.
func _open_buy_confirm(pack_count: int) -> void:
	if _selected_product == null or _buy_popup == null:
		return
	if _is_product_owned(_selected_product):
		_toast("이미 보유 중입니다")
		return
	var count := maxi(1, pack_count)
	var unit := maxi(0, int(_selected_product.price_gold))
	var cost := unit * count
	var gold_now := WalletStore.get_gold()
	if gold_now < cost:
		_toast("골드가 부족합니다")
		_refresh_buy_buttons()
		return
	_pending_pack_count = count
	var gold_after := gold_now - cost
	var copy := chrome_style.get_copy()
	_buy_popup.configure_confirm(
		"구매 확인",
		"상품을 구매하시겠습니까?\n구매 후 gold 잔량 %d -> %d" % [gold_now, gold_after],
		_on_buy_confirmed,
		Callable(),
		"구매",
		copy.cancel,
		{"full_dimmer": true}
	)
	_buy_popup.open()


## 확인 후 실제 구매 → PackOpenScreen(팩) / 치장품 즉시 지급.
func _on_buy_confirmed() -> void:
	if _selected_product == null:
		return
	await MetaSync.refresh_async(false, true)
	if not MetaSync.can_use_shop():
		_show_gate_popup(MetaSync.block_message)
		_refresh_buy_buttons()
		return
	var result: Dictionary = await ShopService.purchase_async(_selected_product, _pending_pack_count)
	_refresh_gold_labels()
	_refresh_buy_buttons()
	if not bool(result.get(ShopService.KEY_OK, false)):
		_toast(String(result.get(ShopService.KEY_ERROR, "구매 실패")))
		return
	if _selected_product is ShopAccessoryProduct:
		await MetaSync.push_snapshot_async()
		_toast("구매 완료")
		_select_sub(_sub_index)
		return
	_open_pack_result(result)


## 구매 성공 → PackOpenScreen. 전 팩 끝나면 OpenResultScreen → DetailRoot.
func _open_pack_result(result: Dictionary) -> void:
	_hide_card_info()
	_clear_pack_flow_overlays()
	var pack_size := 5
	if _selected_product is ShopPackProduct:
		pack_size = maxi(1, int((_selected_product as ShopPackProduct).pack_size))
	var pack_count := maxi(1, int(result.get(ShopService.KEY_PACK_COUNT, 1)))
	_pending_grant_names = result.get(ShopService.KEY_GRANTED_NAMES, []) as Array
	_pending_grant_rarities = result.get(ShopService.KEY_GRANTED_RARITIES, []) as Array
	_pack_open = PACK_OPEN_SCENE.instantiate() as PackOpenScreen
	add_child(_pack_open)
	_pack_open.finished.connect(_on_pack_open_finished)
	_pack_open.chip_info_requested.connect(_on_chip_info_requested)
	_pack_open.present(_pending_grant_names, _pending_grant_rarities, pack_size, pack_count, chrome_style)
	_sync_shop_back_for_pack_flow()


## PackOpen/OpenResult 오버레이를 제거한다.
func _clear_pack_flow_overlays() -> void:
	if _pack_open != null and is_instance_valid(_pack_open):
		_pack_open.queue_free()
	_pack_open = null
	if _open_result != null and is_instance_valid(_open_result):
		_open_result.queue_free()
	_open_result = null
	_sync_shop_back_for_pack_flow()


## 전 팩 개봉 끝 → 획득 결과 그리드.
func _on_pack_open_finished() -> void:
	_hide_card_info()
	_pack_open = null
	_open_result = OPEN_RESULT_SCENE.instantiate() as OpenResultScreen
	add_child(_open_result)
	_open_result.closed.connect(_on_open_result_closed)
	_open_result.chip_info_requested.connect(_on_chip_info_requested)
	_open_result.set_card_info_hooks(_is_card_info_open, _hide_card_info)
	_open_result.present(_pending_grant_names, _pending_grant_rarities, chrome_style)
	_sync_shop_back_for_pack_flow()


## 결과 화면 Back → DetailRoot 유지 · 골드/Buy 갱신.
func _on_open_result_closed() -> void:
	_hide_card_info()
	_open_result = null
	_pending_grant_names = []
	_pending_grant_rarities = []
	_refresh_gold_labels()
	_refresh_buy_buttons()
	_sync_shop_back_for_pack_flow()


## PackOpen 중엔 상점 Back 숨김. CardInfo 열리면 인포 닫기용으로만 표시.
## OpenResult도 동일: 자체 Back은 결과 종료용 · CardInfo 중엔 상점 Back(형제·고 z)으로 닫기.
## (OpenResult 자식 Back은 CardInfoRoot 형제를 z로 이길 수 없음.)
func _sync_shop_back_for_pack_flow() -> void:
	if _back_button == null:
		return
	var pack_open_active := _pack_open != null and is_instance_valid(_pack_open)
	var open_result_active := _open_result != null and is_instance_valid(_open_result)
	if pack_open_active or open_result_active:
		var info_open := _is_card_info_open()
		_back_button.visible = info_open
		_back_button.z_index = SHOP_BACK_Z_ABOVE_INFO if info_open else SHOP_BACK_Z_NORMAL
		if info_open:
			_back_button.move_to_front()
		return
	_back_button.visible = true
	_back_button.z_index = SHOP_BACK_Z_NORMAL


## PackOpen/OpenResult 칩 → CardInfo DetailRoot.
func _on_chip_info_requested(card_name: String, rarity: int) -> void:
	_show_card_info(card_name, rarity)


## CardData·인스턴스 레어로 DetailRoot를 연다.
func _show_card_info(card_name: String, rarity: int) -> void:
	if _card_info == null or card_name.is_empty():
		return
	_card_info.present_name(card_name, rarity, chrome_style)
	_sync_pack_flow_back_above_card_info(true)
	_sync_shop_back_for_pack_flow()


## CardInfo DetailRoot를 숨긴다.
func _hide_card_info() -> void:
	if _card_info != null and is_instance_valid(_card_info):
		_card_info.hide_detail()
	_sync_pack_flow_back_above_card_info(false)
	_sync_shop_back_for_pack_flow()


## OpenResult Back을 CardInfo 위/아래로 맞춘다.
func _sync_pack_flow_back_above_card_info(above: bool) -> void:
	if _open_result != null and is_instance_valid(_open_result):
		_open_result.set_back_above_card_info(above)


## Back: 줌→상세→구매팝업→목록→메인. 팩 플로우 중에는 상점 Back 무시(인포 제외).
func _on_back_button_pressed() -> void:
	if _card_info != null and is_instance_valid(_card_info) and _card_info.consume_back():
		_sync_pack_flow_back_above_card_info(_is_card_info_open())
		_sync_shop_back_for_pack_flow()
		return
	if _is_buy_popup_open():
		_buy_popup.request_cancel()
		return
	if _is_pack_flow_open():
		return
	if _detail_root.visible:
		_show_browse()
		return
	MenuHost.pop_or_file(MAIN_SCENE)
