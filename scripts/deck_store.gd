class_name DeckStore
extends RefCounted
## 프로필 decks/ 저장·목록·포맷별 검증. 기본 5종은 가상(파일 없음).
## 디스크 SSOT: card_ids + card_rarities(병렬, N=0..UR=3). 구형 card_names는 로드 시 마이그레이션.
## 런타임/MP는 card_ids_of 우선 (IdKey). card_names_of는 UI·듀얼라이트용.
## format mono: 저장=0~30(빌딩 규칙만) · 플레이=정확히 30장·동일 id≤2·단색+무색. format none: 빌딩 제한 없음.


const FORMAT_MONO := "mono"
const FORMAT_NONE := "none"
const DECK_SIZE := 30
const MAX_COPIES := 2
const DECKS_REL := "decks"
## builtin 덱 악세서리 override 경로 — AccessoryStore.DECK_OVERRIDES_REL 과 동일.
const DECK_ACCESSORY_OVERRIDES_REL := "accessories/deck_overrides.json"
const BUILTIN_PREFIX := "builtin_"
## 최근 선택/편집 시각(id→unix sec). decks/ 밖이라 remote wipe에 안 지워짐.
const RECENCY_REL := "deck_recency.json"

## 기본 덱·mono base_color용. colorless는 기본 덱에 넣지 않음.
const BASE_COLORS: Array[String] = ["black", "red", "blue", "green", "white"]
## 덱 에디터 색 필터용 (검색에 colorless 포함).
const FILTER_COLORS: Array[String] = ["black", "red", "blue", "green", "white", "colorless"]
const FORMATS: Array[String] = [FORMAT_MONO, FORMAT_NONE]
## 덱에 붙는 악세서리 타입 (프로필 icon 제외).
const DECK_ACCESSORY_TYPES: Array[String] = [
	AccessoryTypes.TYPE_CARD_BACK,
	AccessoryTypes.TYPE_FIELD,
]

## id → last touched unix sec. 계정별로 로드.
static var _recency: Dictionary = {}
static var _recency_account: String = ""


## 프로필 decks/ 디렉터리. AccountService 미부팅이면 빈 문자열.
static func decks_dir() -> String:
	return AccountService.profile_path(DECKS_REL)


## 선택 UI용: 기본 5종 + 사용자 덱. 최근 터치 내림차순.
static func list_selectable_decks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(list_builtin_decks())
	out.append_array(list_user_decks_unsorted())
	_sort_decks_by_recency(out)
	return out


## 가상 기본 5색 덱 메타. colorless는 조건으로 제외.
static func list_builtin_decks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for color_key in BASE_COLORS:
		if color_key == "colorless":
			continue
		out.append(make_builtin_deck(color_key))
	return out


## decks/*.json 사용자 덱 로드(요약). 최근 터치 내림차순.
static func list_user_decks() -> Array[Dictionary]:
	var out := list_user_decks_unsorted()
	_sort_decks_by_recency(out)
	return out


## 사용자 덱 목록(정렬 없음). list_selectable이 builtins와 합친 뒤 한 번 정렬할 때 사용.
static func list_user_decks_unsorted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir_path := decks_dir()
	if dir_path.is_empty():
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var deck := load_deck(file_name.get_basename())
			if not deck.is_empty() and not bool(deck.get("readonly", false)):
				out.append(deck)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


## 덱을 최근 사용으로 표시. Select/Edit/저장 시 호출.
static func touch_deck(deck_id: String) -> void:
	var id := deck_id.strip_edges()
	if id.is_empty():
		return
	_ensure_recency_loaded()
	_recency[id] = int(Time.get_unix_time_from_system())
	_save_recency()


## 덱의 마지막 터치 unix sec. 없으면 0.
static func touched_at(deck_id: String) -> int:
	_ensure_recency_loaded()
	return int(_recency.get(deck_id.strip_edges(), 0))


## id로 덱 로드. builtin_* 는 가상, 그 외는 JSON(ids 정규화).
static func load_deck(deck_id: String) -> Dictionary:
	var id := deck_id.strip_edges()
	if id.is_empty():
		return {}
	if id.begins_with(BUILTIN_PREFIX):
		var color_key := id.substr(BUILTIN_PREFIX.length())
		return make_builtin_deck(color_key)
	var path := _deck_path(id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	return _read_json_dict(path)


## 덱 저장. 저장용 검증 실패 시 {ok:false, error}. builtin id면 거부. 디스크에는 card_ids만.
## mono는 0~30장 저장 가능(플레이용 30장은 is_playable 참고). Meta 사용 중이면 스냅샷 PUT.
static func save_deck(deck: Dictionary) -> Dictionary:
	if bool(deck.get("readonly", false)) or String(deck.get("id", "")).begins_with(BUILTIN_PREFIX):
		return {"ok": false, "error": "Cannot overwrite builtin deck — use New/Save As"}
	var format := normalize_format(String(deck.get("format", FORMAT_MONO)))
	deck["format"] = format
	normalize_deck_cards(deck)
	var err := validate_for_save(deck)
	if not err.is_empty():
		return {"ok": false, "error": err}
	var id := String(deck.get("id", "")).strip_edges()
	if id.is_empty():
		id = _new_uuid()
		deck["id"] = id
	var path := _deck_path(id)
	if path.is_empty():
		return {"ok": false, "error": "No profile path"}
	var acc_err := validate_deck_accessories(normalize_deck_accessories(deck.get("accessories", {})))
	if not acc_err.is_empty():
		return {"ok": false, "error": acc_err}
	repair_main_card_in_deck(deck)
	if not _write_json(path, _deck_to_disk_dict(deck)):
		return {"ok": false, "error": "Write failed"}
	touch_deck(id)
	_push_meta_if_needed()
	return {"ok": true, "error": "", "id": id}


## 사용자 덱 파일 삭제. builtin은 false. Meta 사용 중이면 스냅샷 PUT.
static func delete_deck(deck_id: String) -> bool:
	var id := deck_id.strip_edges()
	if id.is_empty() or id.begins_with(BUILTIN_PREFIX):
		return false
	var path := _deck_path(id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	if DirAccess.remove_absolute(path) != OK:
		return false
	_ensure_recency_loaded()
	if _recency.has(id):
		_recency.erase(id)
		_save_recency()
	_push_meta_if_needed()
	return true


## 서버 덱 목록으로 로컬 decks/ 유저 덱을 교체 (MetaSync 전용 · 재푸시 없음).
## 원격에 main_card가 없으면(구 로비) 기존 로컬 선택을 유지한다.
static func apply_remote_decks(decks: Array) -> void:
	var dir_path := decks_dir()
	if dir_path.is_empty():
		return
	_make_dir(dir_path)
	var preserved_main: Dictionary = _peek_local_main_cards(dir_path)
	# 기존 유저 덱 파일 제거
	var dir := DirAccess.open(dir_path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				DirAccess.remove_absolute("%s/%s" % [dir_path, file_name])
			file_name = dir.get_next()
		dir.list_dir_end()
	for item in decks:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var deck: Dictionary = (item as Dictionary).duplicate(true)
		var id := String(deck.get("id", "")).strip_edges()
		if id.is_empty() or id.begins_with(BUILTIN_PREFIX):
			continue
		normalize_deck_cards(deck)
		var remote_mc := normalize_main_card_raw(deck.get("main_card", {}))
		if remote_mc.is_empty() and preserved_main.has(id):
			deck["main_card"] = (preserved_main[id] as Dictionary).duplicate(true)
		else:
			deck["main_card"] = remote_mc
		var path := _deck_path(id)
		if path.is_empty():
			continue
		_write_json(path, _deck_to_disk_dict(deck))


## 디스크 덱 JSON에서 main_card만 수집 (repair 없이). id → {card_id, rarity}
static func _peek_local_main_cards(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var deck_id := file_name.get_basename()
			var text := _read_text_file("%s/%s" % [dir_path, file_name])
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				var mc := normalize_main_card_raw((parsed as Dictionary).get("main_card", {}))
				if not mc.is_empty():
					out[deck_id] = mc
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


## 덱 accessories 기본값 (card_back · field).
static func default_deck_accessories() -> Dictionary:
	return {
		AccessoryTypes.TYPE_CARD_BACK: AccessoryCatalog.DEFAULT_CARD_BACK_ID,
		AccessoryTypes.TYPE_FIELD: AccessoryCatalog.DEFAULT_FIELD_ID,
	}


## accessories dict 정규화 — 미지정 타입은 기본 id.
static func normalize_deck_accessories(raw: Variant) -> Dictionary:
	var out := default_deck_accessories()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d := raw as Dictionary
	for t in DECK_ACCESSORY_TYPES:
		var id := AccessoryCatalog.migrate_accessory_id(String(d.get(t, "")))
		if not id.is_empty():
			out[t] = id
	return out


## 덱 id/dict의 accessories.
static func accessories_of(deck_id_or_dict: Variant) -> Dictionary:
	var deck := _deck_dict(deck_id_or_dict)
	if deck.is_empty():
		return default_deck_accessories()
	return normalize_deck_accessories(deck.get("accessories", {}))


## 덱의 card_back catalog id.
static func card_back_id_of(deck_id_or_dict: Variant) -> String:
	var acc := accessories_of(deck_id_or_dict)
	return AccessoryCatalog.resolve_card_back_id(String(acc.get(AccessoryTypes.TYPE_CARD_BACK, "")))


## 덱의 field catalog id.
static func field_id_of(deck_id_or_dict: Variant) -> String:
	var acc := accessories_of(deck_id_or_dict)
	return AccessoryCatalog.resolve_field_id(String(acc.get(AccessoryTypes.TYPE_FIELD, "")))


## 보유 악세서리만 허용. 통과 시 "".
static func validate_deck_accessories(accessories: Dictionary) -> String:
	AccessoryStore.ensure_loaded()
	for t in DECK_ACCESSORY_TYPES:
		var id := String(accessories.get(t, "")).strip_edges()
		if id.is_empty():
			continue
		if not AccessoryStore.owns(t, id):
			return "Not owned accessory: %s" % id
	return ""


## 덱 accessories만 저장. builtin은 deck_overrides.json (로컬 전용).
static func save_deck_accessories(deck_id: String, accessories: Dictionary) -> Dictionary:
	var id := deck_id.strip_edges()
	if id.is_empty():
		return {"ok": false, "error": "Empty deck id"}
	var normalized := normalize_deck_accessories(accessories)
	var err := validate_deck_accessories(normalized)
	if not err.is_empty():
		return {"ok": false, "error": err}
	if id.begins_with(BUILTIN_PREFIX):
		return _save_builtin_deck_override(id, normalized, null)
	var deck := load_deck(id)
	if deck.is_empty():
		return {"ok": false, "error": "Deck not found"}
	deck["accessories"] = normalized
	return save_deck(deck)


## main_card 미지정(빈 dict). resolve 시 덱 첫 카드로 대체.
static func default_main_card() -> Dictionary:
	return {}


## raw → {card_id:int, rarity:int} 또는 {}.
static func normalize_main_card_raw(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return default_main_card()
	var d := raw as Dictionary
	var card_id := int(d.get("card_id", 0))
	if card_id <= 0:
		return default_main_card()
	var rarity := clampi(int(d.get("rarity", CardRarity.Tier.N)), CardRarity.Tier.N, CardRarity.Tier.UR)
	return {"card_id": card_id, "rarity": rarity}


## 선택 키 "card_id:rarity".
static func encode_main_card_key(card_id: int, rarity: int) -> String:
	return "%d:%d" % [
		card_id,
		clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR),
	]


## "card_id:rarity" → {card_id, rarity} 또는 {}.
static func parse_main_card_key(key: String) -> Dictionary:
	var parts := key.strip_edges().split(":")
	if parts.size() != 2:
		return default_main_card()
	var card_id := int(parts[0])
	if card_id <= 0:
		return default_main_card()
	var rarity := clampi(int(parts[1]), CardRarity.Tier.N, CardRarity.Tier.UR)
	return {"card_id": card_id, "rarity": rarity}


## 덱에 (id, rarity) 카피가 있으면 true.
static func deck_has_main_card_copy(deck: Dictionary, card_id: int, rarity: int) -> bool:
	normalize_deck_cards(deck)
	var ids := _ids_to_array(deck.get("card_ids", []))
	var rarities := _rarities_to_array(deck.get("card_rarities", []), ids.size())
	var want_r := clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	for i in ids.size():
		if ids[i] == card_id and rarities[i] == want_r:
			return true
	return false


## 표시용 main card. 저장값 유효하면 그것, 아니면 첫 카드. 빈 덱이면 {}.
## 반환: {card_id, rarity, name, key} 또는 {}.
static func resolve_main_card(deck: Dictionary) -> Dictionary:
	if deck.is_empty():
		return {}
	normalize_deck_cards(deck)
	var ids := _ids_to_array(deck.get("card_ids", []))
	var rarities := _rarities_to_array(deck.get("card_rarities", []), ids.size())
	if ids.is_empty():
		return {}
	var stored := normalize_main_card_raw(deck.get("main_card", {}))
	var card_id: int
	var rarity: int
	if not stored.is_empty() and deck_has_main_card_copy(deck, int(stored["card_id"]), int(stored["rarity"])):
		card_id = int(stored["card_id"])
		rarity = int(stored["rarity"])
	else:
		card_id = ids[0]
		rarity = rarities[0]
	var data := CardRegistry.get_by_id(card_id)
	var cname := String(data.card_name) if data != null else ""
	return {
		"card_id": card_id,
		"rarity": rarity,
		"name": cname,
		"key": encode_main_card_key(card_id, rarity),
	}


## 덱 id/dict의 표시용 main card (resolve).
static func main_card_of(deck_id_or_dict: Variant) -> Dictionary:
	var deck := _deck_dict(deck_id_or_dict)
	if deck.is_empty():
		return {}
	return resolve_main_card(deck)


## 덱 내 유니크 (card_id, rarity) 목록. 등장 순. [{card_id, rarity, name, key}, ...]
static func list_unique_main_card_options(deck_id_or_dict: Variant) -> Array[Dictionary]:
	var deck := _deck_dict(deck_id_or_dict)
	var out: Array[Dictionary] = []
	if deck.is_empty():
		return out
	normalize_deck_cards(deck)
	var ids := _ids_to_array(deck.get("card_ids", []))
	var rarities := _rarities_to_array(deck.get("card_rarities", []), ids.size())
	var seen: Dictionary = {}
	for i in ids.size():
		var card_id := ids[i]
		var rarity := rarities[i]
		var key := encode_main_card_key(card_id, rarity)
		if seen.has(key):
			continue
		seen[key] = true
		var data := CardRegistry.get_by_id(card_id)
		var cname := String(data.card_name) if data != null else str(card_id)
		out.append({
			"card_id": card_id,
			"rarity": rarity,
			"name": cname,
			"key": key,
		})
	return out


## 무효 main_card를 첫 카드(또는 빈 dict)로 고친다.
static func repair_main_card_in_deck(deck: Dictionary) -> void:
	if deck.is_empty():
		return
	normalize_deck_cards(deck)
	var ids := _ids_to_array(deck.get("card_ids", []))
	if ids.is_empty():
		deck["main_card"] = default_main_card()
		return
	var resolved := resolve_main_card(deck)
	deck["main_card"] = {
		"card_id": int(resolved.get("card_id", 0)),
		"rarity": int(resolved.get("rarity", CardRarity.Tier.N)),
	}


## main_card만 저장. builtin은 deck_overrides.json.
static func save_deck_main_card(deck_id: String, card_id: int, rarity: int) -> Dictionary:
	var id := deck_id.strip_edges()
	if id.is_empty():
		return {"ok": false, "error": "Empty deck id"}
	var deck := load_deck(id)
	if deck.is_empty():
		return {"ok": false, "error": "Deck not found"}
	var tier := clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	if not deck_has_main_card_copy(deck, card_id, tier):
		return {"ok": false, "error": "Card not in deck"}
	var stored := {"card_id": card_id, "rarity": tier}
	if id.begins_with(BUILTIN_PREFIX):
		return _save_builtin_deck_override(id, null, stored)
	deck["main_card"] = stored
	return save_deck(deck)


## MetaSync 스냅샷 푸시.
static func _push_meta_if_needed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sync := tree.root.get_node_or_null("/root/MetaSync")
	if sync == null or bool(sync.get("applying_remote")):
		return
	sync.call("push_snapshot_async")


## decks 디렉터리 보장.
static func _make_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)


## 포맷별 검증. require_full_mono=true면 mono 30장 필수(플레이). false면 장수 생략(저장).
## 통과 시 "" , 실패 시 사유.
static func validate_deck(deck: Dictionary, require_full_mono: bool = true) -> String:
	normalize_deck_cards(deck)
	var format := normalize_format(String(deck.get("format", FORMAT_MONO)))
	match format:
		FORMAT_NONE:
			return validate_none(deck)
		FORMAT_MONO:
			return validate_mono(deck, require_full_mono)
		_:
			return "Unsupported format: %s" % format


## 디스크 저장용 검증 (mono 미완·0장 허용).
static func validate_for_save(deck: Dictionary) -> String:
	return validate_deck(deck, false)


## 매치 진입용 검증 (mono는 정확히 30장).
static func validate_for_play(deck: Dictionary) -> String:
	return validate_deck(deck, true)


## 매치에 쓸 수 있는 덱이면 true.
static func is_playable(deck: Dictionary) -> bool:
	if deck.is_empty():
		return false
	return validate_for_play(deck).is_empty()


## id로 로드한 뒤 플레이 가능 여부.
static func is_playable_id(deck_id: String) -> bool:
	return is_playable(load_deck(deck_id))


## 플레이 불가 사유(한글 UI). 가능하면 "".
static func describe_play_block_ko(deck_id: String) -> String:
	var id := deck_id.strip_edges()
	if id.is_empty():
		return "덱이 선택되지 않았습니다"
	var deck := load_deck(id)
	if deck.is_empty():
		return "덱을 찾을 수 없습니다"
	var err := validate_for_play(deck)
	if err.is_empty():
		return ""
	var format := normalize_format(String(deck.get("format", FORMAT_MONO)))
	var ids := _ids_to_array(deck.get("card_ids", []))
	if format == FORMAT_MONO:
		if ids.size() != DECK_SIZE:
			return "mono 덱은 %d장이어야 합니다 (현재 %d장)" % [DECK_SIZE, ids.size()]
		if err.find("Too many copies") >= 0:
			return "같은 카드는 최대 %d장까지입니다" % MAX_COPIES
		if err.find("not allowed in mono") >= 0 or err.find("Invalid base_color") >= 0:
			return "단색(+무색) 구성이 아닙니다"
		if err.find("Unknown card") >= 0 or err.find("Invalid card") >= 0:
			return "유효하지 않은 카드가 포함되어 있습니다"
	elif format == FORMAT_NONE:
		if err.find("Unknown card") >= 0 or err.find("Invalid card") >= 0:
			return "유효하지 않은 카드가 포함되어 있습니다"
	return "덱 조건 미달"


## none: 장수·색·중복 제한 없음. 빈/미등록 id만 거부. 0장도 허용.
static func validate_none(deck: Dictionary) -> String:
	normalize_deck_cards(deck)
	for card_id in _ids_to_array(deck.get("card_ids", [])):
		if card_id <= 0:
			return "Invalid card id in deck"
		if CardRegistry.get_by_id(card_id) == null:
			return "Unknown card id in deck: %d" % card_id
	return ""


## mono 규칙 검사. 통과 시 "" , 실패 시 사유.
## require_full_size=false면 0~29장도 OK(저장). true면 정확히 DECK_SIZE(플레이).
## 유채색은 덱 내 카드에서 추론. 비어 있으면 필드 base_color fallback.
static func validate_mono(deck: Dictionary, require_full_size: bool = true) -> String:
	normalize_deck_cards(deck)
	var names := _names_to_array(deck.get("card_names", []))
	var ids := _ids_to_array(deck.get("card_ids", []))
	if require_full_size and ids.size() != DECK_SIZE:
		return "Deck must be exactly %d cards (have %d)" % [DECK_SIZE, ids.size()]
	if ids.size() > DECK_SIZE:
		return "Deck exceeds %d cards (have %d)" % [DECK_SIZE, ids.size()]
	var derived := mono_base_from_card_names(names)
	var base := derived
	if base.is_empty():
		base = String(deck.get("base_color", "")).strip_edges().to_lower()
	if not BASE_COLORS.has(base):
		return "Invalid base_color"
	var counts: Dictionary = {}
	for i in ids.size():
		var card_id := ids[i]
		if card_id <= 0:
			return "Invalid card id in deck"
		var card_name := names[i] if i < names.size() else ""
		if card_name.is_empty():
			return "Unknown card id in deck: %d" % card_id
		if not CardRegistry.card_allowed_in_mono(card_name, base):
			return "Card not allowed in mono %s: %s" % [base, card_name]
		counts[card_id] = int(counts.get(card_id, 0)) + 1
		if int(counts[card_id]) > MAX_COPIES:
			return "Too many copies of id %d (max %d)" % [card_id, MAX_COPIES]
	return ""


## 덱 카드들의 유채색 단색 키. 무색만/비어 있으면 "". 서로 다른 유채색이면 "".
static func mono_base_from_card_names(card_names: Array) -> String:
	var found := ""
	for card_name in _names_to_array(card_names):
		var key := CardRegistry.color_key_for_card_name(String(card_name))
		if key.is_empty():
			continue
		if found.is_empty():
			found = key
		elif found != key:
			return ""
	return found


## 알려진 포맷으로 정규화. 모르면 mono.
static func normalize_format(format: String) -> String:
	var f := format.strip_edges().to_lower()
	if f == FORMAT_NONE:
		return FORMAT_NONE
	return FORMAT_MONO


## 빌딩 제한이 없는 포맷인지.
static func is_unrestricted_format(format: String) -> bool:
	return normalize_format(format) == FORMAT_NONE


## 빈 사용자 덱 골격(카드 0장). 저장 전 채워야 한다.
static func make_empty_user_deck(base_color: String, display_name: String = "") -> Dictionary:
	var base := _sanitize_base_color(base_color)
	var name := display_name.strip_edges()
	if name.is_empty():
		name = "%s Deck" % base.capitalize()
	return {
		"id": _new_uuid(),
		"name": name,
		"format": FORMAT_MONO,
		"base_color": base,
		"card_ids": [] as Array[int],
		"card_names": [] as Array[String],
		"card_rarities": [] as Array[int],
		"accessories": default_deck_accessories(),
		"main_card": default_main_card(),
		"readonly": false,
	}


## 기본 색 덱을 사용자 덱으로 복제한 초안(새 id, readonly=false).
static func clone_builtin_as_user(base_color: String, display_name: String = "") -> Dictionary:
	var builtin := make_builtin_deck(base_color)
	var name := display_name.strip_edges()
	if name.is_empty():
		name = "%s Custom" % String(builtin.get("name", "Deck"))
	var deck := {
		"id": _new_uuid(),
		"name": name,
		"format": FORMAT_MONO,
		"base_color": String(builtin.get("base_color", "black")),
		"card_ids": _ids_to_array(builtin.get("card_ids", [])),
		"card_names": _names_to_array(builtin.get("card_names", [])),
		"card_rarities": _rarities_to_array(builtin.get("card_rarities", []), _ids_to_array(builtin.get("card_ids", [])).size()),
		"accessories": accessories_of(builtin),
		"main_card": normalize_main_card_raw(builtin.get("main_card", {})),
		"readonly": false,
	}
	normalize_deck_cards(deck)
	repair_main_card_in_deck(deck)
	return deck


## 가상 기본 덱 Dictionary. colorless 요청 시 black으로 폴백.
static func make_builtin_deck(base_color: String) -> Dictionary:
	var base := _sanitize_base_color(base_color)
	var color := CardRegistry.deck_color_from_key(base)
	var names := CardRegistry.build_deck_for_color(color)
	var ids := names_to_ids(names)
	var deck := {
		"id": BUILTIN_PREFIX + base,
		"name": "%s (Default)" % base.to_upper(),
		"format": FORMAT_MONO,
		"base_color": base,
		"card_names": names,
		"card_ids": ids,
		"card_rarities": _rarities_filled(ids.size(), CardRarity.Tier.N),
		"accessories": _accessories_for_deck_id(BUILTIN_PREFIX + base),
		"main_card": _main_card_raw_for_deck_id(BUILTIN_PREFIX + base),
		"readonly": true,
	}
	return deck


## 덱의 카드 이름 배열. card_ids 우선 정규화 후 반환.
static func card_names_of(deck_id_or_dict: Variant) -> Array[String]:
	var deck := _deck_dict(deck_id_or_dict)
	if deck.is_empty():
		return [] as Array[String]
	normalize_deck_cards(deck)
	return _names_to_array(deck.get("card_names", []))


## 덱의 카드 id 배열.
static func card_ids_of(deck_id_or_dict: Variant) -> Array[int]:
	var deck := _deck_dict(deck_id_or_dict)
	if deck.is_empty():
		return [] as Array[int]
	normalize_deck_cards(deck)
	return _ids_to_array(deck.get("card_ids", []))


## 덱의 카드 등급 배열 (ids와 동일 길이).
static func card_rarities_of(deck_id_or_dict: Variant) -> Array[int]:
	var deck := _deck_dict(deck_id_or_dict)
	if deck.is_empty():
		return [] as Array[int]
	normalize_deck_cards(deck)
	return _rarities_to_array(deck.get("card_rarities", []), _ids_to_array(deck.get("card_ids", [])).size())


## 메모리 덱의 카드 목록을 이름·등급으로 맞추고 ids도 동기화.
static func set_deck_cards(deck: Dictionary, card_names: Array, card_rarities: Array = []) -> void:
	var names := _names_to_array(card_names)
	deck["card_names"] = names
	deck["card_ids"] = names_to_ids(names)
	deck["card_rarities"] = _rarities_to_array(card_rarities, names.size())


## 메모리 덱의 카드 목록을 이름 배열로 맞추고 card_ids도 동기화. 등급은 길이 맞춤(부족분 N).
static func set_card_names(deck: Dictionary, card_names: Array) -> void:
	var prev := _rarities_to_array(deck.get("card_rarities", []), 0)
	set_deck_cards(deck, card_names, prev)


## card_ids / card_names 중 있는 쪽으로 양쪽을 맞춘다. ids 우선. rarities 길이 맞춤.
static func normalize_deck_cards(deck: Dictionary) -> void:
	var ids := _ids_to_array(deck.get("card_ids", []))
	var names := _names_to_array(deck.get("card_names", []))
	if not ids.is_empty():
		deck["card_ids"] = ids
		deck["card_names"] = ids_to_names(ids)
	elif not names.is_empty():
		deck["card_names"] = names
		deck["card_ids"] = names_to_ids(names)
		ids = deck["card_ids"]
	else:
		deck["card_ids"] = [] as Array[int]
		deck["card_names"] = [] as Array[String]
		ids = [] as Array[int]
	deck["card_rarities"] = _rarities_to_array(deck.get("card_rarities", []), ids.size())


## 이름 배열 → CardData.id 배열. 미등록은 0.
static func names_to_ids(card_names: Array) -> Array[int]:
	CardRegistry.ensure_loaded()
	var out: Array[int] = []
	for card_name in _names_to_array(card_names):
		var data := CardRegistry.get_by_name(card_name)
		out.append(int(data.id) if data != null else 0)
	return out


## id 배열 → 이름 배열. 미등록은 "".
static func ids_to_names(card_ids: Array) -> Array[String]:
	CardRegistry.ensure_loaded()
	var out: Array[String] = []
	for card_id in _ids_to_array(card_ids):
		var data := CardRegistry.get_by_id(card_id)
		out.append(String(data.card_name) if data != null else "")
	return out


## builtin 여부.
static func is_builtin_id(deck_id: String) -> bool:
	return deck_id.begins_with(BUILTIN_PREFIX)


## mono/기본 덱에 쓸 색. colorless·미지수면 black.
static func _sanitize_base_color(base_color: String) -> String:
	var base := base_color.strip_edges().to_lower()
	if base == "colorless" or not BASE_COLORS.has(base):
		return "black"
	return base


## id 또는 dict에서 덱 Dictionary.
static func _deck_dict(deck_id_or_dict: Variant) -> Dictionary:
	if typeof(deck_id_or_dict) == TYPE_DICTIONARY:
		return deck_id_or_dict as Dictionary
	return load_deck(String(deck_id_or_dict))


## decks/{id}.json 경로.
static func _deck_path(deck_id: String) -> String:
	var root := decks_dir()
	if root.is_empty():
		return ""
	return root.path_join("%s.json" % deck_id)


## 최근 사용 시각 내림차순, 동점이면 이름 오름차순.
static func _sort_decks_by_recency(decks: Array[Dictionary]) -> void:
	_ensure_recency_loaded()
	decks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(_recency.get(String(a.get("id", "")), 0))
		var tb := int(_recency.get(String(b.get("id", "")), 0))
		if ta != tb:
			return ta > tb
		return String(a.get("name", "")) < String(b.get("name", ""))
	)


## 현재 계정 recency 로드.
static func _ensure_recency_loaded() -> void:
	if not AccountService.is_bootstrapped():
		_recency.clear()
		_recency_account = ""
		return
	var key := AccountService.current_id()
	if key == _recency_account:
		return
	_recency_account = key
	_recency.clear()
	var path := AccountService.profile_path(RECENCY_REL)
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for id in (parsed as Dictionary).keys():
		_recency[String(id)] = int((parsed as Dictionary)[id])


## recency.json 저장.
static func _save_recency() -> void:
	var path := AccountService.profile_path(RECENCY_REL)
	if path.is_empty():
		return
	var payload: Dictionary = {}
	for id in _recency.keys():
		payload[String(id)] = int(_recency[id])
	_write_json(path, payload)


## Variant 배열을 Array[String]으로 정규화.
static func _names_to_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for item in raw as Array:
			out.append(String(item))
	return out


## Variant 배열을 Array[int]으로 정규화.
static func _ids_to_array(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if raw is Array:
		for item in raw as Array:
			out.append(int(item))
	return out


## 등급 배열을 expected_len에 맞춰 정규화. 부족분은 N, 초과는 자름.
static func _rarities_to_array(raw: Variant, expected_len: int) -> Array[int]:
	var out: Array[int] = []
	if raw is Array:
		for item in raw as Array:
			out.append(clampi(int(item), CardRarity.Tier.N, CardRarity.Tier.UR))
	while out.size() < expected_len:
		out.append(CardRarity.Tier.N)
	if out.size() > expected_len:
		out.resize(expected_len)
	return out


## 동일 등급으로 채운 배열.
static func _rarities_filled(length: int, rarity: int) -> Array[int]:
	var out: Array[int] = []
	var tier := clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	for _i in length:
		out.append(tier)
	return out


## JSON 읽기 후 card_ids 정규화.
static func _read_json_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d := parsed as Dictionary
	d["readonly"] = false
	normalize_deck_cards(d)
	d["accessories"] = normalize_deck_accessories(d.get("accessories", {}))
	d["main_card"] = normalize_main_card_raw(d.get("main_card", {}))
	repair_main_card_in_deck(d)
	return d


## JSON 쓰기.
static func _write_json(path: String, data: Dictionary) -> bool:
	var parent := path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## 디스크/API용 덱 dict (card_ids · accessories · main_card 포함).
static func _deck_to_disk_dict(deck: Dictionary) -> Dictionary:
	var ids := _ids_to_array(deck.get("card_ids", []))
	repair_main_card_in_deck(deck)
	return {
		"id": String(deck.get("id", "")),
		"name": String(deck.get("name", "Deck")),
		"format": normalize_format(String(deck.get("format", FORMAT_MONO))),
		"base_color": String(deck.get("base_color", "black")),
		"card_ids": ids,
		"card_rarities": _rarities_to_array(deck.get("card_rarities", []), ids.size()),
		"accessories": normalize_deck_accessories(deck.get("accessories", {})),
		"main_card": normalize_main_card_raw(deck.get("main_card", {})),
	}


## deck_id accessories — builtin override 또는 기본.
static func _accessories_for_deck_id(deck_id: String) -> Dictionary:
	return _override_entry_of(deck_id)["accessories"] as Dictionary


## builtin override의 main_card raw (미지정이면 {}).
static func _main_card_raw_for_deck_id(deck_id: String) -> Dictionary:
	return normalize_main_card_raw(_override_entry_of(deck_id).get("main_card", {}))


## overrides[id] 정규화. 구형(액세서리 dict만)도 지원.
static func _override_entry_of(deck_id: String) -> Dictionary:
	var id := deck_id.strip_edges()
	var overrides := _load_deck_accessory_overrides()
	var out := {
		"accessories": default_deck_accessories(),
		"main_card": default_main_card(),
	}
	if id.is_empty() or not overrides.has(id):
		return out
	var raw: Variant = overrides[id]
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d := raw as Dictionary
	if d.has("accessories") or d.has("main_card"):
		out["accessories"] = normalize_deck_accessories(d.get("accessories", {}))
		out["main_card"] = normalize_main_card_raw(d.get("main_card", {}))
		return out
	# legacy: 값 전체가 accessories
	out["accessories"] = normalize_deck_accessories(d)
	return out


## builtin override 저장. null 인자는 기존 값 유지.
static func _save_builtin_deck_override(
	deck_id: String,
	accessories: Variant = null,
	main_card: Variant = null
) -> Dictionary:
	var overrides := _load_deck_accessory_overrides()
	var entry := _override_entry_of(deck_id)
	if accessories != null:
		entry["accessories"] = normalize_deck_accessories(accessories)
	if main_card != null:
		entry["main_card"] = normalize_main_card_raw(main_card)
	overrides[deck_id] = entry
	if not _write_deck_accessory_overrides(overrides):
		return {"ok": false, "error": "Write failed"}
	return {"ok": true, "error": "", "id": deck_id}


static func _load_deck_accessory_overrides() -> Dictionary:
	var path := AccountService.profile_path(DECK_ACCESSORY_OVERRIDES_REL)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(_read_text_file(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func _write_deck_accessory_overrides(data: Dictionary) -> bool:
	var path := AccountService.profile_path(DECK_ACCESSORY_OVERRIDES_REL)
	if path.is_empty():
		return false
	return _write_json(path, data)


static func _read_text_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


## uuid4 문자열.
static func _new_uuid() -> String:
	var crypto := Crypto.new()
	var b := crypto.generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
		b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
	]
