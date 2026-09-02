class_name AccessoryCatalog
extends Resource
## resources/accessories/{icon|card_back|field}/*.tres 를 스캔해 id→정의 조회.


const CATALOG_ROOT := "res://resources/accessories"

const DEFAULT_ICON_ID := "icon_default"
const DEFAULT_CARD_BACK_ID := "card_back_default"
const DEFAULT_FIELD_ID := "default_field"

## 폴더명 = AccessoryTypes 상수.
const SCANNED_TYPE_DIRS: Array[String] = [
	AccessoryTypes.TYPE_ICON,
	AccessoryTypes.TYPE_CARD_BACK,
	AccessoryTypes.TYPE_FIELD,
]

## 구 id → 현재 id (로컬 JSON·덱 마이그레이션).
const LEGACY_ID_ALIASES := {
	"default_icon": DEFAULT_ICON_ID,
	"default_back": DEFAULT_CARD_BACK_ID,
}

@export var items: Array[AccessoryDefinition] = []

static var _items_by_id: Dictionary = {}
static var _items_by_type: Dictionary = {}
static var _scanned: bool = false
static var _texture_cache: Dictionary = {}
static var _runtime_catalog: AccessoryCatalog = null


static func migrate_accessory_id(accessory_id: String) -> String:
	var id := accessory_id.strip_edges()
	if id.is_empty():
		return id
	return String(LEGACY_ID_ALIASES.get(id, id))


static func resolve_card_back_id(raw: String) -> String:
	var id := migrate_accessory_id(raw)
	return id if not id.is_empty() else DEFAULT_CARD_BACK_ID


static func resolve_field_id(raw: String) -> String:
	var id := migrate_accessory_id(raw)
	return id if not id.is_empty() else DEFAULT_FIELD_ID


static func resolve_icon_id(raw: String) -> String:
	var id := migrate_accessory_id(raw)
	return id if not id.is_empty() else DEFAULT_ICON_ID


static func resolve(catalog: AccessoryCatalog = null) -> AccessoryCatalog:
	if catalog != null:
		return catalog
	return _runtime_catalog_instance()


static func default_id_for_type(accessory_type: String) -> String:
	match accessory_type:
		AccessoryTypes.TYPE_ICON:
			return DEFAULT_ICON_ID
		AccessoryTypes.TYPE_CARD_BACK:
			return DEFAULT_CARD_BACK_ID
		AccessoryTypes.TYPE_FIELD:
			return DEFAULT_FIELD_ID
		_:
			return ""


## 보유 시드용 — 카탈로그 인스턴스 없이 상수만 사용 (부팅 순서 안전).
static func default_ids_payload() -> Dictionary:
	var out: Dictionary = {}
	for t in AccessoryTypes.ALL_TYPES:
		var id := default_id_for_type(t)
		if not id.is_empty():
			out[t] = [id]
	return out


static func reload() -> void:
	_scanned = false
	_items_by_id.clear()
	_items_by_type.clear()
	_runtime_catalog = null


## 등록된 정의 수. export/스캔 회귀 확인용.
static func catalog_count() -> int:
	_ensure_scanned()
	return _items_by_id.size()


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_items_by_id.clear()
	_items_by_type = {}
	for t in AccessoryTypes.ALL_TYPES:
		_items_by_type[t] = []
	for folder_name in SCANNED_TYPE_DIRS:
		_scan_type_dir(folder_name)
	_scanned = true
	if _items_by_id.is_empty():
		push_error("[AccessoryCatalog] no definitions loaded (export DirAccess/remap?)")


static func _scan_type_dir(folder_name: String) -> void:
	var dir_path := "%s/%s" % [CATALOG_ROOT, folder_name]
	for path in _list_definition_paths_in_dir(dir_path):
		_register_definition(load(path) as Resource, dir_path)


## Export-safe listing — ResourceLoader.list_directory 우선, DirAccess 폴백 (CardRegistry 동일).
static func _list_definition_paths_in_dir(base_dir: String) -> Array[String]:
	var paths: Array[String] = []
	var file_names: PackedStringArray = ResourceLoader.list_directory(base_dir)
	if file_names.is_empty():
		var dir := DirAccess.open(base_dir)
		if dir == null:
			push_warning("[AccessoryCatalog] cannot open %s" % base_dir)
			return paths
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry == "." or entry == "..":
				entry = dir.get_next()
				continue
			if dir.current_is_dir():
				file_names.append(entry + "/")
			else:
				file_names.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()

	for file_name in file_names:
		if file_name.ends_with("/"):
			continue
		var resource_name := file_name
		if resource_name.ends_with(".remap"):
			resource_name = resource_name.trim_suffix(".remap")
		if resource_name.ends_with(".import"):
			continue
		var ext := resource_name.get_extension()
		if ext != "tres" and ext != "res":
			continue
		paths.append(base_dir.path_join(resource_name))
	return paths


static func _register_definition(def: Resource, source_dir: String) -> void:
	if def == null or not def is AccessoryDefinition:
		return
	var item := def as AccessoryDefinition
	var id := item.accessory_id.strip_edges()
	if id.is_empty():
		push_warning("[AccessoryCatalog] skip %s — empty accessory_id" % source_dir)
		return
	if _items_by_id.has(id):
		push_warning("[AccessoryCatalog] duplicate accessory_id '%s' — overwriting" % id)
	var acc_type := item.accessory_type.strip_edges()
	if acc_type.is_empty():
		push_warning("[AccessoryCatalog] '%s' missing accessory_type" % id)
		return
	_items_by_id[id] = item
	if not _items_by_type.has(acc_type):
		_items_by_type[acc_type] = []
	var bucket: Array = _items_by_type[acc_type]
	if not bucket.has(item):
		bucket.append(item)


static func _runtime_catalog_instance() -> AccessoryCatalog:
	_ensure_scanned()
	if _runtime_catalog == null:
		_runtime_catalog = AccessoryCatalog.new()
	_runtime_catalog.items = _all_definitions()
	return _runtime_catalog


static func _all_definitions() -> Array[AccessoryDefinition]:
	_ensure_scanned()
	var out: Array[AccessoryDefinition] = []
	for id in _items_by_id.keys():
		var def: Variant = _items_by_id[id]
		if def is AccessoryDefinition:
			out.append(def as AccessoryDefinition)
	return out


static func _items() -> Array:
	_ensure_scanned()
	return _all_definitions()


static func get_by_id(accessory_id: String) -> AccessoryDefinition:
	var id := migrate_accessory_id(accessory_id.strip_edges())
	if id.is_empty():
		return null
	_ensure_scanned()
	var def: Variant = _items_by_id.get(id)
	return def as AccessoryDefinition if def is AccessoryDefinition else null


static func list_by_type(accessory_type: String) -> Array[AccessoryDefinition]:
	var want := accessory_type.strip_edges()
	if want.is_empty():
		return []
	_ensure_scanned()
	var raw: Variant = _items_by_type.get(want, [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array[AccessoryDefinition] = []
	for item in raw as Array:
		if item is AccessoryDefinition:
			out.append(item as AccessoryDefinition)
	out.sort_custom(_sort_definitions_by_name)
	return out


static func _sort_definitions_by_name(a: AccessoryDefinition, b: AccessoryDefinition) -> bool:
	var an := definition_display_name(a, a.accessory_id if a else "")
	var bn := definition_display_name(b, b.accessory_id if b else "")
	if an == bn:
		return String(a.accessory_id) < String(b.accessory_id)
	return an < bn


static func display_name_for_id(accessory_id: String) -> String:
	var id := migrate_accessory_id(accessory_id.strip_edges())
	return definition_display_name(get_by_id(id), id)


static func description_for_id(accessory_id: String) -> String:
	var def := get_by_id(accessory_id)
	if def == null:
		return ""
	return def.description.strip_edges()


static func preview_path_for_id(accessory_id: String) -> String:
	var def := get_by_id(accessory_id)
	if def == null:
		return ""
	if not def.preview_path.is_empty():
		return def.preview_path
	return ""


static func scene_path_for_id(accessory_id: String) -> String:
	var id := resolve_field_id(accessory_id)
	var def := get_by_id(id)
	if def != null and not def.scene_path.is_empty():
		return def.scene_path
	return FieldBoardLayout.DEFAULT_FIELD_SCENE


static func preview_for_id(accessory_id: String) -> Texture2D:
	var def := get_by_id(accessory_id)
	var tex := definition_preview(def)
	if tex != null:
		return tex
	return _load_texture_path(preview_path_for_id(accessory_id))


static func definition_display_name(def: AccessoryDefinition, fallback_id: String = "") -> String:
	if def == null:
		return fallback_id
	if not def.display_name.is_empty():
		return def.display_name
	if not def.accessory_id.is_empty():
		return def.accessory_id
	return fallback_id


static func definition_preview(def: AccessoryDefinition) -> Texture2D:
	if def == null:
		return null
	if def.preview != null:
		return def.preview
	if not def.preview_path.is_empty():
		return _load_texture_path(def.preview_path)
	return null


static func _load_texture_path(path: String) -> Texture2D:
	var p := path.strip_edges()
	if p.is_empty():
		return null
	if _texture_cache.has(p):
		return _texture_cache[p] as Texture2D
	if not ResourceLoader.exists(p):
		push_warning("[AccessoryCatalog] missing preview texture: %s" % p)
		return null
	var tex := load(p) as Texture2D
	if tex != null:
		_texture_cache[p] = tex
	return tex


## 인스턴스 호환 — static 위임.
func get_definition(accessory_id: String) -> AccessoryDefinition:
	return get_by_id(accessory_id)
