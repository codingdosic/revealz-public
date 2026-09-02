class_name MetaRemote
extends RefCounted
## Lobby MetaSrv HTTP 헬퍼. HTTPRequest 노드는 호출측이 소유한다.
## Dedicated는 META_LOBBY_URL env 우선(같은 VM localhost).


## Lobby base URL. META_LOBBY_URL → ProjectSettings → 127.0.0.1:8080.
static func lobby_base_url() -> String:
	var env_url := OS.get_environment("META_LOBBY_URL").strip_edges()
	if not env_url.is_empty():
		return env_url.trim_suffix("/")
	var url := "http://127.0.0.1:8080"
	if ProjectSettings.has_setting("revealz/lobby_base_url"):
		url = String(ProjectSettings.get_setting("revealz/lobby_base_url"))
	return url.strip_edges().trim_suffix("/")


## 계정 메타 URL.
static func account_url(account_key: String) -> String:
	return "%s/v1/meta/accounts/%s" % [lobby_base_url(), account_key.uri_encode()]


## 구매 API URL.
static func purchase_url(account_key: String) -> String:
	return "%s/purchase" % account_url(account_key)


## 덱 검증 API URL (G3.1).
static func validate_deck_url(account_key: String) -> String:
	return "%s/validate-deck" % account_url(account_key)


## 패치노트 목록 URL.
static func patch_notes_url() -> String:
	return "%s/v1/patch-notes" % lobby_base_url()


## 패치노트 단건 URL.
static func patch_note_url(note_id: int) -> String:
	return "%s/%d" % [patch_notes_url(), note_id]


## GET 스냅샷. 반환: { ok, status, data, error }.
static func get_snapshot(http: HTTPRequest, account_key: String) -> Dictionary:
	return await _request(http, HTTPClient.METHOD_GET, account_url(account_key), {})


## 스냅샷 업서트 (POST).
static func put_snapshot(http: HTTPRequest, account_key: String, body: Dictionary) -> Dictionary:
	return await _request(http, HTTPClient.METHOD_POST, account_url(account_key), body)


## 팩 구매 서버 트랜잭션.
static func purchase(http: HTTPRequest, account_key: String, body: Dictionary) -> Dictionary:
	return await _request(http, HTTPClient.METHOD_POST, purchase_url(account_key), body)


## 덱⊆owned 검증 (G3.1). body: card_ids, card_rarities.
static func validate_deck(http: HTTPRequest, account_key: String, body: Dictionary) -> Dictionary:
	return await _request(http, HTTPClient.METHOD_POST, validate_deck_url(account_key), body)


## GET /v1/patch-notes. 반환: { ok, status, data, error }.
static func get_patch_notes(http: HTTPRequest) -> Dictionary:
	return await _request(http, HTTPClient.METHOD_GET, patch_notes_url(), {})


## GET /v1/patch-notes/{id}.
static func get_patch_note(http: HTTPRequest, note_id: int) -> Dictionary:
	return await _request(http, HTTPClient.METHOD_GET, patch_note_url(note_id), {})


## 로비 health URL.
static func health_url() -> String:
	return "%s/v1/health" % lobby_base_url()


## GET /v1/health. 반환: { ok, status, data, error }.
static func get_health(http: HTTPRequest) -> Dictionary:
	return await _request(http, HTTPClient.METHOD_GET, health_url(), {})


## HTTPRequest 1회 수행. JSON body는 POST/PUT일 때 전송.
static func _request(http: HTTPRequest, method: int, url: String, body: Dictionary) -> Dictionary:
	if http == null:
		return {"ok": false, "status": 0, "data": {}, "error": "no_http"}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload := ""
	if method == HTTPClient.METHOD_PUT or method == HTTPClient.METHOD_POST:
		payload = JSON.stringify(body)
	var err := http.request(url, headers, method, payload)
	if err != OK:
		return {"ok": false, "status": 0, "data": {}, "error": "request_failed:%s" % error_string(err)}
	var result: Array = await http.request_completed
	var http_result: int = int(result[0])
	var status: int = int(result[1])
	var raw: PackedByteArray = result[3]
	if http_result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"status": status,
			"data": {},
			"error": "http_result:%d" % http_result,
		}
	var text := raw.get_string_from_utf8()
	var parsed: Variant = {}
	if not text.is_empty():
		parsed = JSON.parse_string(text)
	var data: Dictionary = parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data, "error": ""}
	var err_code := String(data.get("error", "status_%d" % status))
	return {
		"ok": false,
		"status": status,
		"data": data,
		"error": err_code,
	}
