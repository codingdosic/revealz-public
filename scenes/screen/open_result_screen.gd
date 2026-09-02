class_name OpenResultScreen
extends Control
## 팩 개봉 결과 화면. 획득 카드를 레어도↓ · 개봉 순서↑ 로 정렬해 5열 그리드 표시.
## 종료는 Back(·우클릭)만.

signal closed
## 칩 클릭 → 상점 CardInfoRoot (name, instance_rarity).
signal chip_info_requested(card_name: String, rarity: int)

const GRID_COLS := 5
const CHIP_W := 110.0
const GRID_H_SEP := 12
const GRID_V_SEP := 12

const BACK_Z_NORMAL := 20
## CardInfoRoot(z=40) 위에 Back이 클릭되도록.
const BACK_Z_ABOVE_INFO := 50

@onready var _back_button: Button = $BackButton
@onready var _grid: GridContainer = $Margin/Scroll/Center/CardGrid

var _chrome: UiChromeStyle
## 상점 CardInfo 표시 중이면 우클릭 Back을 무시한다.
var _should_ignore_rmb: Callable = Callable()
## CardInfo가 열려 있으면 닫기. Back 우선 처리용.
var _close_card_info: Callable = Callable()


## Back·우클릭 종료를 연결한다.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.pressed.connect(_on_back_pressed)
	ScreenRmbBack.install(self, _on_back_pressed, _ignore_rmb_back)


## 상점 CardInfo 열림 여부·닫기 콜백을 연결한다.
func set_card_info_hooks(should_ignore_rmb: Callable, close_info: Callable) -> void:
	_should_ignore_rmb = should_ignore_rmb
	_close_card_info = close_info


## 상점 CardInfo가 열려 있으면 우클릭으로 결과 화면을 닫지 않는다.
func set_rmb_ignore(should_ignore: Callable) -> void:
	_should_ignore_rmb = should_ignore


## CardInfo 표시 중이면 true.
func _ignore_rmb_back() -> bool:
	if _should_ignore_rmb.is_valid():
		return bool(_should_ignore_rmb.call())
	return false


## CardInfo가 열려 있으면 Back을 인포 위로 올린다.
func set_back_above_card_info(above: bool) -> void:
	if _back_button == null:
		return
	_back_button.z_index = BACK_Z_ABOVE_INFO if above else BACK_Z_NORMAL
	if above:
		_back_button.move_to_front()


## 획득 카드로 그리드를 채운다. rarities는 names와 동일 길이(부족분 N).
func present(
	granted_names: Array,
	granted_rarities: Array = [],
	chrome_style: UiChromeStyle = null
) -> void:
	_chrome = UiChromeStyle.resolve(chrome_style)
	_chrome.apply_screen_tree(self)
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", GRID_H_SEP)
	_grid.add_theme_constant_override("v_separation", GRID_V_SEP)
	_clear_grid()
	var entries: Array[Dictionary] = []
	for i in granted_names.size():
		var card_name := str(granted_names[i])
		if card_name.is_empty():
			continue
		var rarity := CardRarity.Tier.N
		if i < granted_rarities.size():
			rarity = clampi(int(granted_rarities[i]), CardRarity.Tier.N, CardRarity.Tier.UR)
		entries.append({"name": card_name, "rarity": rarity, "order": i})
	entries.sort_custom(_compare_result_entries)
	var chip_size := Vector2(CHIP_W, CHIP_W / DeckCardChip.CARD_ASPECT)
	for entry in entries:
		var chip := DeckCardChip.instantiate_chip()
		chip.setup(String(entry["name"]), true, -1, chip_size, int(entry["rarity"]))
		chip.set_owned_count(-1)
		chip.info_requested.connect(_on_chip_info_requested)
		_grid.add_child(chip)


## 레어도 내림차순, 동점이면 개봉 순서 오름차순.
func _compare_result_entries(a: Dictionary, b: Dictionary) -> bool:
	var ra := int(a.get("rarity", 0))
	var rb := int(b.get("rarity", 0))
	if ra != rb:
		return ra > rb
	return int(a.get("order", 0)) < int(b.get("order", 0))


## 그리드 자식을 비운다.
func _clear_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


## Back: CardInfo가 열려 있으면 인포만 닫고, 아니면 결과 종료.
func _on_back_pressed() -> void:
	if _close_card_info.is_valid() and _should_ignore_rmb.is_valid() and bool(_should_ignore_rmb.call()):
		_close_card_info.call()
		return
	closed.emit()
	queue_free()


## 칩 정보 요청을 상점으로 전달한다.
func _on_chip_info_requested(card_name: String, rarity: int) -> void:
	chip_info_requested.emit(card_name, rarity)
