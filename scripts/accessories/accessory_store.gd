class_name AccessoryStore
extends RefCounted
## 프로필 accessories/owned.json — 타입별 보유 악세서리 id 목록.
## 카탈로그 default id로 빈 계정 시드. MetaSync ownedAccessories와 roundtrip.


const OWNED_REL := "accessories/owned.json"
const DECK_OVERRIDES_REL := "accessories/deck_overrides.json"

## 상점 연동 전 미리보기용 card_back 보유 주입 — 상점 판매로 대체되어 비움.
const PREVIEW_GRANT_CARD_BACK_IDS: Array[String] = []

## accessory_type → Array[String] id
static var _owned_by_type: Dictionary = {}
static var _loaded_account: String = ""


static func owned_path() -> String:
	return AccountService.profile_path(OWNED_REL)


static func deck_overrides_path() -> String:
	return AccountService.profile_path(DECK_OVERRIDES_REL)


static func ensure_loaded() -> void:
	if not AccountService.is_bootstrapped():
		_owned_by_type.clear()
		_loaded_account = ""
		return
	var key := AccountService.current_id()
	if key == _loaded_account and not _owned_by_type.is_empty():
		return
	_loaded_account = key
	_owned_by_type = _empty_owned_dict()
	var path := owned_path()
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		_owned_by_type = _parse_owned(_read_json_dict(path))
	if _is_empty_owned(_owned_by_type):
		_seed_defaults()
		save()
	elif _apply_preview_grants():
		save()


static func reload() -> void:
	_loaded_account = ""
	_owned_by_type.clear()
	ensure_loaded()


static func save() -> bool:
	var path := owned_path()
	if path.is_empty():
		return false
	if not _write_json(path, snapshot_owned()):
		return false
	_push_meta_if_needed()
	return true


## API/MetaSync PUT body용.
static func snapshot_owned() -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	for t in AccessoryTypes.ALL_TYPES:
		out[t] = _owned_ids_array(t)
	return out


## 서버 ownedAccessories → 로컬 (MetaSync 전용 · 재푸시 없음).
## 서버에 아직 없는 로컬 보유(상점 구매 직후 등)는 merge로 유지한다.
static func apply_remote_owned(owned: Dictionary) -> void:
	ensure_loaded()
	var remote := _parse_owned(owned)
	_owned_by_type = _merge_owned_snapshots(_owned_by_type, remote)
	if _is_empty_owned(_owned_by_type):
		_seed_defaults()
	elif _apply_preview_grants():
		pass
	_loaded_account = AccountService.current_id()
	var path := owned_path()
	if path.is_empty():
		return
	_write_json(path, snapshot_owned())


## 타입별 id 목록 union — remote pull이 로컬 구매를 지우지 않게 한다.
static func _merge_owned_snapshots(local: Dictionary, remote: Dictionary) -> Dictionary:
	var out := _empty_owned_dict()
	for t in AccessoryTypes.ALL_TYPES:
		var ids: Array = []
		var local_raw: Variant = local.get(t, [])
		if typeof(local_raw) == TYPE_ARRAY:
			for item in local_raw as Array:
				var id := AccessoryCatalog.migrate_accessory_id(String(item))
				if not id.is_empty() and not ids.has(id):
					ids.append(id)
		var remote_raw: Variant = remote.get(t, [])
		if typeof(remote_raw) == TYPE_ARRAY:
			for item in remote_raw as Array:
				var id := AccessoryCatalog.migrate_accessory_id(String(item))
				if not id.is_empty() and not ids.has(id):
					ids.append(id)
		out[t] = ids
	return out


static func owns(accessory_type: String, accessory_id: String) -> bool:
	ensure_loaded()
	var id := accessory_id.strip_edges()
	if id.is_empty():
		return false
	for owned_id in _owned_ids_array(accessory_type):
		if owned_id == id:
			return true
	return false


static func list_owned_ids(accessory_type: String) -> Array[String]:
	ensure_loaded()
	return _owned_ids_array(accessory_type)


static func grant(accessory_type: String, accessory_id: String) -> bool:
	ensure_loaded()
	var id := accessory_id.strip_edges()
	if id.is_empty() or not AccessoryTypes.ALL_TYPES.has(accessory_type):
		return false
	if owns(accessory_type, id):
		return true
	var ids: Array = _owned_by_type.get(accessory_type, [])
	ids.append(id)
	_owned_by_type[accessory_type] = ids
	return save()


static func _owned_ids_array(accessory_type: String) -> Array[String]:
	var raw: Variant = _owned_by_type.get(accessory_type, [])
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw as Array:
		var id := String(item).strip_edges()
		if id.is_empty() or out.has(id):
			continue
		out.append(id)
	return out


static func _empty_owned_dict() -> Dictionary:
	return {
		AccessoryTypes.TYPE_ICON: [],
		AccessoryTypes.TYPE_CARD_BACK: [],
		AccessoryTypes.TYPE_FIELD: [],
	}


static func _is_empty_owned(owned: Dictionary) -> bool:
	for t in AccessoryTypes.ALL_TYPES:
		var ids: Variant = owned.get(t, [])
		if typeof(ids) == TYPE_ARRAY and not (ids as Array).is_empty():
			return false
	return true


static func _parse_owned(raw: Dictionary) -> Dictionary:
	var out := _empty_owned_dict()
	if raw.is_empty():
		return out
	for t in AccessoryTypes.ALL_TYPES:
		var ids_raw: Variant = raw.get(t, [])
		if typeof(ids_raw) != TYPE_ARRAY:
			continue
		var ids: Array = []
		for item in ids_raw as Array:
			var id := AccessoryCatalog.migrate_accessory_id(String(item))
			if id.is_empty() or ids.has(id):
				continue
			ids.append(id)
		out[t] = ids
	return out


static func _seed_defaults() -> void:
	_owned_by_type = _starter_owned_payload()


## 신규 계정·빈 owned 시드 — default + 미리보기 card_back.
static func _starter_owned_payload() -> Dictionary:
	var out := AccessoryCatalog.default_ids_payload()
	var backs: Array = out.get(AccessoryTypes.TYPE_CARD_BACK, [])
	for id in PREVIEW_GRANT_CARD_BACK_IDS:
		if not backs.has(id):
			backs.append(id)
	out[AccessoryTypes.TYPE_CARD_BACK] = backs
	return out


## 기존 owned.json에 미리보기 card_back이 없으면 병합. 변경 시 true.
static func _apply_preview_grants() -> bool:
	var changed := false
	var backs: Array = _owned_by_type.get(AccessoryTypes.TYPE_CARD_BACK, [])
	for id in PREVIEW_GRANT_CARD_BACK_IDS:
		if backs.has(id):
			continue
		backs.append(id)
		changed = true
	if changed:
		_owned_by_type[AccessoryTypes.TYPE_CARD_BACK] = backs
	return changed


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func _write_json(path: String, data: Dictionary) -> bool:
	var parent := path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[AccessoryStore] cannot write %s err=%s" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


static func _push_meta_if_needed() -> void:
	var sync := _meta_sync_node()
	if sync == null or bool(sync.get("applying_remote")):
		return
	sync.call("push_snapshot_async")


static func _meta_sync_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/MetaSync")
