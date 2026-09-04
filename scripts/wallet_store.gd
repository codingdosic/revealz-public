class_name WalletStore
extends RefCounted
## 프로필 wallet.json — 골드 잔액 캐시. Meta 스냅샷/구매 TX가 권위.
## 파일 없으면 0 (로컬 시드·로컬 차감/지급 API 없음).


const WALLET_REL := "wallet.json"

## 메모리 잔액. ensure_loaded 전엔 의미 없음.
static var _gold: int = 0
static var _loaded_account: String = ""


## wallet.json 절대 경로. 프로필 없으면 "".
static func wallet_path() -> String:
	return AccountService.profile_path(WALLET_REL)


## 현재 계정 지갑을 메모리에 올린다. 파일 없으면 0 (시드 없음).
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


## 디스크에서 다시 읽는다(테스트·계정 전환용).
static func reload() -> void:
	_loaded_account = ""
	_gold = 0
	ensure_loaded()


## 서버 골드로 메모리·캐시 교체 (MetaSync 전용 · 재푸시 없음).
static func apply_remote_gold(gold: int) -> void:
	_gold = maxi(0, gold)
	_loaded_account = AccountService.current_id()
	var path := wallet_path()
	if path.is_empty():
		return
	_write_json(path, {"gold": _gold})


## 보유 골드.
static func get_gold() -> int:
	ensure_loaded()
	return _gold


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
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true
