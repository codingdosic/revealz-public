extends Node
## Autoload NetworkManager — ENet host/join·RPC·peer 수명.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connection_failed()
signal connected_to_server()

var room_code: String = ""
## Actual ENet listen/connect port (lobby path may differ from room_code_to_port).
var listen_port: int = 0
## When true, listen as dedicated authority host: player disconnect must not
## tear down the server peer or jump to UI scenes (headless M0+).
var dedicated_server: bool = false


## 방 코드를 ENet listen/connect 포트로 변환한다 (개발 폴백 · code%200).
## 왜: 로비 경로에서는 쓰지 않는다 — host_game/join_game이 명시 port를 쓴다.
func room_code_to_port(code: String) -> int:
	var numeric := code.to_int()
	if numeric > 0:
		return NetworkConstants.BASE_PORT + (numeric % 200)
	return NetworkConstants.BASE_PORT + (abs(code.hash()) % 200)


## 명시 포트로 서버 listen (G4 로비 spawn / LAN Host 공통).
func host_game(port: int, code: String = "") -> Error:
	if port <= 0:
		return ERR_INVALID_PARAMETER
	room_code = code.strip_edges()
	listen_port = port
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, NetworkConstants.MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## 명시 host:port로 클라 접속 (로비 응답 경로).
func join_game(address: String, port: int, code: String = "") -> Error:
	if port <= 0:
		return ERR_INVALID_PARAMETER
	var host := address.strip_edges()
	if host.is_empty():
		return ERR_INVALID_PARAMETER
	room_code = code.strip_edges()
	listen_port = port
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	# Peer 1 = server; stretch timeout before heavy game.tscn load.
	_apply_peer_timeout(peer, 1)
	return OK


## Dedicated CLI `--room` 폴백: code → room_code_to_port 후 listen.
func host_room(code: String) -> Error:
	room_code = code.strip_edges()
	if room_code.is_empty():
		return ERR_INVALID_PARAMETER
	return host_game(room_code_to_port(room_code), room_code)


## multiplayer peer를 닫고 룸 상태를 초기화한다.
func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	room_code = ""
	listen_port = 0
	dedicated_server = false


## ENet peer 타임아웃을 NetworkConstants 값으로 설정한다.
func _apply_peer_timeout(enet_peer: ENetMultiplayerPeer, peer_id: int) -> void:
	var packet_peer := enet_peer.get_peer(peer_id)
	if packet_peer == null:
		return
	packet_peer.set_timeout(
		NetworkConstants.ENET_TIMEOUT_LIMIT,
		NetworkConstants.ENET_TIMEOUT_MIN_MS,
		NetworkConstants.ENET_TIMEOUT_MAX_MS
	)


## multiplayer peer가 있으면 true.
func is_online() -> bool:
	return multiplayer.multiplayer_peer != null


## 이 피어가 서버면 true.
func is_server() -> bool:
	return multiplayer.is_server()


## 접속 중인 원격 peer id 목록.
func get_player_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for peer_id in multiplayer.get_peers():
		ids.append(int(peer_id))
	return ids


## 인게임 UI가 뜰 때 호출. 로컬 표시명·프로필·덱 뒷면·field를 상대에게 보낸다 (2인 전용 단순 교환).
func publish_display_name() -> void:
	if not is_online():
		return
	var name := ""
	var icon := ""
	var card_back := ""
	var field_id := ""
	if AccountService.is_bootstrapped():
		name = AccountService.display_name().strip_edges()
		icon = AccountService.profile_icon_id().strip_edges()
	var session := GameSession.get_active()
	if session:
		session.sync_local_display_name()
		session.sync_local_card_back()
		session.sync_local_field()
		if not session.local_card_back_id.is_empty():
			card_back = session.local_card_back_id
		if not session.local_field_id.is_empty():
			field_id = session.local_field_id
	if name.is_empty():
		return
	if is_server():
		if dedicated_server:
			return
		for peer_id in get_player_peer_ids():
			rpc_notify_opponent_display_name.rpc_id(peer_id, name, icon, card_back, field_id)
	else:
		rpc_submit_display_name.rpc_id(1, name, icon, card_back, field_id)


## 클라→서버: 내 표시명·프로필 아이콘·덱 카드 뒷면·field.
@rpc("any_peer", "reliable")
func rpc_submit_display_name(
	display_name: String,
	profile_icon_id: String = "",
	card_back_id: String = "",
	field_id: String = ""
) -> void:
	if not multiplayer.is_server():
		return
	var name := display_name.strip_edges()
	if name.is_empty():
		return
	var icon := AccessoryCatalog.resolve_icon_id(profile_icon_id.strip_edges())
	var back := AccessoryCatalog.resolve_card_back_id(card_back_id.strip_edges())
	var field := AccessoryCatalog.resolve_field_id(field_id.strip_edges())
	var sender := multiplayer.get_remote_sender_id()
	if not dedicated_server:
		_apply_opponent_profile(name, icon, back, field)
	for peer_id in get_player_peer_ids():
		if peer_id != sender:
			rpc_notify_opponent_display_name.rpc_id(peer_id, name, icon, back, field)


## 서버→클라: 상대 표시명·프로필·덱 카드 뒷면·field.
@rpc("authority", "reliable")
func rpc_notify_opponent_display_name(
	display_name: String,
	profile_icon_id: String = "",
	card_back_id: String = "",
	field_id: String = ""
) -> void:
	_apply_opponent_profile(display_name, profile_icon_id, card_back_id, field_id)


## 세션·GameUILayer에 상대 프로필 반영.
func _apply_opponent_profile(
	display_name: String,
	profile_icon_id: String = "",
	card_back_id: String = "",
	field_id: String = ""
) -> void:
	if dedicated_server:
		return
	var name := display_name.strip_edges()
	if name.is_empty():
		return
	var session := GameSession.get_active()
	if session == null or session.play_mode != GameSessionBase.PlayMode.ONLINE:
		return
	session.apply_opponent_profile_from_network(name, profile_icon_id, card_back_id, field_id)
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("game_ui_layer"):
		if node and node.has_method("refresh_player_id_labels"):
			node.refresh_player_id_labels()


## 클라→서버 INTENT. 서버만 세션 handle_intent로 전달.
@rpc("any_peer", "reliable")
func rpc_submit_intent(intent: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var session := GameSession.get_active()
	if session and session.has_method("handle_intent"):
		session.handle_intent(sender, intent)


## 서버→클라 게임 이벤트. 클라 세션 receive_game_event로 전달.
@rpc("authority", "reliable")
func rpc_game_event(event: Dictionary) -> void:
	if multiplayer.is_server():
		return
	var event_type := String(event.get("type", "?"))
	print("[MP] event received type=%s" % event_type)
	var session := GameSession.get_active()
	if session and session.has_method("receive_game_event"):
		session.receive_game_event(event)


## 레거시: 색 힌트 없이 로딩 씬으로 보낸다 (pending 없으면 로딩 씬이 ensure_loaded 폴백).
@rpc("authority", "reliable")
func rpc_start_game_scene() -> void:
	call_deferred("_change_to_loading_scene")


## 매치 전 로딩: 내/상대 카드 이름 배열을 pending에 넣고 로딩 씬으로 이동한다 (G3b).
## 왜: 커스텀 덱은 색→DEFAULT로 펼치면 틀린 카드를 프리로드한다. 이름 배열이 SSOT.
## opponent_display_name: 상대 표시 ID. GAME_START보다 먼저 도착해 인게임 … 고착을 막음.
## opponent_profile_icon_id / opponent_card_back_id / opponent_field_id: 로딩 단계에서 배지·뒷면·필드 미리 반영.
@rpc("authority", "reliable")
func rpc_start_match_loading(
	my_names: Array,
	opponent_names: Array,
	opponent_display_name: String = "",
	opponent_profile_icon_id: String = "",
	opponent_card_back_id: String = "",
	opponent_field_id: String = "",
	first_player_net: int = 0,
	my_side_net: int = -1
) -> void:
	var session := GameSession.get_active()
	if session:
		session.sync_local_display_name()
		session.apply_opponent_profile_from_network(
			opponent_display_name,
			opponent_profile_icon_id,
			opponent_card_back_id,
			opponent_field_id
		)
		if my_side_net >= 0:
			session.apply_match_intro_seat(my_side_net, first_player_net)
	var merged: Array[String] = []
	for n in my_names:
		merged.append(String(n))
	for n in opponent_names:
		merged.append(String(n))
	GameSession.prepare_match_loading(merged)
	# Defer so this RPC returns and ENet can keep polling before scene change.
	call_deferred("_change_to_loading_scene")


## 카드 로딩 씬으로 전환한다.
func _change_to_loading_scene() -> void:
	get_tree().change_scene_to_file(GameSession.MATCH_LOADING_SCENE)


## 세션 종료 RPC. 접속 해제 후 온라인 준비 화면으로.
@rpc("authority", "reliable")
func rpc_session_ended() -> void:
	GameSession.pending_lobby_message = "상대의 접속이 종료되었습니다."
	disconnect_game()
	GameSession.clear()
	MenuHost.open_root(get_tree(), GameSession.ONLINE_PREPARE_SCENE)


## 특정 peer에 game event RPC.
func send_event_to_peer(peer_id: int, event: Dictionary) -> void:
	if not is_server() or peer_id <= 0:
		return
	rpc_game_event.rpc_id(peer_id, event)


## 모든 원격 peer에 game event broadcast.
func broadcast_event(event: Dictionary) -> void:
	if not is_server():
		return
	var peers := get_player_peer_ids()
	for peer_id in peers:
		rpc_game_event.rpc_id(peer_id, event)
	if dedicated_server or peers.size() > 1:
		print("[MP-SERVER] broadcast type=%s peers=%s" % [
			String(event.get("type", "?")),
			str(peers),
		])


## multiplayer 시그널을 hub 시그널/핸들러에 연결한다.
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: connected_to_server.emit())
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## peer 접속 시 타임아웃 적용 후 peer_joined emit.
func _on_peer_connected(peer_id: int) -> void:
	var mp := multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer:
		_apply_peer_timeout(mp as ENetMultiplayerPeer, peer_id)
	peer_joined.emit(peer_id)


## peer 퇴장. Dedicated는 listen 유지, LAN Host는 전원 종료, 클라는 GAME_OVER 대기.
func _on_peer_disconnected(peer_id: int) -> void:
	print("[MP] peer_disconnected id=%d server=%s dedicated=%s" % [
		peer_id,
		str(multiplayer.is_server()),
		str(dedicated_server),
	])
	peer_left.emit(peer_id)
	if dedicated_server and is_server():
		# Keep peer until session handles leave. G4: empty room → worker quit (not listen reuse).
		return
	if is_server():
		# LAN Host: other client left → end room for everyone.
		_end_session_for_all()
		return
	# Thin client: another player's leave must NOT dump us to lobby.
	# Dedicated forfeit arrives as GAME_OVER from the server.
	# Only server_disconnected / explicit session_ended leave the match.
	print("[MP] ignore peer_disconnected on client (await server GAME_OVER / server_disconnected)")


## 서버 끊김 → 온라인 세션 정리.
func _on_server_disconnected() -> void:
	print("[MP] server_disconnected")
	_leave_online_session()


## 원격 peer에 session_ended를 보낸 뒤 로컬도 떠난다.
func _end_session_for_all() -> void:
	for peer_id in get_player_peer_ids():
		rpc_session_ended.rpc_id(peer_id)
	_leave_online_session()


## Dedicated가 아니면 접속 해제·세션 clear·온라인 준비 화면.
func _leave_online_session() -> void:
	if dedicated_server:
		return
	disconnect_game()
	GameSession.clear()
	if get_tree().current_scene:
		MenuHost.open_root(get_tree(), GameSession.ONLINE_PREPARE_SCENE)
