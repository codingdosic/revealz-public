extends Node
## Autoload MetaSync — Acc0 부팅 후 health 게이트 · 메타 GET/신규 빈 계정 · Store 저장 시 스냅샷 푸시.
## 서버 권위: Meta 동기화 실패·점검·health 실패 시 싱글·온라인·상점·덱 진입 불가 (오프라인 폴백 없음).
## 로컬 파일은 캐시. 서버 meta_revision 낙관적 잠금.
## UX: 부팅·신규 계정·진입 재점검만 LoadingGate (취소 없음). 상점/온라인은 watch로 점검 전환 감지.


signal sync_finished(ok: bool, message: String)
signal push_failed(message: String)
## online_blocked / block_kind 변경 시 (상점·온라인 조작 차단용).
signal online_gate_changed()

const LOADING_GATE_SCENE := preload("res://scenes/ui/loading_gate.tscn")
const WATCH_SEC := 12.0

## true면 원격 적용 중 — Store.save가 재푸시하지 않음.
var applying_remote: bool = false
## 부팅 동기 성공·로컬 캐시 확정 후 true.
var boot_done: bool = false
## 로비 Meta API 사용 가능(최근 GET/PUT 성공 또는 404 이관 경로).
var meta_available: bool = false
## health 실패 또는 maintenance — 온라인 진입 불가.
var online_blocked: bool = false
## server_error | maintenance | ""
var block_kind: String = ""
## 팝업에 쓸 문구.
var block_message: String = ""
## 최근 health 성공 시 lobby version.json 의 lobby 문자열. 연결 실패 시에도 이전 값 유지.
var lobby_version: String = ""
## 서버 스냅샷 revision. PUT 시 baseRevision으로 보냄.
var meta_revision: int = 0
## 선물함 pending 수 (스냅샷 mailboxPendingCount).
var mailbox_pending_count: int = 0
## 동기/푸시 진행 중.
var _busy: bool = false
## 푸시 중 추가 저장이 있으면 한 번 더 PUT.
var _push_dirty: bool = false
var _http: HTTPRequest
var _gate: LoadingGate
var _watch_refs: int = 0
var _watch_timer: Timer


## HTTPRequest 준비 후 부팅 동기(계정 bootstrap 이후).
func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	if not AccountService.is_bootstrapped():
		boot_done = true
		return
	call_deferred("sync_boot")


## 부팅: health → GET 스냅샷 / 404 빈 계정 생성 / 실패 시 로컬 캐시(온라인인 척하지 않음).
func sync_boot() -> void:
	if _busy:
		return
	_busy = true
	_show_gate("서버 상태 확인 중…")
	var health: Dictionary = await MetaRemote.get_health(_http)
	if not bool(health.get("ok", false)):
		_block_and_cache("server_error", "서버 오류 (연결 실패)")
		return
	var health_data: Dictionary = {}
	if typeof(health.get("data", {})) == TYPE_DICTIONARY:
		health_data = health.get("data", {}) as Dictionary
	_remember_lobby_version(health_data)
	if bool(health_data.get("maintenance", false)):
		var mmsg := String(health_data.get("maintenanceMessage", "")).strip_edges()
		if mmsg.is_empty():
			mmsg = "점검 중"
		else:
			mmsg = "점검 중\n%s" % mmsg
		_block_and_cache("maintenance", mmsg)
		return
	_set_block_state(false, "", "")
	_show_gate("계정 데이터 동기화 중…")
	var key := AccountService.current_id()
	var got: Dictionary = await MetaRemote.get_snapshot(_http, key)
	if bool(got.get("ok", false)):
		_apply_snapshot(got.get("data", {}) as Dictionary)
		meta_available = true
		boot_done = true
		_busy = false
		_hide_gate()
		sync_finished.emit(true, "synced")
		print("[MetaSync] boot GET ok account=%s rev=%d" % [key, meta_revision])
		return
	var status := int(got.get("status", 0))
	var get_err := String(got.get("error", ""))
	print("[MetaSync] boot GET fail status=%d error=%s url=%s" % [
		status, get_err, MetaRemote.account_url(key)
	])
	if status == 404 or get_err == "account_not_found" or get_err == "not_found":
		_show_gate("계정 생성 중…")
		var created: Dictionary = await _ensure_empty_remote_account()
		if bool(created.get("ok", false)):
			_apply_snapshot(created.get("data", {}) as Dictionary)
			meta_available = true
			boot_done = true
			_busy = false
			_hide_gate()
			sync_finished.emit(true, "created")
			print("[MetaSync] boot create empty account ok account=%s rev=%d" % [key, meta_revision])
			return
		var put_status := int(created.get("status", 0))
		var put_err := String(created.get("error", ""))
		if put_status == 410 or put_err == "account_deleted":
			_cache_without_meta("account_deleted")
			print("[MetaSync] create blocked account_deleted account=%s" % key)
			return
		print("[MetaSync] create empty account fail status=%d error=%s" % [
			put_status, put_err
		])
		_cache_without_meta("create_failed:%s" % put_err)
		return
	if status == 410 or get_err == "account_deleted":
		_cache_without_meta("account_deleted")
		print("[MetaSync] boot GET account_deleted account=%s" % key)
		return
	_cache_without_meta(String(got.get("error", "boot_get_failed")))


## 화면 진입·복귀·구매 직전 재점검. pull_meta면 GET 스냅샷 적용.
## show_loading이면 LoadingGate. 반환: health OK(차단 아님).
func refresh_async(pull_meta: bool = false, show_loading: bool = false) -> bool:
	if not AccountService.is_bootstrapped():
		return false
	while _busy:
		await get_tree().process_frame
	_busy = true
	if show_loading:
		_show_gate("서버 상태 확인 중…")
	var health: Dictionary = await MetaRemote.get_health(_http)
	if not bool(health.get("ok", false)):
		_block_and_cache("server_error", "서버 오류 (연결 실패)")
		return false
	var health_data: Dictionary = {}
	if typeof(health.get("data", {})) == TYPE_DICTIONARY:
		health_data = health.get("data", {}) as Dictionary
	_remember_lobby_version(health_data)
	if bool(health_data.get("maintenance", false)):
		var mmsg := String(health_data.get("maintenanceMessage", "")).strip_edges()
		if mmsg.is_empty():
			mmsg = "점검 중"
		else:
			mmsg = "점검 중\n%s" % mmsg
		_block_and_cache("maintenance", mmsg)
		return false
	_set_block_state(false, "", "")
	if pull_meta:
		if show_loading:
			_show_gate("계정 데이터 동기화 중…")
		var key := AccountService.current_id()
		var got: Dictionary = await MetaRemote.get_snapshot(_http, key)
		if bool(got.get("ok", false)):
			_apply_snapshot(got.get("data", {}) as Dictionary)
			meta_available = true
		else:
			var status := int(got.get("status", 0))
			var get_err := String(got.get("error", ""))
			meta_available = false
			# 재점검에서는 계정 생성하지 않음 — 부팅 경로만. Meta 없으면 전면 차단.
			var msg := "서버 오류 (계정 동기화 실패)"
			if status == 410 or get_err == "account_deleted":
				msg = "계정이 삭제되었습니다"
			_set_block_state(true, "server_error", msg)
			_busy = false
			_hide_gate()
			sync_finished.emit(false, "refresh_meta_failed")
			print("[MetaSync] refresh GET fail status=%d error=%s" % [status, get_err])
			return false
	elif not meta_available:
		# health만 OK여도 계정 메타가 없으면 플레이 불가.
		_set_block_state(true, "server_error", "서버 연결 필요 (계정 동기화)")
		_busy = false
		_hide_gate()
		sync_finished.emit(false, "meta_unavailable")
		return false
	_busy = false
	_hide_gate()
	sync_finished.emit(true, "refreshed")
	return true


## 상점/온라인 화면이 떠 있는 동안 health 폴링 유지(refcount).
func retain_online_watch() -> void:
	_watch_refs += 1
	if _watch_refs != 1:
		return
	if _watch_timer == null:
		_watch_timer = Timer.new()
		_watch_timer.wait_time = WATCH_SEC
		_watch_timer.one_shot = false
		add_child(_watch_timer)
		_watch_timer.timeout.connect(_on_watch_timeout)
	_watch_timer.start()


## retain_online_watch 쌍.
func release_online_watch() -> void:
	_watch_refs = maxi(0, _watch_refs - 1)
	if _watch_refs > 0:
		return
	if _watch_timer != null:
		_watch_timer.stop()


## 상점/온라인 상주 중 점검·서버오류 전환 감지 (게이트 UI 없음).
func _on_watch_timeout() -> void:
	if _busy or not AccountService.is_bootstrapped():
		return
	await refresh_async(false, false)


## Store 변경 후 프로필·덱 스냅샷 PUT (gold/owned는 서버 TX만). meta 불가면 true.
func push_snapshot_async() -> bool:
	if applying_remote or not meta_available:
		return true
	if not AccountService.is_bootstrapped():
		return false
	if _busy:
		_push_dirty = true
		return true
	_busy = true
	var ok := true
	while true:
		_push_dirty = false
		var put: Dictionary = await _put_current_snapshot()
		if not bool(put.get("ok", false)):
			ok = false
			var status := int(put.get("status", 0))
			var data: Dictionary = {}
			if typeof(put.get("data", {})) == TYPE_DICTIONARY:
				data = put.get("data", {}) as Dictionary
			if status == 409:
				var snap: Dictionary = {}
				if typeof(data.get("snapshot", {})) == TYPE_DICTIONARY:
					snap = data.get("snapshot", {}) as Dictionary
				elif not data.is_empty() and data.has("owned"):
					snap = data
				if not snap.is_empty():
					_apply_snapshot(snap)
					meta_available = true
					print("[MetaSync] push revision_conflict → applied server snap rev=%d" % meta_revision)
				push_failed.emit("revision_conflict")
			elif status == 410 or String(put.get("error", "")) == "account_deleted":
				meta_available = false
				push_warning("[MetaSync] push blocked account_deleted")
				push_failed.emit("account_deleted")
			else:
				var msg := String(put.get("error", "push_failed"))
				push_warning("[MetaSync] push failed: %s" % msg)
				push_failed.emit(msg)
			break
		var put_data: Dictionary = {}
		if typeof(put.get("data", {})) == TYPE_DICTIONARY:
			put_data = put.get("data", {}) as Dictionary
		if not put_data.is_empty():
			_apply_snapshot(put_data)
		if not _push_dirty:
			break
	_busy = false
	return ok


## 동기화 중이면 대기 후 반환 (메인 골드 갱신 등).
func wait_boot_done() -> void:
	if boot_done:
		return
	await sync_finished


## 로컬 캐시를 올린다 (시드 없음).
func _ensure_local_stores() -> void:
	WalletStore.ensure_loaded()
	CollectionStore.ensure_loaded()
	AccessoryStore.ensure_loaded()
	# 덱은 파일 목록이 SSOT — ensure 불필요.


## 덱·표시 메타만 PUT (경제/보유는 서버 TX).
func _put_current_snapshot() -> Dictionary:
	_ensure_local_stores()
	var body := build_snapshot_from_local()
	var key := AccountService.current_id()
	return await MetaRemote.put_snapshot(_http, key, body)


## 신규 guest: 로컬 파일 이관 없이 서버에 빈 계정(gold 0 · owned 없음 · default 악세)만 생성.
func _ensure_empty_remote_account() -> Dictionary:
	var key := AccountService.current_id()
	var body := {
		"account": {
			"accountKey": key,
			"authKind": AccountService.current_auth_kind(),
			"displayName": AccountService.display_name(),
			"profileIconId": AccessoryCatalog.DEFAULT_ICON_ID,
		},
		"ownedAccessories": AccessoryCatalog.default_ids_payload(),
		"decks": [],
	}
	return await MetaRemote.put_snapshot(_http, key, body)


## 로컬 Store → PUT body (account + decks만). gold/owned는 포함하지 않음.
func build_snapshot_from_local() -> Dictionary:
	var decks: Array = []
	for deck in DeckStore.list_user_decks():
		var full := DeckStore.load_deck(String(deck.get("id", "")))
		if full.is_empty():
			continue
		decks.append({
			"id": String(full.get("id", "")),
			"name": String(full.get("name", "Deck")),
			"format": String(full.get("format", "mono")),
			"base_color": String(full.get("base_color", "black")),
			"card_ids": full.get("card_ids", []),
			"card_rarities": full.get("card_rarities", []),
			"accessories": DeckStore.accessories_of(full),
			"main_card": DeckStore.normalize_main_card_raw(full.get("main_card", {})),
		})
	return {
		"account": {
			"accountKey": AccountService.current_id(),
			"authKind": AccountService.current_auth_kind(),
			"displayName": AccountService.display_name(),
			"profileIconId": AccountService.profile_icon_id(),
		},
		"decks": decks,
		"baseRevision": meta_revision,
	}


## 서버 스냅샷을 로컬 캐시·메모리에 적용 (푸시 없음).
func _apply_snapshot(data: Dictionary) -> void:
	applying_remote = true
	var account: Dictionary = data.get("account", {}) as Dictionary
	if typeof(data.get("account", {})) != TYPE_DICTIONARY:
		account = {}
	var display := String(account.get("displayName", "")).strip_edges()
	if not display.is_empty() and display != AccountService.display_name():
		AccountService.apply_remote_display_name(display)
	var profile_icon := String(account.get("profileIconId", "")).strip_edges()
	if profile_icon != AccountService.profile_icon_id():
		AccountService.apply_remote_profile_icon(profile_icon)
	WalletStore.apply_remote_gold(maxi(0, int(data.get("gold", 0))))
	var owned: Dictionary = {}
	if typeof(data.get("owned", {})) == TYPE_DICTIONARY:
		owned = data.get("owned", {}) as Dictionary
	CollectionStore.apply_remote_owned(owned)
	var owned_accessories: Dictionary = {}
	if typeof(data.get("ownedAccessories", {})) == TYPE_DICTIONARY:
		owned_accessories = data.get("ownedAccessories", {}) as Dictionary
	AccessoryStore.apply_remote_owned(owned_accessories)
	var decks_raw: Array = []
	if typeof(data.get("decks", [])) == TYPE_ARRAY:
		decks_raw = data.get("decks", []) as Array
	DeckStore.apply_remote_decks(decks_raw)
	if data.has("metaRevision"):
		meta_revision = maxi(0, int(data.get("metaRevision", 0)))
	if data.has("mailboxPendingCount"):
		mailbox_pending_count = maxi(0, int(data.get("mailboxPendingCount", 0)))
	applying_remote = false


## claim 등에서 받은 서버 스냅샷을 로컬에 반영한다.
func apply_server_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		return
	_apply_snapshot(data)


## 온라인·싱글·덱 등 플레이 가능. health/점검 차단이 없고 Meta 동기화 성공이어야 함.
func can_use_online() -> bool:
	return not online_blocked and meta_available


## 상점·메타 쓰기 가능. 플레이 가능과 동일 (서버 권위 — Meta 필수).
func can_use_shop() -> bool:
	return can_use_online()


## health.data.version.lobby 를 lobby_version에 반영한다.
func _remember_lobby_version(health_data: Dictionary) -> void:
	if health_data.is_empty():
		return
	var ver: Variant = health_data.get("version", {})
	if typeof(ver) != TYPE_DICTIONARY:
		return
	var lobby := String((ver as Dictionary).get("lobby", "")).strip_edges()
	if not lobby.is_empty():
		lobby_version = lobby


## 차단 상태 갱신. 변경 시 online_gate_changed.
func _set_block_state(blocked: bool, kind: String, message: String) -> void:
	var changed := (
		online_blocked != blocked
		or block_kind != kind
		or block_message != message
	)
	online_blocked = blocked
	block_kind = kind
	block_message = message
	if changed:
		online_gate_changed.emit()


## health 실패·점검: 로컬 캐시만. 전면 차단.
func _block_and_cache(kind: String, message: String) -> void:
	_ensure_local_stores()
	meta_available = false
	_set_block_state(true, kind, message)
	boot_done = true
	_busy = false
	_hide_gate()
	sync_finished.emit(false, kind)
	print("[MetaSync] blocked kind=%s" % kind)


## 메타 API 실패 — 서버 권위 전제상 싱글·온라인·상점 모두 차단.
func _cache_without_meta(reason: String) -> void:
	var msg := "서버 연결 필요 (계정 동기화)"
	if reason == "account_deleted":
		msg = "계정이 삭제되었습니다"
	elif reason.begins_with("create_failed"):
		msg = "서버 오류 (계정 생성 실패)"
	_ensure_local_stores()
	meta_available = false
	_set_block_state(true, "server_error", msg)
	boot_done = true
	_busy = false
	_hide_gate()
	sync_finished.emit(false, reason)
	print("[MetaSync] meta unavailable reason=%s" % reason)


## 루트에 LoadingGate 표시.
func _show_gate(message: String) -> void:
	if _gate == null:
		_gate = LOADING_GATE_SCENE.instantiate() as LoadingGate
		get_tree().root.add_child(_gate)
	_gate.show_gate(message, false, false)


## LoadingGate 숨김.
func _hide_gate() -> void:
	if _gate != null:
		_gate.hide_gate()


## 서버 구매 (팩·치장). body: product_id, pack_count. 성공 시 로컬 gold/owned 반영.
## meta 불가면 {}. 실패 시 {ok:false, error}.
func purchase_product_async(body: Dictionary) -> Dictionary:
	if not meta_available or not AccountService.is_bootstrapped():
		return {}
	_show_gate("구매 처리 중…")
	var key := AccountService.current_id()
	var res: Dictionary = await MetaRemote.purchase(_http, key, body)
	_hide_gate()
	if not bool(res.get("ok", false)):
		var msg := String(res.get("error", "purchase_failed"))
		match msg:
			"insufficient_gold":
				msg = "골드가 부족합니다"
			"empty_pool":
				msg = "출현 풀이 비어 있습니다"
			"account_not_found":
				msg = "계정 데이터가 없습니다"
			"product_not_found":
				msg = "상품을 찾을 수 없습니다"
			"already_owned":
				msg = "이미 보유 중입니다"
		return {"ok": false, "error": msg, "status": int(res.get("status", 0))}
	var data: Dictionary = {}
	if typeof(res.get("data", {})) == TYPE_DICTIONARY:
		data = res.get("data", {}) as Dictionary
	applying_remote = true
	WalletStore.apply_remote_gold(maxi(0, int(data.get("gold", 0))))
	if typeof(data.get("owned", {})) == TYPE_DICTIONARY:
		CollectionStore.apply_remote_owned(data.get("owned", {}) as Dictionary)
	if typeof(data.get("ownedAccessories", {})) == TYPE_DICTIONARY:
		AccessoryStore.apply_remote_owned(data.get("ownedAccessories", {}) as Dictionary)
	if data.has("metaRevision"):
		meta_revision = maxi(0, int(data.get("metaRevision", 0)))
	applying_remote = false
	var product_type := String(data.get("product_type", ""))
	var out := {
		"ok": true,
		"error": "",
		"product_id": String(data.get("product_id", "")),
		"spent": int(data.get("spent", 0)),
		"pack_count": int(data.get("pack_count", 1)),
	}
	if product_type == "accessory" or data.has("granted_accessory_id"):
		out["granted_accessory_type"] = String(data.get("granted_accessory_type", ""))
		out["granted_accessory_id"] = String(data.get("granted_accessory_id", ""))
		print("[MetaSync] purchase accessory ok spent=%s id=%s rev=%d" % [
			str(out["spent"]), out["granted_accessory_id"], meta_revision
		])
		return out
	var granted_ids: Array = data.get("granted_card_ids", []) as Array
	var granted_rarities: Array = data.get("granted_rarities", []) as Array
	var granted_names: Array[String] = []
	CardRegistry.ensure_loaded()
	for raw_id in granted_ids:
		var card_id := int(raw_id)
		var card := CardRegistry.get_by_id(card_id)
		granted_names.append(card.card_name if card else str(card_id))
	print("[MetaSync] purchase pack ok spent=%s cards=%d rev=%d" % [
		str(data.get("spent", 0)), granted_ids.size(), meta_revision
	])
	out["granted_card_ids"] = granted_ids
	out["granted_names"] = granted_names
	out["granted_rarities"] = granted_rarities
	return out


## @deprecated use purchase_product_async
func purchase_pack_async(body: Dictionary) -> Dictionary:
	return await purchase_product_async(body)


## GET /v1/shop/catalog — 서버 가격·팩 설정을 클라 ShopProduct에 덮어쓴다.
## 성공 시 true. 실패해도 상점 UI는 열리되 구매는 Meta 게이트에 막힘.
func apply_shop_catalog_to_resource(catalog: ShopCatalog) -> bool:
	if catalog == null or not meta_available:
		return false
	var res: Dictionary = await MetaRemote.get_shop_catalog(_http)
	if not bool(res.get("ok", false)):
		print("[MetaSync] shop catalog GET fail error=%s" % String(res.get("error", "")))
		return false
	var data: Dictionary = {}
	if typeof(res.get("data", {})) == TYPE_DICTIONARY:
		data = res.get("data", {}) as Dictionary
	var products_raw: Array = data.get("products", []) as Array
	var by_id: Dictionary = {}
	for raw in products_raw:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw as Dictionary
		var pid := String(row.get("productId", row.get("product_id", ""))).strip_edges()
		if pid.is_empty():
			continue
		by_id[pid] = row
	var applied := 0
	for tab in catalog.tabs:
		if tab == null:
			continue
		for sub in tab.subcategories:
			if sub == null:
				continue
			for product in sub.products:
				if product == null:
					continue
				var id := String(product.product_id).strip_edges()
				if id.is_empty() or not by_id.has(id):
					continue
				var row: Dictionary = by_id[id] as Dictionary
				product.price_gold = maxi(0, int(row.get("priceGold", row.get("price_gold", product.price_gold))))
				if product is ShopPackProduct:
					var pack := product as ShopPackProduct
					pack.pack_size = maxi(1, int(row.get("packSize", row.get("pack_size", pack.pack_size))))
					pack.weight_n = maxi(0, int(row.get("weightN", row.get("weight_n", pack.weight_n))))
					pack.weight_r = maxi(0, int(row.get("weightR", row.get("weight_r", pack.weight_r))))
					pack.weight_sr = maxi(0, int(row.get("weightSr", row.get("weight_sr", pack.weight_sr))))
					pack.weight_ur = maxi(0, int(row.get("weightUr", row.get("weight_ur", pack.weight_ur))))
				applied += 1
	print("[MetaSync] shop catalog applied products=%d rev=%s" % [
		applied, str(data.get("revision", "?"))
	])
	return true


## 프로필(표시명·아이콘) 서버 업데이트. fields: displayName?, profileIconId?
## 성공 시 "" · 실패 시 유저용 에러 문자열. 409면 서버 스냅샷 적용.
func update_profile_async(fields: Dictionary) -> String:
	if not meta_available or not AccountService.is_bootstrapped():
		return "서버 연결이 필요합니다"
	while _busy:
		await get_tree().process_frame
	_busy = true
	var body := {
		"baseRevision": meta_revision,
	}
	if fields.has("displayName"):
		body["displayName"] = String(fields.get("displayName", ""))
	if fields.has("profileIconId"):
		body["profileIconId"] = String(fields.get("profileIconId", ""))
	_show_gate("프로필 저장 중…")
	var key := AccountService.current_id()
	var res: Dictionary = await MetaRemote.update_profile(_http, key, body)
	_hide_gate()
	if bool(res.get("ok", false)):
		var data: Dictionary = {}
		if typeof(res.get("data", {})) == TYPE_DICTIONARY:
			data = res.get("data", {}) as Dictionary
		_apply_snapshot(data)
		_busy = false
		return ""
	var status := int(res.get("status", 0))
	var err := String(res.get("error", "profile_failed"))
	if status == 409 and err == "revision_conflict":
		var data: Dictionary = {}
		if typeof(res.get("data", {})) == TYPE_DICTIONARY:
			data = res.get("data", {}) as Dictionary
		var snap: Dictionary = {}
		if typeof(data.get("snapshot", {})) == TYPE_DICTIONARY:
			snap = data.get("snapshot", {}) as Dictionary
		elif not data.is_empty():
			snap = data
		if not snap.is_empty():
			_apply_snapshot(snap)
		_busy = false
		return "다른 기기에서 변경됨 — 다시 저장하세요"
	_busy = false
	match err:
		"display_name_invalid", "display_name_too_long", "display_name_required":
			return "사용할 수 없는 ID입니다"
		"icon_not_owned":
			return "보유하지 않은 아이콘입니다"
		"account_not_found", "account_deleted":
			return "계정 데이터를 확인할 수 없습니다"
		_:
			return "프로필 저장에 실패했습니다"
