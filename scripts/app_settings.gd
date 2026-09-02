class_name AppSettings
extends RefCounted
## 앱 설정 로드/저장/적용. Acc0 프로필 `settings.json`에 기록한다.
## G2: 해상도. G2b: 마스터/BGM/SFX 볼륨(UI·저장만, AudioServer 미연결).
## 준비 화면: 마지막 선택 덱 id (싱글 Player/COM · 온라인).


const SETTINGS_REL := "settings.json"
const DEFAULT_VOLUME := 1.0
const KEY_LAST_DECK_SINGLE_PLAYER := "last_deck_single_player"
const KEY_LAST_DECK_SINGLE_COM := "last_deck_single_com"
const KEY_LAST_DECK_ONLINE := "last_deck_online"

## 선택지용 해상도 프리셋. UI OptionButton과 동일 순서.
const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]


## 프로필 아래 settings.json 절대 경로. AccountService 미부팅이면 빈 문자열.
static func settings_path() -> String:
	return AccountService.profile_path(SETTINGS_REL)


## 저장된 설정을 Dictionary로 읽는다. 없거나 실패 시 {}.
static func load_dict() -> Dictionary:
	var path := settings_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[AppSettings] cannot read %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[AppSettings] invalid settings json: %s" % path)
		return {}
	return parsed as Dictionary


## 현재 Dictionary에 해상도를 병합 저장한다. 다른 키(사운드 등)는 유지.
static func save_resolution(size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		push_error("[AppSettings] invalid resolution %s" % size)
		return false
	var path := settings_path()
	if path.is_empty():
		push_error("[AppSettings] save_resolution: no profile path")
		return false
	var data := load_dict()
	data["resolution_w"] = size.x
	data["resolution_h"] = size.y
	return _write_json(path, data)


## 마스터/BGM/SFX 볼륨(0~1)을 병합 저장한다. 오디오 버스 적용은 후속.
static func save_volumes(master: float, bgm: float, sfx: float) -> bool:
	var path := settings_path()
	if path.is_empty():
		push_error("[AppSettings] save_volumes: no profile path")
		return false
	var data := load_dict()
	data["master_volume"] = clampf(master, 0.0, 1.0)
	data["bgm_volume"] = clampf(bgm, 0.0, 1.0)
	data["sfx_volume"] = clampf(sfx, 0.0, 1.0)
	return _write_json(path, data)


## 저장된 볼륨. 키 없으면 DEFAULT_VOLUME.
static func get_volumes() -> Dictionary:
	var data := load_dict()
	return {
		"master_volume": _clamp_volume(data.get("master_volume", DEFAULT_VOLUME)),
		"bgm_volume": _clamp_volume(data.get("bgm_volume", DEFAULT_VOLUME)),
		"sfx_volume": _clamp_volume(data.get("sfx_volume", DEFAULT_VOLUME)),
	}


## Variant를 0~1 float로 클램프. 비숫자면 기본값.
static func _clamp_volume(value: Variant) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return DEFAULT_VOLUME
	return clampf(float(value), 0.0, 1.0)


## 프로필에 저장된 해상도를 창에 적용. 값 없거나 임베디드 에디터면 no-op.
static func apply_saved() -> void:
	var data := load_dict()
	var w := int(data.get("resolution_w", 0))
	var h := int(data.get("resolution_h", 0))
	if w <= 0 or h <= 0:
		return
	apply_resolution(Vector2i(w, h))


## 창 크기 변경 가능 여부. 에디터 Embedded Game은 resize/move가 엔진에서 거부된다.
static func can_apply_window_size() -> bool:
	return not Engine.is_embedded_in_editor()


## OS 창 크기를 바꾸고 현재 스크린 중앙에 둔다. 저장은 하지 않음.
## export/스탠드얼론·인게임(싱글·MP)에서 즉시 반영. Embedded Game은 no-op → false.
## 함정: 최대화/전체화면에서는 set_size가 체감되지 않으므로 WINDOWED로 내린 뒤 적용.
static func apply_resolution(size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	if not can_apply_window_size():
		return false
	var mode := DisplayServer.window_get_mode()
	if (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_MAXIMIZED
	):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	# 일부 빌드에서 DisplayServer만으로는 루트 Window와 어긋날 수 있어 동기화.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.size = size
	var screen := DisplayServer.window_get_current_screen()
	var screen_pos := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	var pos := screen_pos + (screen_size - size) / 2
	DisplayServer.window_set_position(pos)
	return true


## 저장된(또는 현재 창) 해상도. 설정 UI 초기 선택용.
static func get_resolution_or_current() -> Vector2i:
	var data := load_dict()
	var w := int(data.get("resolution_w", 0))
	var h := int(data.get("resolution_h", 0))
	if w > 0 and h > 0:
		return Vector2i(w, h)
	return DisplayServer.window_get_size()


## 준비 화면용 마지막 선택 덱 id. 없으면 "".
static func get_last_deck_id(key: String) -> String:
	if key.is_empty():
		return ""
	return String(load_dict().get(key, "")).strip_edges()


## 준비 화면 선택 덱 id를 병합 저장한다.
static func save_last_deck_id(key: String, deck_id: String) -> bool:
	if key.is_empty():
		return false
	var path := settings_path()
	if path.is_empty():
		return false
	var data := load_dict()
	data[key] = deck_id.strip_edges()
	return _write_json(path, data)


## 프리셋 배열에서 size와 같은 인덱스. 없으면 -1.
static func preset_index_of(size: Vector2i) -> int:
	for i in RESOLUTION_PRESETS.size():
		if RESOLUTION_PRESETS[i] == size:
			return i
	return -1


## Dictionary를 pretty JSON으로 저장. 부모 디렉터리를 먼저 만든다.
static func _write_json(path: String, data: Dictionary) -> bool:
	var parent := path.get_base_dir()
	if not parent.is_empty():
		var err := DirAccess.make_dir_recursive_absolute(parent)
		if err != OK and not DirAccess.dir_exists_absolute(parent):
			push_error("[AppSettings] mkdir failed path=%s err=%s" % [parent, error_string(err)])
			return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[AppSettings] cannot write %s err=%s" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true
