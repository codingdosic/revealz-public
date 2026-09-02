class_name WalletStore
extends RefCounted
## 프로필 wallet.json — 골드 잔액. 파일 없으면 SEED_GOLD 지급 후 저장.
## MetaSync: 로컬=캐시 · save 시 스냅샷 PUT. 구매 서버 TX는 후속.


const WALLET_REL := "wallet.json"
const SEED_GOLD := 100000000

## 메모리 잔액. ensure_loaded 전엔 의미 없음.
static var _gold: int = 0
static var _loaded_account: String = ""


## wallet.json 절대 경로. 프로필 없으면 "".
static func wallet_path() -> String:
	return AccountService.profile_path(WALLET_REL)


## 현재 계정 지갑을 메모리에 올린다. 파일 없으면 시드 후 저장.
static func ensure_loaded() -> void:
	if not AccountService.is_bootstrapped():
		_gold = 0
		_loaded_account = ""
		return
	var key := AccountService.current_id()
	if key == _loaded_account:
		return
	_loaded_account = key
	_gold = 0
	var path := wallet_path()
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		var data := _read_json_dict(path)
		_gold = maxi(0, int(data.get("gold", 0)))
	else:
		_gold = SEED_GOLD
		save()


## 디스크에서 다시 읽는다(테스트·계정 전환용).
static func reload() -> void:
	_loaded_account = ""
	_gold = 0
	ensure_loaded()


## 메모리 잔액을 wallet.json에 쓴다. 성공 시 true. Meta 사용 중이면 스냅샷 PUT도 시도.
static func save() -> bool:
	var path := wallet_path()
	if path.is_empty():
		return false
	if not _write_json(path, {"gold": _gold}):
		return false
	_push_meta_if_needed()
	return true


## 서버 골드로 메모리·캐시 교체 (MetaSync 전용 · 재푸시 없음).
static func apply_remote_gold(gold: int) -> void:
	_gold = maxi(0, gold)
	_loaded_account = AccountService.current_id()
	var path := wallet_path()
	if path.is_empty():
		return
	_write_json(path, {"gold": _gold})


## MetaSync 스냅샷 푸시.
static func _push_meta_if_needed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sync := tree.root.get_node_or_null("/root/MetaSync")
	if sync == null or bool(sync.get("applying_remote")):
		return
	sync.call("push_snapshot_async")


## 보유 골드.
static func get_gold() -> int:
	ensure_loaded()
	return _gold


## 골드를 더한다(비양수는 무시). 저장까지 수행.
static func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	ensure_loaded()
	_gold += amount
	save()


## amount만큼 차감 시도. 부족하면 false·변경 없음. 성공 시 저장.
static func try_spend(amount: int) -> bool:
	if amount < 0:
		return false
	ensure_loaded()
	if _gold < amount:
		return false
	_gold -= amount
	save()
	return true


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
