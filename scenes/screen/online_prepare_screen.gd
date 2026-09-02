extends Control
## 온라인 준비 (G4c/G4d + G4e-UX). Create/Join/Random · 로비 HTTP → join_game(host,port).
## 대기/로딩은 LoadingGate 오버레이. G3b: INTENT_DECK.
## Deck 셀 → deck_select(Select·SLOT_ONLINE). playable만 Create/Join/Random 활성.
## 기본 표시=builtin_black · 이후 last_deck_id. 룩: UiChromeStyle.


const DEFAULT_LOBBY_BASE_URL := "http://127.0.0.1:8080"
const MAIN_SCENE := "res://scenes/main/main.tscn"
const PREPARE_SCENE := "res://scenes/screen/online_prepare_screen.tscn"
const DEFAULT_DECK_ID := "builtin_black"
const LOADING_GATE_SCENE := preload("res://scenes/ui/loading_gate.tscn")
## 매칭 티켓 폴링 간격 (로비 MATCH_TIMEOUT_MS≈60s와 별개).
const MATCH_POLL_SEC := 1.0
## Create 후 상대/시작 대기: 취소 버튼 비활성 고정 (추후 true로 변경 가능).
const CREATE_WAIT_CANCEL_ENABLED := true

@export var chrome_style: UiChromeStyle

@onready var _room_code_edit: LineEdit = $CenterContainer/VBoxContainer/RoomCodeSection/RoomCodeRow/LineEdit
@onready var _status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var _deck_cell: DeckSelectCell = $CenterContainer/VBoxContainer/DeckSection/VBox/DeckCell
@onready var _create_button: Button = $CenterContainer/VBoxContainer/CreateRoomButton
@onready var _join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var _random_button: Button = $CenterContainer/VBoxContainer/RandomButton
@onready var _title_label: Label = $CenterContainer/VBoxContainer/HeaderSection/VBox/TitleLabel
@onready var _hint_label: Label = $CenterContainer/VBoxContainer/HeaderSection/VBox/HintLabel


var _http: HTTPRequest
## "create" | "create_join" | "join" | "enqueue" | "ticket" | "cancel" | ""
var _lobby_pending: String = ""
var _last_room_code: String = ""
var _match_ticket_id: String = ""
var _match_poll_timer: Timer
var _gate: LoadingGate
var _gate_popup: PopupShell
## Create 플로우로 들어온 뒤 상대/시작 대기 중이면 true (취소 정책용).
var _waiting_as_creator: bool = false
## StatusLabel이 덱 진입 불가 사유를 보여 주는 중이면 true (로비 문구와 구분).
var _status_is_deck_gate: bool = false
var _deck_id: String = DEFAULT_DECK_ID


## 시그널·덱 셀·HTTPRequest·매칭 폴링·LoadingGate · 크롬.
func _ready() -> void:
	_apply_ui_chrome()
	ScreenRmbBack.install(self, _on_back_button_pressed)
	_gate = LOADING_GATE_SCENE.instantiate() as LoadingGate
	add_child(_gate)
	if _gate.has_method("apply_chrome"):
		_gate.call("apply_chrome", chrome_style)
	_gate.cancel_pressed.connect(_on_loading_gate_cancel_pressed)
	_gate_popup = preload("res://scenes/ui/shell/popup_shell.tscn").instantiate() as PopupShell
	add_child(_gate_popup)
	if _gate_popup.has_method("apply_chrome"):
		_gate_popup.call("apply_chrome", chrome_style)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.peer_joined.connect(_on_peer_joined)
	_deck_id = _resolve_deck_id()
	if _deck_cell:
		_deck_cell.cell_pressed.connect(_on_deck_cell_pressed)
		_deck_cell.apply_chrome(chrome_style)
		_bind_deck_cell(_deck_cell, _deck_id)
	_refresh_match_buttons()
	var pending_msg := GameSession.take_pending_lobby_message()
	if not pending_msg.is_empty():
		_set_idle_status(pending_msg)
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_lobby_http_completed)
	_match_poll_timer = Timer.new()
	_match_poll_timer.wait_time = MATCH_POLL_SEC
	_match_poll_timer.one_shot = false
	add_child(_match_poll_timer)
	_match_poll_timer.timeout.connect(_on_match_poll_timeout)
	MetaSync.retain_online_watch()
	if not MetaSync.online_gate_changed.is_connected(_on_online_gate_changed):
		MetaSync.online_gate_changed.connect(_on_online_gate_changed)
	_apply_online_gate_ui(false)


func _exit_tree() -> void:
	MetaSync.release_online_watch()
	if MetaSync.online_gate_changed.is_connected(_on_online_gate_changed):
		MetaSync.online_gate_changed.disconnect(_on_online_gate_changed)


## 점검/서버오류 전환 시 매치 버튼 잠금 · 팝업.
func _on_online_gate_changed() -> void:
	_apply_online_gate_ui(true)


## 게이트에 맞춰 Create/Join/Random 잠금.
func _apply_online_gate_ui(announce: bool) -> void:
	_refresh_match_buttons()
	if not announce:
		return
	if MetaSync.can_use_online():
		return
	_show_gate_popup(MetaSync.block_message)


## 온라인 게이트 차단 팝업.
func _show_gate_popup(message: String) -> void:
	if _gate_popup == null:
		return
	var copy := chrome_style.get_copy()
	var title := "점검 중" if MetaSync.block_kind == "maintenance" else "서버 오류"
	var body := message
	if body.is_empty():
		body = "서버 오류"
	_gate_popup.configure_confirm(
		title,
		body,
		Callable(),
		Callable(),
		copy.confirm,
		copy.cancel,
		{"confirm_only": true, "full_dimmer": true}
	)
	_gate_popup.open()


## 스택에서 다시 보일 때 last_deck을 셀에 반영한다.
func on_menu_shown() -> void:
	_deck_id = _resolve_deck_id()
	_bind_deck_cell(_deck_cell, _deck_id)
	_refresh_match_buttons()
	_apply_online_gate_ui(false)


## 버튼·라벨·입력에 Cyan 크롬을 입힌다 (레이아웃 유지).
func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)
	if _title_label:
		chrome_style.apply_title_label(_title_label)
	if _hint_label:
		chrome_style.apply_muted_label(_hint_label)
	if _status_label:
		chrome_style.apply_muted_label(_status_label)


## ProjectSettings revealz/lobby_base_url (없으면 로컬 기본).
func _lobby_base_url() -> String:
	var url := DEFAULT_LOBBY_BASE_URL
	if ProjectSettings.has_setting("revealz/lobby_base_url"):
		url = String(ProjectSettings.get_setting("revealz/lobby_base_url"))
	return url.strip_edges().trim_suffix("/")


## last id가 유효하면 사용, 아니면 builtin_black.
func _resolve_deck_id() -> String:
	var id := AppSettings.get_last_deck_id(AppSettings.KEY_LAST_DECK_ONLINE).strip_edges()
	if id.is_empty():
		return DEFAULT_DECK_ID
	var deck := DeckStore.load_deck(id)
	if deck.is_empty():
		return DEFAULT_DECK_ID
	return id


## 셀에 덱 이름·id를 표시한다.
func _bind_deck_cell(cell: DeckSelectCell, deck_id: String) -> void:
	if cell == null:
		return
	var deck := DeckStore.load_deck(deck_id)
	var id := deck_id
	var display_name := deck_id
	if not deck.is_empty():
		id = String(deck.get("id", deck_id))
		display_name = String(deck.get("name", id))
	cell.bind(id, display_name)


## Deck 셀 → deck_select (Select가 온라인 슬롯에 반영).
func _on_deck_cell_pressed(_cell: DeckSelectCell) -> void:
	DeckSelectScreen.open(get_tree(), PREPARE_SCENE, DeckSelectScreen.SLOT_ONLINE)


## 선택 덱이 playable이고 서버 게이트 OK일 때만 매치 진입 버튼 활성.
func _refresh_match_buttons() -> void:
	var playable := _selected_deck_playable() and MetaSync.can_use_online()
	if _create_button:
		_create_button.disabled = not playable
	if _join_button:
		_join_button.disabled = not playable
	if _random_button:
		_random_button.disabled = not playable
	_update_deck_gate_status(_selected_deck_playable())


## 진입 불가 시에만 덱 사유를 StatusLabel에 표시. 정상이면 덱 게이트 문구만 비운다.
func _update_deck_gate_status(playable: bool) -> void:
	if _status_label == null:
		return
	if playable:
		if _status_is_deck_gate:
			_status_label.text = ""
			_status_label.visible = false
			_status_is_deck_gate = false
		return
	var reason := DeckStore.describe_play_block_ko(_selected_deck_id())
	_status_label.text = reason
	_status_label.visible = not reason.is_empty()
	_status_is_deck_gate = true


## 로비/게이트용 StatusLabel 문구. 덱 게이트 플래그를 해제한다.
func _set_lobby_status(message: String) -> void:
	_status_is_deck_gate = false
	if _status_label:
		_status_label.text = message
		_status_label.visible = not message.is_empty()


## 대기 종료 후 안내. 덱이 불가하면 진입 사유로 덮어쓴다.
func _set_idle_status(message: String) -> void:
	_set_lobby_status(message)
	_update_deck_gate_status(_selected_deck_playable())


## 현재 선택 덱 id.
func _selected_deck_id() -> String:
	return _deck_id


## 현재 선택 덱이 매치 가능하면 true.
func _selected_deck_playable() -> bool:
	return DeckStore.is_playable_id(_selected_deck_id())


## 선택 덱의 card_names·rarities. 실패 시 흑 기본.
func _selected_deck() -> Dictionary:
	var id := _selected_deck_id()
	if id.is_empty():
		var fallback := CardRegistry.build_deck_for_color(CardRegistry.DeckColor.BLACK)
		return {"names": fallback, "rarities": [] as Array[int]}
	var names := DeckStore.card_names_of(id)
	if names.is_empty():
		var fallback := CardRegistry.build_deck_for_color(CardRegistry.DeckColor.BLACK)
		return {"names": fallback, "rarities": [] as Array[int]}
	return {"names": names, "rarities": DeckStore.card_rarities_of(id)}


## 선택 덱의 card_ids. 실패 시 흑 기본 ids.
func _selected_deck_ids() -> Array[int]:
	var id := _selected_deck_id()
	if id.is_empty():
		return CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
	var ids := DeckStore.card_ids_of(id)
	if ids.is_empty():
		return CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
	return ids


## 선택 덱의 card_names. 실패 시 흑 기본.
func _selected_deck_names() -> Array[String]:
	return _selected_deck()["names"]


## 로비 오류 키/HTTP 결과를 사용자 문구로 바꾼다.
func _lobby_error_message(err_key: String, response_code: int = 0) -> String:
	match err_key:
		"room_not_found":
			return "방이 없거나 이미 종료된 코드입니다."
		"room_full":
			return "방이 가득 찼습니다 (최대 2명)."
		"no_free_ports":
			return "지금은 방을 만들 수 없습니다. 잠시 후 다시 시도하세요."
		"spawn_failed":
			return "게임 서버를 시작하지 못했습니다. 로비/워커 설정을 확인하세요."
		"match_timeout", "expired":
			return "매칭 시간이 초과되었습니다. 다시 Random을 눌러 주세요."
		"ticket_not_found":
			return "매칭 대기 정보가 없습니다. 다시 Random을 눌러 주세요."
		_:
			if response_code == 404:
				return "방이 없거나 이미 종료된 코드입니다."
			if response_code == 409:
				return "방이 가득 찼습니다 (최대 2명)."
			if not err_key.is_empty():
				return "로비 오류: %s" % err_key
			return "로비 요청에 실패했습니다."


## HTTPRequest 실패 원인을 안내 문구로 만든다.
func _lobby_unreachable_message(result: int) -> String:
	# RESULT_CANT_CONNECT=2, RESULT_TIMEOUT=1 — 로비 미기동이 가장 흔함.
	if (
		result == HTTPRequest.RESULT_CANT_CONNECT
		or result == HTTPRequest.RESULT_TIMEOUT
		or result == HTTPRequest.RESULT_CONNECTION_ERROR
	):
		return "로비에 연결할 수 없습니다. 로비가 켜져 있는지 확인하세요."
	return "로비 연결 실패. 잠시 후 다시 시도하세요."


## LoadingGate 표시. StatusLabel도 같은 문구로 맞춤.
func _show_gate(
	message: String,
	cancel_visible: bool = false,
	cancel_enabled: bool = false
) -> void:
	_set_lobby_status(message)
	if _gate:
		_gate.show_gate(message, cancel_visible, cancel_enabled)


## LoadingGate 숨김.
func _hide_gate() -> void:
	if _gate:
		_gate.hide_gate()


## 매칭 폴링·Random 버튼 잠금. 게이트 문구는 호출 측에서 지정.
func _set_matchmaking_polling(active: bool) -> void:
	if active:
		_random_button.disabled = true
		if _match_poll_timer.is_stopped():
			_match_poll_timer.start()
	else:
		_match_poll_timer.stop()
		_refresh_match_buttons()


## 티켓 상태를 버리고 대기 UI를 종료한다.
func _clear_match_ticket() -> void:
	_match_ticket_id = ""
	_set_matchmaking_polling(false)
	_hide_gate()


## 게이트 취소 → Random 큐 취소, 또는 방/접속 대기 중이면 연결 해제.
func _on_loading_gate_cancel_pressed() -> void:
	if not _match_ticket_id.is_empty():
		_request_cancel_matchmaking()
		return
	if NetworkManager.is_online():
		NetworkManager.disconnect_game()
	GameSession.clear()
	_waiting_as_creator = false
	_lobby_pending = ""
	_hide_gate()
	_set_idle_status("대기를 취소했습니다.")
	_refresh_match_buttons()


## 로비 POST /v1/rooms 후 같은 코드로 /join → host/port ENet.
## 왜 create 직후 /join: 로비 좌석·TTL(빈 방)과 정원을 맞추기 위함.
func _on_create_room_button_pressed() -> void:
	await MetaSync.refresh_async(false, true)
	_refresh_match_buttons()
	if not MetaSync.can_use_online():
		_show_gate_popup(MetaSync.block_message)
		return
	if not _selected_deck_playable():
		return
	if _lobby_pending != "" or not _match_ticket_id.is_empty():
		return
	_waiting_as_creator = true
	_lobby_pending = "create"
	_show_gate("방 생성 중…", false, false)
	var err := _http.request(
		"%s/v1/rooms" % _lobby_base_url(),
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		"{}"
	)
	if err != OK:
		_lobby_pending = ""
		_waiting_as_creator = false
		_hide_gate()
		_set_idle_status("로비 요청을 시작할 수 없습니다.")


## 로비 POST /v1/rooms/{code}/join → host/port Join.
func _on_join_lobby_button_pressed() -> void:
	await MetaSync.refresh_async(false, true)
	_refresh_match_buttons()
	if not MetaSync.can_use_online():
		_show_gate_popup(MetaSync.block_message)
		return
	if not _selected_deck_playable():
		return
	if _lobby_pending != "" or not _match_ticket_id.is_empty():
		return
	var code := _room_code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		_set_lobby_status("방 코드를 입력하세요.")
		return
	_waiting_as_creator = false
	_lobby_pending = "join"
	_show_gate("코드 %s 로 참가 중…" % code, false, false)
	var path := "%s/v1/rooms/%s/join" % [_lobby_base_url(), code.uri_encode()]
	var err := _http.request(
		path,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		"{}"
	)
	if err != OK:
		_lobby_pending = ""
		_hide_gate()
		_set_idle_status("로비 요청을 시작할 수 없습니다.")


## 로비 POST /v1/matchmaking/enqueue — 큐 대기 또는 즉시 매칭.
func _on_random_button_pressed() -> void:
	await MetaSync.refresh_async(false, true)
	_refresh_match_buttons()
	if not MetaSync.can_use_online():
		_show_gate_popup(MetaSync.block_message)
		return
	if not _selected_deck_playable():
		return
	if _lobby_pending != "" or not _match_ticket_id.is_empty():
		return
	_waiting_as_creator = false
	_lobby_pending = "enqueue"
	_show_gate("랜덤 매칭 중…", false, false)
	var err := _http.request(
		"%s/v1/matchmaking/enqueue" % _lobby_base_url(),
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		"{}"
	)
	if err != OK:
		_lobby_pending = ""
		_hide_gate()
		_set_idle_status("로비 요청을 시작할 수 없습니다.")


## 매칭 대기 취소 — POST /v1/matchmaking/cancel.
func _request_cancel_matchmaking() -> void:
	if _match_ticket_id.is_empty():
		return
	if _lobby_pending == "enqueue" or _lobby_pending == "ticket":
		_http.cancel_request()
	_lobby_pending = "cancel"
	_show_gate("매칭 취소 중…", false, false)
	_match_poll_timer.stop()
	var body := JSON.stringify({"ticketId": _match_ticket_id})
	var err := _http.request(
		"%s/v1/matchmaking/cancel" % _lobby_base_url(),
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_lobby_pending = ""
		_clear_match_ticket()
		_set_idle_status("매칭 취소 요청에 실패했습니다.")


## 대기 중이면 GET /v1/matchmaking/tickets/{id}로 상태를 갱신한다.
func _on_match_poll_timeout() -> void:
	if _match_ticket_id.is_empty():
		_match_poll_timer.stop()
		return
	if _lobby_pending != "":
		return
	_lobby_pending = "ticket"
	var path := (
		"%s/v1/matchmaking/tickets/%s" % [_lobby_base_url(), _match_ticket_id.uri_encode()]
	)
	var err := _http.request(path, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		_lobby_pending = ""
		# 다음 틱에 재시도


## enqueue/ticket 응답에서 matched면 접속, queued면 대기 UI 유지.
func _handle_matchmaking_response(dict: Dictionary, response_code: int) -> void:
	var status := String(dict.get("status", ""))
	var ticket_id := String(dict.get("ticketId", "")).strip_edges()
	if not ticket_id.is_empty():
		_match_ticket_id = ticket_id
	match status:
		"matched":
			_match_poll_timer.stop()
			_match_ticket_id = ""
			_set_matchmaking_polling(false)
			var host := String(dict.get("host", "")).strip_edges()
			var port := int(dict.get("port", 0))
			var room_code := String(dict.get("roomCode", "")).strip_edges()
			if host.is_empty() or port <= 0 or room_code.is_empty():
				_hide_gate()
				_set_idle_status("매칭 응답이 올바르지 않습니다.")
				return
			_room_code_edit.text = room_code
			_last_room_code = room_code
			_show_gate("매칭됨 — 접속 중…", false, false)
			_connect_via_lobby(host, port, room_code)
		"queued":
			_set_matchmaking_polling(true)
			_show_gate("상대를 찾는 중…", true, true)
		"expired":
			_clear_match_ticket()
			_set_idle_status(_lobby_error_message("expired", response_code))
		"cancelled":
			_clear_match_ticket()
			_set_idle_status("매칭을 취소했습니다.")
		"error":
			_clear_match_ticket()
			var err_key := String(dict.get("error", "spawn_failed"))
			_set_idle_status(_lobby_error_message(err_key, response_code))
		_:
			_clear_match_ticket()
			_set_idle_status("알 수 없는 매칭 상태입니다.")


## 로비 HTTP 완료 → create면 /join 연쇄, matchmaking이면 티켓 처리, 아니면 join_game.
func _on_lobby_http_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var pending := _lobby_pending
	if pending.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_lobby_pending = ""
		if pending == "cancel":
			_clear_match_ticket()
			_set_idle_status("매칭을 취소했습니다. (로비 응답 없음)")
			return
		if pending == "enqueue" or pending == "ticket":
			_clear_match_ticket()
		elif pending == "create" or pending == "create_join" or pending == "join":
			_waiting_as_creator = false
			_hide_gate()
		_set_idle_status(_lobby_unreachable_message(result))
		return
	var text := body.get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_lobby_pending = ""
		if pending == "enqueue" or pending == "ticket" or pending == "cancel":
			_clear_match_ticket()
		elif pending == "create" or pending == "create_join" or pending == "join":
			_waiting_as_creator = false
			_hide_gate()
		_set_idle_status("로비 응답을 읽지 못했습니다.")
		return
	var dict: Dictionary = data
	_lobby_pending = ""

	if pending == "cancel":
		_clear_match_ticket()
		_set_idle_status("매칭을 취소했습니다.")
		return

	if pending == "enqueue" or pending == "ticket":
		if response_code < 200 or response_code >= 300:
			var mm_err := String(dict.get("error", ""))
			_clear_match_ticket()
			_set_idle_status(_lobby_error_message(mm_err, response_code))
			return
		_handle_matchmaking_response(dict, response_code)
		return

	if response_code < 200 or response_code >= 300:
		_waiting_as_creator = false
		_hide_gate()
		var err_key := String(dict.get("error", ""))
		_set_idle_status(_lobby_error_message(err_key, response_code))
		return
	var host := String(dict.get("host", "")).strip_edges()
	var port := int(dict.get("port", 0))
	var room_code := String(dict.get("roomCode", "")).strip_edges()
	if host.is_empty() or port <= 0 or room_code.is_empty():
		_waiting_as_creator = false
		_hide_gate()
		_set_idle_status("로비 응답이 올바르지 않습니다.")
		return
	_room_code_edit.text = room_code
	_last_room_code = room_code
	if pending == "create":
		_lobby_pending = "create_join"
		_show_gate(
			"방 코드: %s — 상대에게 공유하세요…" % room_code,
			true,
			CREATE_WAIT_CANCEL_ENABLED
		)
		var path := "%s/v1/rooms/%s/join" % [_lobby_base_url(), room_code.uri_encode()]
		var err := _http.request(
			path,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			"{}"
		)
		if err != OK:
			_lobby_pending = ""
			_waiting_as_creator = false
			_hide_gate()
			_set_idle_status("방 코드: %s — 참가 요청에 실패했습니다." % room_code)
		return
	_connect_via_lobby(host, port, room_code)


## 로비 발급 host/port로 클라 접속. 상태에는 코드만 강조한다.
func _connect_via_lobby(host: String, port: int, room_code: String) -> void:
	var deck := _selected_deck()
	var ids := _selected_deck_ids()
	GameSession.start_client(ids, deck["rarities"], _selected_deck_id())
	var err := NetworkManager.join_game(host, port, room_code)
	if err != OK:
		_waiting_as_creator = false
		_hide_gate()
		_set_idle_status("게임 서버 접속에 실패했습니다.")
		GameSession.clear()
		return
	_show_gate(
		"방 코드: %s — 접속 중…" % room_code,
		true,
		CREATE_WAIT_CANCEL_ENABLED
	)


## 메인으로. 매칭 중이면 취소 시도 후 접속 종료.
func _on_back_button_pressed() -> void:
	if not _match_ticket_id.is_empty():
		_request_cancel_matchmaking()
	if NetworkManager.is_online():
		NetworkManager.disconnect_game()
	GameSession.clear()
	_waiting_as_creator = false
	_hide_gate()
	MenuHost.pop_or_file(MAIN_SCENE)


## 연결 성공 시 INTENT_DECK(cardIds+cardNames 듀얼라이트)를 권위에 보낸다 (G3b + IdKey Phase 2).
func _on_connected_to_server() -> void:
	var code := _last_room_code if not _last_room_code.is_empty() else NetworkManager.room_code
	if _waiting_as_creator:
		var msg := (
			"방 코드: %s — 상대/시작 대기…" % code
			if not code.is_empty()
			else "상대/시작 대기…"
		)
		_show_gate(msg, true, CREATE_WAIT_CANCEL_ENABLED)
	elif code.is_empty():
		_show_gate("서버 연결됨. 게임 시작 대기…", true, CREATE_WAIT_CANCEL_ENABLED)
	else:
		_show_gate(
			"방 코드: %s — 연결됨. 상대/시작 대기…" % code,
			true,
			CREATE_WAIT_CANCEL_ENABLED
		)
	var session := GameSession.get_active()
	if session is ClientGameSession:
		var client := session as ClientGameSession
		client.sync_local_card_back()
		client.sync_local_field()
		client.sync_local_profile_icon()
		var rarity_wire: Array = []
		for r in client.get_deck_rarities():
			rarity_wire.append(int(r))
		var id_wire: Array = []
		for v in client.get_deck_ids():
			id_wire.append(int(v))
		NetworkManager.rpc_submit_intent.rpc_id(
			1,
			{
				"type": NetworkConstants.INTENT_DECK,
				"cardIds": id_wire,
				"cardNames": client.get_deck_names(),
				"cardRarities": rarity_wire,
				"displayName": AccountService.display_name() if AccountService.is_bootstrapped() else "",
				"profileIconId": client.local_profile_icon_id,
				"cardBackId": client.local_card_back_id,
				"fieldId": client.local_field_id,
				"accountKey": AccountService.current_id() if AccountService.is_bootstrapped() else "",
			}
		)


## 연결 실패 정리.
func _on_connection_failed() -> void:
	_waiting_as_creator = false
	_hide_gate()
	_set_idle_status("게임 서버 연결에 실패했습니다. 잠시 후 Join을 다시 시도하세요.")
	GameSession.clear()


## Host 측: 상대 접속 알림.
func _on_peer_joined(_peer_id: int) -> void:
	_show_gate("상대 접속. 게임 시작…", false, false)
