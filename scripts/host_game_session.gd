class_name HostGameSession
extends OnlineAuthoritySessionBase
## LAN Host: 한 프로세스가 seated PLAYER + Logic 권위를 겸한다 (레거시, 유지).

var _remote_peer_id: int = 0
var _client_scene_ready: bool = false
## 호스트 덱 id (IdKey Phase 2).
var _host_deck_ids: Array[int] = []
var _host_deck_rarities: Array[int] = []
## 클라 덱 id (INTENT_DECK cardIds 우선, 없으면 cardNames→ids 폴백).
var _client_deck_ids: Array[int] = []
var _client_deck_rarities: Array[int] = []
var _client_deck_received: bool = false
var _host_deck_id: String = ""


## 온라인 Host 세션을 초기화한다. my_network_side=PLAYER, 호스트 덱 id 저장.
func setup(
	deck_ids: Array[int] = [],
	deck_rarities: Array[int] = [],
	deck_id: String = ""
) -> void:
	play_mode = PlayMode.ONLINE
	effects_enabled = true
	my_network_side = GameConstants.Side.PLAYER
	_host_deck_id = deck_id.strip_edges()
	if deck_ids.is_empty():
		_host_deck_ids = CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
		_host_deck_rarities = []
	else:
		_host_deck_ids = deck_ids.duplicate()
		_host_deck_rarities = deck_rarities.duplicate()
	local_card_back_id = DeckStore.card_back_id_of(_host_deck_id) if not _host_deck_id.is_empty() else AccessoryCatalog.DEFAULT_CARD_BACK_ID
	local_field_id = DeckStore.field_id_of(_host_deck_id) if not _host_deck_id.is_empty() else AccessoryCatalog.DEFAULT_FIELD_ID
	sync_local_display_name()
	opponent_display_name = ""


func sync_local_card_back() -> void:
	local_card_back_id = DeckStore.card_back_id_of(_host_deck_id) if not _host_deck_id.is_empty() else AccessoryCatalog.DEFAULT_CARD_BACK_ID


func sync_local_field() -> void:
	local_field_id = DeckStore.field_id_of(_host_deck_id) if not _host_deck_id.is_empty() else AccessoryCatalog.DEFAULT_FIELD_ID


## 원격 클라 접속 시 호출. peer 기록 후 즉시 매치 시작(방 정원 게이트 없음).
func on_client_joined(peer_id: int) -> void:
	_remote_peer_id = peer_id
	_client_scene_ready = false
	_client_deck_received = false
	_client_deck_ids = CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
	_client_deck_rarities = []
	_begin_online_match(peer_id)


## 클라 덱 대기 → 덱 준비 → first_player 롤 → 양측 로딩 씬(이름 RPC) → 이후 game.
func _begin_online_match(peer_id: int) -> void:
	await _wait_for_client_deck(3.0)
	_prepare_decks()
	first_player = roll_first_player()
	# 클라 시점: my=클라 덱, opponent=호스트 덱. RPC는 이름으로 송신.
	var host_name := local_display_name
	if host_name.is_empty() and AccountService.is_bootstrapped():
		host_name = AccountService.display_name()
	NetworkManager.rpc_start_match_loading.rpc_id(
		peer_id,
		CardRegistry.ids_to_names(_client_deck_ids),
		CardRegistry.ids_to_names(_host_deck_ids),
		host_name,
		AccessoryCatalog.resolve_icon_id(local_profile_icon_id),
		AccessoryCatalog.resolve_card_back_id(local_card_back_id),
		AccessoryCatalog.resolve_field_id(local_field_id),
		int(first_player),
		int(GameConstants.Side.OPPONENT),
	)
	var merged_ids: Array[int] = []
	merged_ids.append_array(_host_deck_ids)
	merged_ids.append_array(_client_deck_ids)
	GameSession.begin_match_loading_ids(merged_ids)


## INTENT_DECK가 올 때까지 frame 대기. 타임아웃 시 클라 흑 기본으로 진행.
func _wait_for_client_deck(timeout_sec: float) -> void:
	var tree := GameSession.get_hub().get_tree()
	if tree == null:
		return
	var max_frames := int(timeout_sec * 60.0)
	var frames := 0
	while not _client_deck_received and frames < max_frames:
		await tree.process_frame
		frames += 1


## 호스트/클라 id·등급 덱으로 _deck_entries_by_net_side를 채운다.
func _prepare_decks() -> void:
	_deck_entries_by_net_side = DeckEntryBuilder.prepare_decks_from_ids(
		_host_deck_ids,
		_client_deck_ids,
		_host_deck_rarities,
		_client_deck_rarities
	)


## 원격 peer intent 라우팅: PLACE/EFFECT → PM, SCENE_READY/DECK → 세션 플래그.
func handle_intent(peer_id: int, intent: Dictionary) -> void:
	if peer_id != _remote_peer_id:
		return
	match String(intent.get("type", "")):
		NetworkConstants.INTENT_PLACE:
			if _phase_manager:
				_phase_manager.apply_remote_place_intent(intent)
		NetworkConstants.INTENT_EFFECT_DECISION:
			if _phase_manager:
				_phase_manager.deliver_effect_decision(intent)
		NetworkConstants.INTENT_CLIENT_SCENE_READY:
			_apply_peer_accessories(intent)
			_client_scene_ready = true
			print("[MP-DRAW] CLIENT_SCENE_READY from peer %d back=%s" % [
				peer_id,
				opponent_card_back_id,
			])
		NetworkConstants.INTENT_DECK:
			# cardIds 우선 파싱; 없으면 cardNames→ids 폴백.
			var parsed_ids: Array[int] = DeckEntryBuilder.parse_card_ids(intent.get("cardIds", []))
			if not parsed_ids.is_empty():
				_client_deck_ids = parsed_ids
			else:
				_client_deck_ids = CardRegistry.names_to_ids(_parse_card_names(intent.get("cardNames", [])))
			_client_deck_rarities = _parse_card_rarities(
				intent.get("cardRarities", []),
				_client_deck_ids.size()
			)
			_client_deck_received = true
			_apply_peer_accessories(intent)
			if _phase_manager and _phase_manager.has_method("get_node_or_null"):
				var game_ui: Node = _phase_manager.get_node_or_null("../GameUILayer")
				if game_ui and game_ui.has_method("refresh_player_id_labels"):
					game_ui.refresh_player_id_labels()
		NetworkConstants.INTENT_FORFEIT:
			# 원격 클라 항복 → Host(PLAYER) 승.
			_finish_surrender(GameConstants.Side.PLAYER)


## Host 본인 항복. 상대(OPPONENT) 승 + GAME_OVER 방송.
func _apply_local_authority_surrender() -> void:
	_finish_surrender(GameConstants.Side.OPPONENT)


## 항복 승자를 로컬에 적용하고 원격에 reason=surrender로 방송한다.
func _finish_surrender(winner_local: GameConstants.Side) -> void:
	if _phase_manager == null or not _phase_manager.has_method("force_surrender_game_over"):
		return
	if _phase_manager.current_phase == GameConstants.Phase.GAME_OVER:
		return
	_phase_manager.force_surrender_game_over(winner_local)
	broadcast_event({
		"type": NetworkConstants.EVENT_GAME_OVER,
		"winner": local_side_to_network(winner_local),
		"reason": "surrender",
	})
	print("[MP] surrender winner_local=%d" % int(winner_local))


## intent cardNames Variant → Array[String]. 비면 흑 기본. cardIds 없을 때 폴백용.
func _parse_card_names(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for item in raw as Array:
			out.append(String(item))
	if out.is_empty():
		return CardRegistry.build_deck_for_color(CardRegistry.DeckColor.BLACK)
	return out


## intent cardRarities → Array[int]. length에 맞춰 N으로 패딩. PackedInt32Array 허용(RPC).
func _parse_card_rarities(raw: Variant, length: int) -> Array[int]:
	return DeckEntryBuilder.parse_rarities(raw, length)


## INTENT에서 상대 표시·악세서리 id를 세션에 반영 (DECK·SCENE_READY 공용).
func _apply_peer_accessories(intent: Dictionary) -> void:
	var remote_name := String(intent.get("displayName", "")).strip_edges()
	var remote_icon := AccessoryCatalog.resolve_icon_id(String(intent.get("profileIconId", "")))
	var remote_back := AccessoryCatalog.resolve_card_back_id(String(intent.get("cardBackId", "")))
	var remote_field := AccessoryCatalog.resolve_field_id(String(intent.get("fieldId", "")))
	apply_opponent_profile_from_network(remote_name, remote_icon, remote_back, remote_field)


## 원격 클라에 EVENT_GAME_START를 보낸다. mySide=OPPONENT, 덱 필드는 클라 시점으로 스왑.
## 왜: LAN Host 원격 seat는 항상 net OPPONENT 하나뿐이라 per-peer 루프가 불필요.
func dispatch_game_start() -> void:
	if _remote_peer_id <= 0:
		return
	var client_event := {
		"type": NetworkConstants.EVENT_GAME_START,
		"mySide": int(GameConstants.Side.OPPONENT),
		"firstPlayer": int(first_player),
		"effectsEnabled": effects_enabled,
		"playerDeck": _deck_entries_by_net_side[int(GameConstants.Side.OPPONENT)],
		"opponentDeck": _deck_entries_by_net_side[int(GameConstants.Side.PLAYER)],
		# 클라 시점 상대 = Host 표시명
		"opponentDisplayName": local_display_name if not local_display_name.is_empty() else AccountService.display_name(),
		"opponentProfileIconId": AccessoryCatalog.resolve_icon_id(
			local_profile_icon_id if not local_profile_icon_id.is_empty() else AccountService.profile_icon_id()
		),
		"opponentCardBackId": AccessoryCatalog.resolve_card_back_id(local_card_back_id),
		"opponentFieldId": AccessoryCatalog.resolve_field_id(local_field_id),
	}
	NetworkManager.rpc_game_event.rpc_id(_remote_peer_id, client_event)
	print("[MP-DRAW] GAME_START sent to peer %d" % _remote_peer_id)


## GAME_START를 다시 보내고, 캐시된 DRAW_RESULT가 있으면 함께 재전송한다.
func resend_match_init() -> void:
	dispatch_game_start()
	if not _last_draw_event.is_empty():
		NetworkManager.rpc_game_event.rpc_id(_remote_peer_id, _last_draw_event)
		print("[MP-DRAW] DRAW_RESULT resent to peer %d" % _remote_peer_id)


## 권위 DRAW를 클라 seat(OPPONENT) 시점으로 스왑해 broadcast한다.
## 왜: Host는 단일 원격 peer라 per-peer remap 없이 self/opp 한 번 교환하면 됨.
func dispatch_draw_result(player_draw: Dictionary, opponent_draw: Dictionary) -> void:
	var client_self_draw := opponent_draw
	var client_opponent_draw := player_draw
	var host_event := make_draw_result_event(client_self_draw, client_opponent_draw)
	broadcast_event(host_event)
	store_last_draw_event(host_event)
	print(
		"[MP-DRAW] DRAW_RESULT broadcast self_entries=%d limit=%d | opp_entries=%d limit=%d"
		% [
			client_self_draw.get("hand_entries", []).size(),
			int(client_self_draw.get("hand_limit", 0)),
			client_opponent_draw.get("hand_entries", []).size(),
			int(client_opponent_draw.get("hand_limit", 0)),
		]
	)


## TURN_CHANGED를 권위 좌표 그대로 broadcast한다.
## 왜: Host LAN 경로 기존 동작 유지 — Dedicated와 달리 placement seat remap 없음.
func dispatch_turn_changed(
	active_side: GameConstants.Side,
	placements_remaining: Dictionary,
	setting_turn_index: int,
	permissions: Dictionary = {}
) -> void:
	var payload := {
		"type": NetworkConstants.EVENT_TURN_CHANGED,
		"activeSide": local_side_to_network(active_side),
		"playerPlacements": placements_remaining[GameConstants.Side.PLAYER],
		"opponentPlacements": placements_remaining[GameConstants.Side.OPPONENT],
		"settingTurnIndex": setting_turn_index,
	}
	if not permissions.is_empty():
		payload["playerPermission"] = int(permissions.get(GameConstants.Side.PLAYER, 0))
		payload["opponentPermission"] = int(permissions.get(GameConstants.Side.OPPONENT, 0))
	broadcast_event(payload)


## 원격 클라가 game.tscn 로드 후 CLIENT_SCENE_READY를 보냈는지.
func is_client_scene_ready() -> bool:
	return _client_scene_ready


## CLIENT_SCENE_READY까지 frame 대기. 타임아웃해도 false만 반환(매치는 계속 가능).
func wait_for_client_scene_ready(timeout_sec: float = 10.0) -> bool:
	var tree := GameSession.get_hub().get_tree()
	if tree == null:
		return false
	var max_frames := int(timeout_sec * 60.0)
	var frames := 0
	while not _client_scene_ready and frames < max_frames:
		await tree.process_frame
		frames += 1
	if not _client_scene_ready:
		push_warning("[MP-DRAW] CLIENT_SCENE_READY timeout after %.1fs" % timeout_sec)
	return _client_scene_ready
