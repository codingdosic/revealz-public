extends Control
## 설정 화면 (G2/G2b). 해상도 · 볼륨 슬라이더. 표시명은 Player Profile 화면.
## 변경 즉시 저장·적용 (Apply 없음). 볼륨은 UI·저장만 — AudioServer 버스 적용은 후속.
## 인게임 임베드 시 Back은 메인 대신 close_requested.
## 룩: UiChromeStyle (단색 ScreenBg · Resolution/Volume Section).

signal close_requested

@export var chrome_style: UiChromeStyle

@onready var _resolution_option: OptionButton = $CenterContainer/VBoxContainer/ResolutionSection/ResolutionRow/OptionButton
@onready var _master_slider: HSlider = $CenterContainer/VBoxContainer/VolumeSection/VBox/MasterVolumeRow/HSlider
@onready var _bgm_slider: HSlider = $CenterContainer/VBoxContainer/VolumeSection/VBox/BgmVolumeRow/HSlider
@onready var _sfx_slider: HSlider = $CenterContainer/VBoxContainer/VolumeSection/VBox/SfxVolumeRow/HSlider
@onready var _back_button: Button = $BackButton
@onready var _status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel

var _embedded: bool = false
## 초기 populate 중 value_changed/item_selected로 중복 저장 방지.
var _suppress_apply: bool = false


## 프리셋·볼륨으로 UI를 채우고 저장된(또는 현재) 값을 선택한다.
func _ready() -> void:
	_suppress_apply = true
	_populate_resolution_options()
	_populate_volume_sliders()
	var current := AppSettings.get_resolution_or_current()
	var idx := AppSettings.preset_index_of(current)
	if idx < 0:
		# 함정: 프리셋 밖 해상도면 목록 끝에 추가해 선택 가능하게 둔다.
		idx = _resolution_option.item_count
		_resolution_option.add_item("%d x %d" % [current.x, current.y], idx)
		_resolution_option.set_item_metadata(idx, current)
	_resolution_option.select(idx)
	_status_label.text = ""
	_apply_embedded_chrome()
	_apply_ui_chrome()
	_suppress_apply = false


## 크롬 스타일을 컨트롤에 적용한다. 임베드면 ScreenBg 생략(게임 위 오버레이).
func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self, not _embedded)
	if _title_label:
		chrome_style.apply_title_label(_title_label)
	ScreenRmbBack.install(self, _on_back_button_pressed)
	_apply_embedded_chrome()


## RESOLUTION_PRESETS를 OptionButton에 넣는다. metadata에 Vector2i를 둔다.
func _populate_resolution_options() -> void:
	_resolution_option.clear()
	for i in AppSettings.RESOLUTION_PRESETS.size():
		var size: Vector2i = AppSettings.RESOLUTION_PRESETS[i]
		_resolution_option.add_item("%d x %d" % [size.x, size.y], i)
		_resolution_option.set_item_metadata(i, size)


## 저장된 볼륨을 슬라이더에 반영한다.
func _populate_volume_sliders() -> void:
	var vols := AppSettings.get_volumes()
	_master_slider.value = float(vols.get("master_volume", AppSettings.DEFAULT_VOLUME))
	_bgm_slider.value = float(vols.get("bgm_volume", AppSettings.DEFAULT_VOLUME))
	_sfx_slider.value = float(vols.get("sfx_volume", AppSettings.DEFAULT_VOLUME))


## 해상도 선택 즉시 저장·창 적용 (싱글/MP 인게임 임베드 포함).
func _on_resolution_item_selected(_index: int) -> void:
	if _suppress_apply:
		return
	var size := _selected_resolution()
	if size.x <= 0 or size.y <= 0:
		_status_label.text = "Invalid resolution"
		return
	if not AppSettings.save_resolution(size):
		_status_label.text = "Save failed"
		return
	var applied := AppSettings.apply_resolution(size)
	if applied:
		_status_label.text = "%d x %d" % [size.x, size.y]
	else:
		# 함정: 에디터 Game 임베디드 창은 OS 창이 아니라 리사이즈 불가 — 값은 유지됨.
		_status_label.text = "%d x %d (applies outside editor)" % [size.x, size.y]


## 볼륨 슬라이더 변경 즉시 저장 (오디오 버스 미연결).
func _on_volume_changed(_value: float) -> void:
	if _suppress_apply:
		return
	if not AppSettings.save_volumes(_master_slider.value, _bgm_slider.value, _sfx_slider.value):
		_status_label.text = "Volume save failed"
		return
	_status_label.text = ""


## 인게임 오버레이로 쓸 때 true. Back은 메인 대신 close_requested.
func set_embedded(embedded: bool) -> void:
	_embedded = embedded
	_apply_embedded_chrome()
	if is_node_ready():
		if _embedded:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			var center := get_node_or_null("CenterContainer") as Control
			if center:
				center.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			mouse_filter = Control.MOUSE_FILTER_STOP


## 임베드면 툴팁만 닫기로. 기호 버튼 유지.
func _apply_embedded_chrome() -> void:
	if _back_button == null:
		return
	var copy := UiChromeStyle.resolve(chrome_style).get_copy()
	_back_button.tooltip_text = copy.close_tooltip if _embedded else copy.back_tooltip


## 임베드면 오버레이 닫기, 아니면 메인 메뉴.
func _on_back_button_pressed() -> void:
	if _embedded:
		close_requested.emit()
		return
	MenuHost.pop_or_file("res://scenes/main/main.tscn")


## OptionButton 선택 항목의 Vector2i. 없거나 잘못되면 (0,0).
func _selected_resolution() -> Vector2i:
	var idx := _resolution_option.selected
	if idx < 0 or idx >= _resolution_option.item_count:
		return Vector2i.ZERO
	var meta: Variant = _resolution_option.get_item_metadata(idx)
	if typeof(meta) == TYPE_VECTOR2I:
		return meta as Vector2i
	return Vector2i.ZERO
