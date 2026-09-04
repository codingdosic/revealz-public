class_name CollectionStore
extends RefCounted
## 프로필 collection/owned.json — CardData.id → { rarity → 장수 }.
## 토큰은 소유 개념 없음(조회 시 항상 보유·무제한).
## 권위는 Meta 스냅샷/구매·ops. 로컬 파일은 캐시만 (빈 파일에 시드하지 않음).


const OWNED_REL := "collection/owned.json"
## CardData.trigger_type TOKEN 비트 (OPEN=1 … VANILLA=64 다음).
const TRIGGER_TOKEN := 128
## 토큰 get_count 반환값(무제한 표시용). owns()는 true.
const UNLIMITED := 999999

## id(int) → Dictionary{ rarity(int) → count(int) }. 토큰 id는 넣지 않음.
static var _counts: Dictionary = {}
static var _loaded_account: String = ""


## collection/owned.json 절대 경로. 프로필 없으면 "".
static func owned_path() -> String:
	return AccountService.profile_path(OWNED_REL)


## 현재 계정 보유를 메모리에 올린다. 없거나 비면 빈 보유(시드 없음).
static func ensure_loaded() -> void:
	if not AccountService.is_bootstrapped():
		_counts.clear()
		_loaded_account = ""
		return
	var key := AccountService.current_id()
	if key == _loaded_account and not _counts.is_empty():
		return
	CardRegistry.ensure_loaded()
	_loaded_account = key
	_counts.clear()
	var path := owned_path()
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		_counts = _parse_counts(_read_json_dict(path))


## 디스크에서 다시 읽는다(테스트·계정 전환용).
static func reload() -> void:
	_loaded_account = ""
	_counts.clear()
	ensure_loaded()


## 메모리 보유를 owned.json에 쓴다. 성공 시 true (캐시만 · Meta PUT 없음).
static func save() -> bool:
	var path := owned_path()
	if path.is_empty():
		return false
	var payload: Dictionary = {}
	for id in _counts.keys():
		var by_rarity: Dictionary = _counts[id]
		var rarity_payload: Dictionary = {}
		for rarity in by_rarity.keys():
			var n := int(by_rarity[rarity])
			if n <= 0:
				continue
			rarity_payload[str(int(rarity))] = n
		if rarity_payload.is_empty():
			continue
		payload[str(int(id))] = rarity_payload
	return _write_json(path, payload)


## 서버 스냅샷 owned로 메모리·캐시 교체 (MetaSync 전용 · 재푸시 없음).
static func apply_remote_owned(owned: Dictionary) -> void:
	CardRegistry.ensure_loaded()
	_counts = _parse_counts(owned)
	_loaded_account = AccountService.current_id()
	var path := owned_path()
	if path.is_empty():
		return
	var payload: Dictionary = {}
	for id in _counts.keys():
		var by_rarity: Dictionary = _counts[id]
		var rarity_payload: Dictionary = {}
		for rarity in by_rarity.keys():
			var n := int(by_rarity[rarity])
			if n <= 0:
				continue
			rarity_payload[str(int(rarity))] = n
		if rarity_payload.is_empty():
			continue
		payload[str(int(id))] = rarity_payload
	_write_json(path, payload)


## 특정 등급 보유 장수. 토큰은 UNLIMITED.
static func get_count(card_id: int, rarity: int = CardRarity.Tier.N) -> int:
	ensure_loaded()
	if is_token_id(card_id):
		return UNLIMITED
	var by_rarity: Variant = _counts.get(card_id, {})
	if typeof(by_rarity) != TYPE_DICTIONARY:
		return 0
	return int((by_rarity as Dictionary).get(rarity, 0))


## 카드 id의 전 등급 합계. 토큰은 UNLIMITED.
static func total_count(card_id: int) -> int:
	ensure_loaded()
	if is_token_id(card_id):
		return UNLIMITED
	var by_rarity: Variant = _counts.get(card_id, {})
	if typeof(by_rarity) != TYPE_DICTIONARY:
		return 0
	var total := 0
	for rarity in (by_rarity as Dictionary).keys():
		total += int((by_rarity as Dictionary)[rarity])
	return total


## 카드 이름으로 특정 등급 장수.
static func get_count_by_name(card_name: String, rarity: int = CardRarity.Tier.N) -> int:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return 0
	return get_count(int(data.id), rarity)


## 카드 이름 전 등급 합계.
static func total_count_by_name(card_name: String) -> int:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return 0
	return total_count(int(data.id))


## 특정 등급 보유 여부. 토큰은 항상 true.
static func owns(card_id: int, rarity: int = CardRarity.Tier.N) -> bool:
	ensure_loaded()
	if is_token_id(card_id):
		return true
	return get_count(card_id, rarity) > 0


## 아무 등급이라도 보유하면 true. 토큰은 항상 true.
static func owns_any(card_id: int) -> bool:
	ensure_loaded()
	if is_token_id(card_id):
		return true
	return total_count(card_id) > 0


## 카드 이름·등급 보유 여부.
static func owns_name(card_name: String, rarity: int = CardRarity.Tier.N) -> bool:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return false
	return owns(int(data.id), rarity)


## 카드 이름 아무 등급 보유 여부.
static func owns_name_any(card_name: String) -> bool:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return false
	return owns_any(int(data.id))


## 보유 장수 조회 등은 캐시 기준. 지급·차감은 Meta TX만 (로컬 add API 없음).


## id → { rarity → count } 사본.
static func all_counts_by_rarity() -> Dictionary:
	ensure_loaded()
	return _counts.duplicate(true)


## 레거시 호환: id → 전 등급 합계.
static func all_counts() -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	for id in _counts.keys():
		out[id] = total_count(int(id))
	return out


## TOKEN 플래그 카드인지 (id). 미등록이면 false.
static func is_token_id(card_id: int) -> bool:
	var data := CardRegistry.get_by_id(card_id)
	if data == null:
		return false
	return (int(data.trigger_type) & TRIGGER_TOKEN) != 0


## TOKEN 플래그 카드인지 (이름).
static func is_token_name(card_name: String) -> bool:
	var data := CardRegistry.get_by_name(card_name)
	if data == null:
		return false
	return (int(data.trigger_type) & TRIGGER_TOKEN) != 0


## owned.json → id→{rarity→count}. 구형 flat(int)이면 {} 반환.
static func _parse_counts(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	# 구형: 값이 int이면 전체 폐기.
	for key in raw.keys():
		var v: Variant = raw[key]
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			return {}
		if typeof(v) != TYPE_DICTIONARY:
			return {}
	var out: Dictionary = {}
	for key in raw.keys():
		var id := int(str(key))
		if id <= 0 or is_token_id(id):
			continue
		var rarity_raw: Dictionary = raw[key]
		var by_rarity: Dictionary = {}
		for rkey in rarity_raw.keys():
			var rarity := clampi(int(str(rkey)), CardRarity.Tier.N, CardRarity.Tier.UR)
			var n := int(rarity_raw[rkey])
			if n <= 0:
				continue
			by_rarity[rarity] = n
		if by_rarity.is_empty():
			continue
		out[id] = by_rarity
	return out


## JSON 읽기. 없거나 실패 시 {}.
static func _read_json_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


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
