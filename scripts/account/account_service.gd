extends Node
## Autoload AccountService — 활성 계정 bootstrap + 프로필 경로 API.
## Acc0: GuestAuthProvider만. G2/G3는 profile_path() 아래에만 저장한다.
## 표시명(displayName)은 계정 키와 별개로 수정 가능. accountKey(프로필 폴더)는 고정.
## 비역할: 로그인 UI·서드파티 SDK·Dedicated 서버 계정 강제(헤드리스는 스킵).


const ACTIVE_ACCOUNT_PATH := "user://active_account.json"
const PROFILES_ROOT := "user://profiles"
const DISPLAY_NAME_MAX_LEN := 50
## 영문·숫자·한글·_·- 만 허용 (빈 문자열·그 외 특수문자 거부).
const DISPLAY_NAME_PATTERN := "^[A-Za-z0-9가-힣_\\-]+$"

## 부팅 후 활성 계정 키 (예: guest_…). 비어 있으면 bootstrap 미완료/스킵.
var _account_key: String = ""
## active 계정의 authKind ("guest" 등). Acc1에서 교체된다.
var _auth_kind: String = ""
## 표시용 id. 기본=accountKey. 설정에서 변경 가능.
var _display_name: String = ""
## 프로필 아이콘 악세서리 id. account.json profileIconId.
var _profile_icon_id: String = ""
## Acc0는 Guest만. Acc1에서 AuthProvider 구현체를 갈아끼운다.
var _provider: AuthProvider = null
## true면 current_id/profile_path 사용 가능. Dedicated 스킵 시 false 유지.
var _bootstrapped: bool = false


## 클라 부팅 시 자동 bootstrap 후 프로필 설정을 창에 재적용. Dedicated/headless는 스킵.
func _ready() -> void:
	if _should_skip_bootstrap():
		print("[AccountService] skip bootstrap (dedicated/headless)")
		return
	bootstrap()
	if _bootstrapped:
		# G2: 재시작 후에도 동일 해상도. 설정 파일 없으면 no-op.
		AppSettings.apply_saved()


## 활성 계정 확보: 없으면 guest 생성, 있으면 동일 키 로드. 프로필 폴더를 보장한다.
func bootstrap() -> void:
	_provider = GuestAuthProvider.new()
	var active := _read_json_dict(ACTIVE_ACCOUNT_PATH)
	var key := String(active.get("accountKey", "")).strip_edges()
	var kind := String(active.get("authKind", "")).strip_edges()
	if key.is_empty():
		var meta := _provider.create_account_meta()
		key = String(meta.get("accountKey", "")).strip_edges()
		kind = String(meta.get("authKind", _provider.get_auth_kind())).strip_edges()
		if key.is_empty():
			push_error("[AccountService] guest create failed — empty accountKey")
			return
		_write_json(ACTIVE_ACCOUNT_PATH, {
			"accountKey": key,
			"authKind": kind,
		})
		_ensure_profile_tree(key, meta)
		print("[AccountService] created guest accountKey=%s displayName=%s" % [
			key,
			String(meta.get("displayName", key)),
		])
	else:
		if kind.is_empty():
			kind = _provider.get_auth_kind()
		_ensure_profile_tree(key, {
			"accountKey": key,
			"authKind": kind,
			"displayName": key,
			"createdAtUnix": int(Time.get_unix_time_from_system()),
		})
		print("[AccountService] loaded accountKey=%s authKind=%s" % [key, kind])
	_account_key = key
	_auth_kind = kind
	_display_name = _load_and_migrate_display_name(key)
	_profile_icon_id = _load_profile_icon_id(key)
	_bootstrapped = true


## 활성 accountKey. bootstrap 전이면 빈 문자열. 프로필 경로용(변경 불가).
func current_id() -> String:
	return _account_key


## 표시용 id. 인게임·설정·온라인 교환에 사용.
func display_name() -> String:
	if not _display_name.is_empty():
		return _display_name
	return _account_key


## 프로필 아이콘 악세서리 id. 비어 있으면 카탈로그 기본.
func profile_icon_id() -> String:
	if not _profile_icon_id.is_empty():
		return _profile_icon_id
	return AccessoryCatalog.DEFAULT_ICON_ID


## 활성 authKind ("guest" 등).
func current_auth_kind() -> String:
	return _auth_kind


## bootstrap 완료 여부. Dedicated 스킵·실패 시 false.
func is_bootstrapped() -> bool:
	return _bootstrapped


## 표시명 검증. 통과 시 빈 문자열, 실패 시 사유.
static func validate_display_name(raw: String) -> String:
	var name := raw.strip_edges()
	if name.is_empty():
		return "ID를 입력하세요"
	if name.length() > DISPLAY_NAME_MAX_LEN:
		return "ID는 %d자 이하여야 합니다" % DISPLAY_NAME_MAX_LEN
	var re := RegEx.new()
	if re.compile(DISPLAY_NAME_PATTERN) != OK:
		return "검증 오류"
	if re.search(name) == null:
		return "영문·숫자·한글·_·- 만 사용할 수 있습니다"
	return ""


## 표시명 저장. 성공 시 "". accountKey는 바꾸지 않음.
func set_display_name(raw: String) -> String:
	if not _bootstrapped or _account_key.is_empty():
		return "계정이 없습니다"
	var err := validate_display_name(raw)
	if not err.is_empty():
		return err
	var name := raw.strip_edges()
	var path := profile_path("account.json")
	var data := _read_json_dict(path)
	if data.is_empty():
		data = {
			"accountKey": _account_key,
			"authKind": _auth_kind,
			"createdAtUnix": int(Time.get_unix_time_from_system()),
		}
	data["accountKey"] = _account_key
	data["authKind"] = _auth_kind
	data["displayName"] = name
	_write_json(path, data)
	_display_name = name
	_push_meta_if_needed()
	return ""


## 프로필 아이콘 저장. 성공 시 "". 보유 icon 타입만 허용.
func set_profile_icon_id(raw: String) -> String:
	if not _bootstrapped or _account_key.is_empty():
		return "계정이 없습니다"
	var id := raw.strip_edges()
	if id.is_empty():
		return "아이콘을 선택하세요"
	AccessoryStore.ensure_loaded()
	if not AccessoryStore.owns(AccessoryTypes.TYPE_ICON, id):
		return "보유하지 않은 아이콘입니다"
	_write_profile_icon_id(id)
	_push_meta_if_needed()
	return ""


## MetaSync GET 적용 — 디스크만 갱신, 재푸시 없음.
func apply_remote_profile_icon(raw: String) -> void:
	var id := raw.strip_edges()
	if id.is_empty():
		id = AccessoryCatalog.DEFAULT_ICON_ID
	_write_profile_icon_id(id)


## MetaSync 스냅샷 푸시 (표시명 변경 반영).
func _push_meta_if_needed() -> void:
	var sync := get_node_or_null("/root/MetaSync")
	if sync == null or bool(sync.get("applying_remote")):
		return
	sync.call("push_snapshot_async")


## 프로필 하위 경로. relative 예: "settings.json", "decks/foo.json". 빈 값이면 루트(끝 /).
## 함정: bootstrap 전·Dedicated 스킵 시 빈 문자열 — 호출측에서 is_bootstrapped 확인할 것.
func profile_path(relative: String = "") -> String:
	if _account_key.is_empty():
		push_warning("[AccountService] profile_path before bootstrap")
		return ""
	var root := "%s/%s" % [PROFILES_ROOT, _account_key]
	var rel := relative.strip_edges().trim_prefix("/").trim_prefix("\\")
	if rel.is_empty():
		return root + "/"
	return "%s/%s" % [root, rel]


## Dedicated export 또는 headless 디스플레이면 로컬 계정 불필요.
func _should_skip_bootstrap() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	return false


## profiles/{key}/ 와 decks·collection 하위, account.json 을 보장한다. 기존 account.json은 덮지 않음.
func _ensure_profile_tree(account_key: String, meta: Dictionary) -> void:
	var root := "%s/%s" % [PROFILES_ROOT, account_key]
	_make_dir_recursive(root)
	_make_dir_recursive("%s/decks" % root)
	_make_dir_recursive("%s/collection" % root)
	_make_dir_recursive("%s/accessories" % root)
	var account_path := "%s/account.json" % root
	if not FileAccess.file_exists(account_path):
		_write_json(account_path, meta)


## 기존 세이브: displayName이 비어 있거나 "Guest"면 accountKey로 맞춘다(폴더는 그대로).
func _load_and_migrate_display_name(account_key: String) -> String:
	var path := "%s/%s/account.json" % [PROFILES_ROOT, account_key]
	var data := _read_json_dict(path)
	var name := String(data.get("displayName", "")).strip_edges()
	if name.is_empty() or name == "Guest":
		name = account_key
		if data.is_empty():
			data = {
				"accountKey": account_key,
				"authKind": _auth_kind if not _auth_kind.is_empty() else "guest",
				"createdAtUnix": int(Time.get_unix_time_from_system()),
			}
		data["accountKey"] = account_key
		data["displayName"] = name
		if not data.has("authKind"):
			data["authKind"] = _auth_kind if not _auth_kind.is_empty() else "guest"
		_write_json(path, data)
		print("[AccountService] migrated displayName -> %s" % name)
	return name


## account.json profileIconId 로드. 없으면 기본 id로 마이그레이션.
func _load_profile_icon_id(account_key: String) -> String:
	var path := "%s/%s/account.json" % [PROFILES_ROOT, account_key]
	var data := _read_json_dict(path)
	var id := AccessoryCatalog.migrate_accessory_id(String(data.get("profileIconId", "")))
	if id.is_empty():
		id = AccessoryCatalog.DEFAULT_ICON_ID
	if not data.is_empty():
		var raw := String(data.get("profileIconId", "")).strip_edges()
		if raw != id:
			data["profileIconId"] = id
			_write_json(path, data)
	return id


## profileIconId를 account.json에 쓴다.
func _write_profile_icon_id(id: String) -> void:
	var path := profile_path("account.json")
	var data := _read_json_dict(path)
	if data.is_empty():
		data = {
			"accountKey": _account_key,
			"authKind": _auth_kind,
			"displayName": _display_name if not _display_name.is_empty() else _account_key,
			"createdAtUnix": int(Time.get_unix_time_from_system()),
		}
	data["accountKey"] = _account_key
	data["authKind"] = _auth_kind
	if not data.has("displayName"):
		data["displayName"] = _display_name if not _display_name.is_empty() else _account_key
	data["profileIconId"] = id
	_write_json(path, data)
	_profile_icon_id = id


## user:// JSON을 Dictionary로 읽는다. 없거나 파싱 실패 시 {}.
func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[AccountService] cannot read %s err=%s" % [path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[AccountService] invalid json (expect object): %s" % path)
		return {}
	return parsed as Dictionary


## Dictionary를 pretty JSON으로 저장. 부모 디렉터리를 먼저 만든다.
func _write_json(path: String, data: Dictionary) -> void:
	var parent := path.get_base_dir()
	if not parent.is_empty():
		_make_dir_recursive(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[AccountService] cannot write %s err=%s" % [path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


## DirAccess로 user:// 하위 폴더를 재귀 생성. 이미 있으면 무시.
func _make_dir_recursive(path: String) -> void:
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		# make_dir_recursive_absolute는 존재 시 OK를 주는 편이지만, 환경별 차이를 흡수.
		if not DirAccess.dir_exists_absolute(path):
			push_error("[AccountService] mkdir failed path=%s err=%s" % [path, error_string(err)])
