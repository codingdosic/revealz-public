class_name ShopCardPool
extends Resource
## 상점 팩 출현 풀. Inspector(.tres) 또는 JSON({id, card_ids})로 지정.


@export var pool_id: String = ""
## 출현 후보 CardData.id 목록. 토큰·미등록 id는 resolve 시 걸러짐.
@export var card_ids: PackedInt32Array = PackedInt32Array()


## 이 풀의 유효 card_ids를 Array[int]로 반환한다 (복사).
func to_id_array() -> Array[int]:
	var out: Array[int] = []
	for raw in card_ids:
		var id := int(raw)
		if id > 0:
			out.append(id)
	return out


## JSON 문자열 → ShopCardPool. 실패 시 null. 키: id(optional), card_ids(array).
static func from_json_text(text: String) -> ShopCardPool:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parsed
	var pool := ShopCardPool.new()
	pool.pool_id = String(data.get("id", "")).strip_edges()
	var ids: PackedInt32Array = PackedInt32Array()
	var raw_ids: Variant = data.get("card_ids", [])
	if raw_ids is PackedInt32Array:
		ids = raw_ids as PackedInt32Array
	elif raw_ids is Array:
		for item in raw_ids as Array:
			var id := int(item)
			if id > 0:
				ids.append(id)
	pool.card_ids = ids
	return pool


## res:// 또는 user:// JSON 경로를 읽어 ShopCardPool을 만든다. 실패 시 null.
static func load_json_path(path: String) -> ShopCardPool:
	var p := path.strip_edges()
	if p.is_empty():
		return null
	if not FileAccess.file_exists(p):
		push_warning("ShopCardPool: missing json '%s'" % p)
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		push_warning("ShopCardPool: cannot open '%s'" % p)
		return null
	var pool := from_json_text(f.get_as_text())
	if pool == null:
		push_warning("ShopCardPool: invalid json '%s'" % p)
	return pool
