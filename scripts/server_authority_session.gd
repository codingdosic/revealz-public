class_name ServerAuthoritySession
extends OnlineAuthoritySessionBase
## Dedicated headless 권위. 로컬 UI 없음. peer[0]=net PLAYER, peer[1]=net OPPONENT.

const REQUIRED_PLAYERS := 2
const LOG_PREFIX := "[MP-SERVER]"

var _peers: Array[int] = []
## peer_id → Array[int] card ids (IdKey Phase 2 우선).
var _deck_ids_by_peer: Dictionary = {}
## peer_id → Array[int] card rarities (parallel to ids).
var _deck_rarities_by_peer: Dictionary = {}
## peer_id → displayName (INTENT_DECK).
var _display_name_by_peer: Dictionary = {}
var _profile_icon_by_peer: Dictionary = {}
var _card_back_by_peer: Dictionary = {}
var _field_by_peer: Dictionary = {}
var _scene_ready_by_peer: Dictionary = {}
var _match_started: bool = false
var _begin_in_progress: bool = false
var _match_ended: bool = false
## peer_id → true while Meta validate-deck in flight (G3.1).
var _deck_validate_pending: Dictionary = {}


## Dedicated 세션 초기화. 권위 좌표는 Side.PLAYER==network 0.
func setup() -> void:
	play_mode = PlayMode.ONLINE
	effects_enabled = true
	my_network_side = GameConstants.Side.PLAYER


## 헤드리스라 로컬 입력/효과 UI를 쓰지 않는다. 결정은 전부로만 수신.
func has_local_player_input() -> bool:
	return false


## game.tscn을 로드하고 PhaseManager를 Logic 권위로 돌린다.
func should_start_match_locally() -> bool:
	return true


## peer 입장. 정원·중복·forfeit 정리 중이면 무시. 2인+덱 모이면 매치 시도.
func on_player_joined(peer_id: int) -> void:
	if _match_ended:
		print("%s ignore join peer=%d (forfeit cleanup — wait for room empty)" % [
			LOG_PREFIX,
			peer_id,
		])
		return
	if _peers.has(peer_id):
		return
	if _peers.size() >= REQUIRED_PLAYERS:
		print("%s ignore join peer=%d (room full)" % [LOG_PREFIX, peer_id])
		return
	_peers.append(peer_id)
	_scene_ready_by_peer[peer_id] = false
	print("%s player_joined id=%d seat=%d peers=%s" % [
		LOG_PREFIX,
		peer_id,
		_peers.size() - 1,
		str(_peers),
	])
	_try_begin_match()


## peer 퇴장. 매치 중이면 forfeit, 매치 전이면 남은 peer에 session_ended. 방 비면 워커 종료(G4).
func on_player_left(peer_id: int) -> void:
	var left_net := net_side_for_peer(peer_id)
	var remaining: Array[int] = []
	for p in _peers:
		if p != peer_id:
			remaining.append(p)

	var abort_match := _match_started and not _match_ended and left_net >= 0
	if abort_match:
		_end_match_by_forfeit(peer_id, left_net, remaining)
	elif not _match_started and not remaining.is_empty():
		_end_prematch_by_peer_left(remaining)

	_peers.erase(peer_id)
	_deck_ids_by_peer.erase(peer_id)
	_deck_rarities_by_peer.erase(peer_id)
	_display_name_by_peer.erase(peer_id)
	_profile_icon_by_peer.erase(peer_id)
	_card_back_by_peer.erase(peer_id)
	_field_by_peer.erase(peer_id)
	_scene_ready_by_peer.erase(peer_id)
	print("%s player_left id=%d remaining=%s" % [LOG_PREFIX, peer_id, str(_peers)])

	if not _match_started:
		_begin_in_progress = false

	if _peers.is_empty():
		_quit_when_room_empty()


## 매치 시작 전 이탈 → 남은 클라를 prepare로 돌려 무한 게이트 대기를 막는다.
func _end_prematch_by_peer_left(remaining_peers: Array[int]) -> void:
	print("%s prematch peer left — session_ended for remaining=%s" % [
		LOG_PREFIX,
		str(remaining_peers),
	])
	for peer_id in remaining_peers:
		NetworkManager.rpc_session_ended.rpc_id(peer_id)

## 이탈자 패배 forfeit. placement/decision wait 해제 → PM game over → 남은 peer에 GAME_OVER.
func _end_match_by_forfeit(
	left_peer_id: int,
	left_net_side: int,
	remaining_peers: Array[int]
) -> void:
	_match_ended = true
	finish_remote_placement_wait()
	_abort_effect_decisions()
	var winner_net := 1 - left_net_side
	print("%s forfeit left_peer=%d left_net=%d winner_net=%d remaining=%s" % [
		LOG_PREFIX,
		left_peer_id,
		left_net_side,
		winner_net,
		str(remaining_peers),
	])
	if _phase_manager and _phase_manager.has_method("force_forfeit_game_over"):
		var winner_local := network_side_to_local(winner_net)
		_phase_manager.force_forfeit_game_over(winner_local)

	for peer_id in remaining_peers:
		NetworkManager.send_event_to_peer(peer_id, {
			"type": NetworkConstants.EVENT_GAME_OVER,
			"winner": winner_net,
			"reason": "forfeit",
		})


## forfeit 시 원격 효과 결정 await를 깨뜨린다.
func _abort_effect_decisions() -> void:
	if _phase_manager == null:
		return
	var em: Variant = _phase_manager.get("effect_manager")
	if em != null and em.has_method("abort_pending_decisions"):
		em.abort_pending_decisions()

## 방 비움 → 프로세스 종료. 로비가 exit 감시로 포트 회수 (G4 · M5 listen 재사용 폐기).
func _quit_when_room_empty() -> void:
	print("%s room empty — worker exit (lobby port reclaim)" % LOG_PREFIX)
	var tree := GameSession.get_hub().get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.quit(0)
	else:
		push_error("%s room empty but no SceneTree — cannot quit" % LOG_PREFIX)


## INTENT에서 displayName·profileIconId·cardBackId·fieldId를 peer dict에 반영 (DECK·SCENE_READY 공용).
func _apply_peer_accessories(peer_id: int, intent: Dictionary) -> void:
	var remote_name := String(intent.get("displayName", "")).strip_edges()
	var remote_icon := AccessoryCatalog.resolve_icon_id(String(intent.get("profileIconId", "")))
	var remote_back := AccessoryCatalog.resolve_card_back_id(String(intent.get("cardBackId", "")))
	var remote_field := AccessoryCatalog.resolve_field_id(String(intent.get("fieldId", "")))
	if not remote_name.is_empty():
		_display_name_by_peer[peer_id] = remote_name
	if not remote_icon.is_empty():
		_profile_icon_by_peer[peer_id] = remote_icon
	if not remote_back.is_empty():
		_card_back_by_peer[peer_id] = remote_back
	if not remote_field.is_empty():
		_field_by_peer[peer_id] = remote_field


## peer_id → net side(0/1). _peers 배열 인덱스가 seat. 없으면 -1.
func net_side_for_peer(peer_id: int) -> int:
	var idx := _peers.find(peer_id)
	if idx < 0:
		return -1
	return idx


## net side(0/1) → peer_id. 없으면 -1.
func _peer_for_net_side(net_side: int) -> int:
	if net_side < 0 or net_side >= _peers.size():
		return -1
	return _peers[net_side]


## 방 peer intent 라우팅. DECK는 G3.1 owned 검증 후 매치 게이트, PLACE는 peer_id 포함해 PM에 전달.
func handle_intent(peer_id: int, intent: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	match String(intent.get("type", "")):
		NetworkConstants.INTENT_DECK:
			_handle_deck_intent(peer_id, intent)
		NetworkConstants.INTENT_CLIENT_SCENE_READY:
			_apply_peer_accessories(peer_id, intent)
			_scene_ready_by_peer[peer_id] = true
			print("%s CLIENT_SCENE_READY peer=%d icon=%s back=%s field=%s" % [
				LOG_PREFIX,
				peer_id,
				String(_profile_icon_by_peer.get(peer_id, "")),
				String(_card_back_by_peer.get(peer_id, "")),
				String(_field_by_peer.get(peer_id, "")),
			])
		NetworkConstants.INTENT_PLACE:
			if _phase_manager:
				_phase_manager.apply_remote_place_intent(intent, peer_id)
		NetworkConstants.INTENT_EFFECT_DECISION:
			if not _accepts_effect_decision_from(peer_id):
				print("%s ignore EFFECT_DECISION from peer=%d (not decision owner)" % [
					LOG_PREFIX,
					peer_id,
				])
				return
			if _phase_manager:
				_phase_manager.deliver_effect_decision(intent)
		NetworkConstants.INTENT_FORFEIT:
			_end_match_by_surrender(peer_id)


## INTENT_DECK: 파싱 → (가능 시) Meta validate-deck → 저장 → 매치 게이트.
func _handle_deck_intent(peer_id: int, intent: Dictionary) -> void:
	if bool(_deck_validate_pending.get(peer_id, false)):
		print("%s DECK ignore peer=%d (validate pending)" % [LOG_PREFIX, peer_id])
		return
	var parsed_ids: Array[int] = DeckEntryBuilder.parse_card_ids(intent.get("cardIds", []))
	if parsed_ids.is_empty():
		var names: Array[String] = _parse_card_names(intent.get("cardNames", []))
		parsed_ids = CardRegistry.names_to_ids(names)
	var rarities: Array[int] = _parse_card_rarities(
		intent.get("cardRarities", []),
		parsed_ids.size()
	)
	var account_key := String(intent.get("accountKey", "")).strip_edges()
	_deck_validate_pending[peer_id] = true
	var check: Dictionary = await _validate_deck_owned(account_key, parsed_ids, rarities)
	_deck_validate_pending.erase(peer_id)
	if not bool(check.get("ok", false)):
		var reason := String(check.get("error", "not_owned"))
		print("%s DECK rejected peer=%d reason=%s" % [LOG_PREFIX, peer_id, reason])
		_reject_deck(peer_id, reason)
		return
	_deck_ids_by_peer[peer_id] = parsed_ids
	_deck_rarities_by_peer[peer_id] = rarities
	_apply_peer_accessories(peer_id, intent)
	print("%s DECK peer=%d cards=%d validate=%s" % [
		LOG_PREFIX,
		peer_id,
		parsed_ids.size(),
		"skipped" if bool(check.get("skipped", false)) else "ok",
	])
	_try_begin_match()


## Meta validate-deck. META 불가·503이면 스킵(수락). 그 외 실패는 거부.
func _validate_deck_owned(
	account_key: String,
	card_ids: Array[int],
	card_rarities: Array[int]
) -> Dictionary:
	var http := _meta_http()
	if http == null:
		return {"ok": true, "skipped": true, "error": ""}
	if account_key.is_empty():
		# Meta URL이 있으면 키 필수 — 없으면 스킵(로컬/레거시 워커).
		if OS.get_environment("META_LOBBY_URL").strip_edges().is_empty():
			return {"ok": true, "skipped": true, "error": ""}
		return {"ok": false, "error": "account_key_required"}
	var ids_wire: Array = []
	for id in card_ids:
		ids_wire.append(int(id))
	var rar_wire: Array = []
	for r in card_rarities:
		rar_wire.append(int(r))
	var res: Dictionary = await MetaRemote.validate_deck(http, account_key, {
		"card_ids": ids_wire,
		"card_rarities": rar_wire,
	})
	if bool(res.get("ok", false)):
		return {"ok": true, "skipped": false, "error": ""}
	var status := int(res.get("status", 0))
	var err := String(res.get("error", "validate_failed"))
	# Meta 미설정·다운 → 매칭 막지 않음 (개발/폴백).
	if status == 503 or err == "meta_db_not_configured" or err.begins_with("http_result"):
		print("%s DECK validate skipped status=%d error=%s" % [LOG_PREFIX, status, err])
		return {"ok": true, "skipped": true, "error": err}
	return {"ok": false, "error": err}


## 덱 거부 이벤트 후 peer 연결 종료.
func _reject_deck(peer_id: int, reason: String) -> void:
	_deck_ids_by_peer.erase(peer_id)
	_deck_rarities_by_peer.erase(peer_id)
	NetworkManager.send_event_to_peer(peer_id, {
		"type": NetworkConstants.EVENT_DECK_REJECTED,
		"reason": reason,
	})
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(0.15).timeout
	var mp := NetworkManager.multiplayer.multiplayer_peer if NetworkManager else null
	if mp != null and peer_id > 0:
		mp.disconnect_peer(peer_id)


## 트리에 검증용 HTTPRequest를 두거나 재사용.
func _meta_http() -> HTTPRequest:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var existing := tree.root.get_node_or_null("MetaValidateHttp") as HTTPRequest
	if existing != null:
		return existing
	var http := HTTPRequest.new()
	http.name = "MetaValidateHttp"
	http.timeout = 12.0
	tree.root.add_child(http)
	return http


## 자발적 항복. 양 peer에 GAME_OVER(reason=surrender). 이탈 forfeit과 달리 양쪽 유지.
func _end_match_by_surrender(loser_peer_id: int) -> void:
	if _match_ended:
		return
	var loser_net := net_side_for_peer(loser_peer_id)
	if loser_net < 0:
		return
	_match_ended = true
	finish_remote_placement_wait()
	var winner_net := 1 - loser_net
	print("%s surrender loser_peer=%d loser_net=%d winner_net=%d" % [
		LOG_PREFIX,
		loser_peer_id,
		loser_net,
		winner_net,
	])
	if _phase_manager and _phase_manager.has_method("force_surrender_game_over"):
		_phase_manager.force_surrender_game_over(network_side_to_local(winner_net))
	var event := {
		"type": NetworkConstants.EVENT_GAME_OVER,
		"winner": winner_net,
		"reason": "surrender",
	}
	for peer_id in _peers:
		NetworkManager.send_event_to_peer(peer_id, event)


## 효과 결정 INTENT 수락 여부. 대기 중인 owner net-side와 peer seat가 같을 때만 true.
## is_decision_owner_for_net_side(로컬 UI 소유)와 혼동하지 말 것.
## 왜: EM private `.get()` 대신 `get_decision_gate_state()` 계약 사용 (S4 / B-EM-08).
func _accepts_effect_decision_from(peer_id: int) -> bool:
	var net := net_side_for_peer(peer_id)
	if net < 0:
		return false
	if _phase_manager == null:
		return true
	var em: Variant = _phase_manager.get("effect_manager")
	if em == null:
		return true
	if not em.has_method("get_decision_gate_state"):
		return true
	var gate: Dictionary = em.get_decision_gate_state()
	if bool(gate.get("waiting", false)):
		var owner_net := int(gate.get("owner_net_side", -1))
		if owner_net >= 0:
			return net == owner_net
	return true


## 각 peer에 seat 시점의 EVENT_GAME_START를 보낸다 (mySide·덱 필드 per-peer).
## 왜: Dedicated는 seat마다 self 덱이 다르므로 단일 broadcast 불가.
func dispatch_game_start() -> void:
	for peer_id in _peers:
		var my_side := net_side_for_peer(peer_id)
		if my_side < 0:
			continue
		var other_side := 1 - my_side
		var other_peer := _peer_for_net_side(other_side)
		if other_peer <= 0:
			push_warning("%s GAME_START skip peer=%d — invalid other_peer for side=%d" % [
				LOG_PREFIX,
				peer_id,
				other_side,
			])
			continue
		var event := {
			"type": NetworkConstants.EVENT_GAME_START,
			"mySide": my_side,
			"firstPlayer": int(first_player),
			"effectsEnabled": effects_enabled,
			"playerDeck": _deck_entries_by_net_side[my_side],
			"opponentDeck": _deck_entries_by_net_side[other_side],
			"opponentDisplayName": String(_display_name_by_peer.get(other_peer, "")),
			"opponentProfileIconId": AccessoryCatalog.resolve_icon_id(
				String(_profile_icon_by_peer.get(other_peer, ""))
			),
			"opponentCardBackId": AccessoryCatalog.resolve_card_back_id(
				String(_card_back_by_peer.get(other_peer, ""))
			),
			"opponentFieldId": AccessoryCatalog.resolve_field_id(
				String(_field_by_peer.get(other_peer, ""))
			),
		}
		NetworkManager.rpc_game_event.rpc_id(peer_id, event)
		print("%s GAME_START peer=%d mySide=%d firstPlayer=%d oppIcon=%s oppBack=%s" % [
			LOG_PREFIX,
			peer_id,
			my_side,
			int(first_player),
			String(event.get("opponentProfileIconId", "")),
			String(event.get("opponentCardBackId", "")),
		])


## 전 peer에 GAME_START 재전송 + 캐시된 DRAW_RESULT가 있으면 함께 보냄.
## 왜: _last_draw_event는 단일 캐시(마지막 peer 페이로드) — 기존 resend 동작 유지.
func resend_match_init() -> void:
	dispatch_game_start()
	if _last_draw_event.is_empty():
		return
	for peer_id in _peers:
		NetworkManager.rpc_game_event.rpc_id(peer_id, _last_draw_event)


## peer별 seat 시점으로 DRAW_RESULT를 재매핑해 개별 송신한다.
## 왜: seat마다 self/opponent 덱·핸드가 다르므로 per-peer 좌표 동일 보장에 필요.
func dispatch_draw_result(player_draw: Dictionary, opponent_draw: Dictionary) -> void:
	for peer_id in _peers:
		var net_side := net_side_for_peer(peer_id)
		if net_side < 0:
			continue
		var self_draw: Dictionary = (
			player_draw if net_side == int(GameConstants.Side.PLAYER) else opponent_draw
		)
		var opp_draw: Dictionary = (
			opponent_draw if net_side == int(GameConstants.Side.PLAYER) else player_draw
		)
		var event := make_draw_result_event(self_draw, opp_draw)
		NetworkManager.send_event_to_peer(peer_id, event)
		store_last_draw_event(event)
		print("%s DRAW_RESULT peer=%d net=%d self_entries=%d opp_entries=%d" % [
			LOG_PREFIX,
			peer_id,
			net_side,
			self_draw.get("hand_entries", []).size(),
			opp_draw.get("hand_entries", []).size(),
		])


## peer별 placement를 seat self/opp로 재매핑한 TURN_CHANGED를 개별 송신한다.
## 왜: 수신측은 playerPlacements=자기 남은 배치로 해석 — Host권위 좌표 그대로면 seat1이 깨짐.
func dispatch_turn_changed(
	active_side: GameConstants.Side,
	placements_remaining: Dictionary,
	setting_turn_index: int,
	permissions: Dictionary = {}
) -> void:
	for peer_id in _peers:
		var net_side := net_side_for_peer(peer_id)
		if net_side < 0:
			continue
		var self_rem: int = int(
			placements_remaining[GameConstants.Side.PLAYER]
			if net_side == int(GameConstants.Side.PLAYER)
			else placements_remaining[GameConstants.Side.OPPONENT]
		)
		var opp_rem: int = int(
			placements_remaining[GameConstants.Side.OPPONENT]
			if net_side == int(GameConstants.Side.PLAYER)
			else placements_remaining[GameConstants.Side.PLAYER]
		)
		var payload := {
			"type": NetworkConstants.EVENT_TURN_CHANGED,
			"activeSide": local_side_to_network(active_side),
			"playerPlacements": self_rem,
			"opponentPlacements": opp_rem,
			"settingTurnIndex": setting_turn_index,
		}
		if not permissions.is_empty():
			# Dedicated: 수신 측 playerPermission=자기 seat 배치권
			var self_perm: int = int(
				permissions.get(GameConstants.Side.PLAYER, 0)
				if net_side == int(GameConstants.Side.PLAYER)
				else permissions.get(GameConstants.Side.OPPONENT, 0)
			)
			var opp_perm: int = int(
				permissions.get(GameConstants.Side.OPPONENT, 0)
				if net_side == int(GameConstants.Side.PLAYER)
				else permissions.get(GameConstants.Side.PLAYER, 0)
			)
			payload["playerPermission"] = self_perm
			payload["opponentPermission"] = opp_perm
		NetworkManager.send_event_to_peer(peer_id, payload)


## 전원 CLIENT_SCENE_READY인지.
func is_client_scene_ready() -> bool:
	return _all_scene_ready()


## forfeit 등으로 매치가 중단됐는지. PM이 GAME_START/DRAW 스킵에 사용.
func is_match_aborted() -> bool:
	return _match_ended


## 전원 scene-ready 대기. timeout 기본값은 NetworkConstants.SCENE_READY_TIMEOUT_SEC.
func wait_for_client_scene_ready(timeout_sec: float = -1.0) -> bool:
	if timeout_sec < 0.0:
		timeout_sec = NetworkConstants.SCENE_READY_TIMEOUT_SEC
	return await _wait_all_scene_ready(timeout_sec)


## wall-clock로 전원 SCENE_READY를 기다린다. headless는 FPS 무제한이라 frame 카운트 금지.
func _wait_all_scene_ready(timeout_sec: float) -> bool:
	var tree := GameSession.get_hub().get_tree()
	if tree == null:
		return false
	var deadline_ms := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not _all_scene_ready() and not _match_ended:
		if Time.get_ticks_msec() >= deadline_ms:
			push_warning("%s CLIENT_SCENE_READY timeout after %.1fs ready=%s peers=%s" % [
				LOG_PREFIX,
				timeout_sec,
				str(_scene_ready_by_peer),
				str(_peers),
			])
			break
		await tree.process_frame
	return _all_scene_ready() and not _match_ended


## forfeit(_match_ended)면 placement wait 루프를 끊는다.
func _is_remote_placement_aborted() -> bool:
	return _match_ended


## 2인 + 양쪽 INTENT_DECK가 모였을 때만 _begin_online_match 진입 (중복 시작 방지).
func _try_begin_match() -> void:
	if _match_started or _begin_in_progress:
		return
	if _peers.size() < REQUIRED_PLAYERS:
		return
	for peer_id in _peers:
		if not _deck_ids_by_peer.has(peer_id):
			return
	_begin_in_progress = true
	_begin_online_match()


## 양 덱∪토큰 스코프 id 로드 → 덱 준비·first_player → peer 로딩 RPC(이름) → 권위 game.tscn.
## G4e-L1: 부팅 전량 로드 대신 INTENT_DECK 이후 ensure_deck_union_tokens_loaded_ids.
func _begin_online_match() -> void:
	var deck_scope := _collect_peer_deck_ids()
	print("%s CardRegistry scope start ids=%d (deck∪token)" % [
		LOG_PREFIX,
		deck_scope.size(),
	])
	var t0 := Time.get_ticks_msec()
	var loaded_scope: Array[int] = await CardRegistry.ensure_deck_union_tokens_loaded_ids(
		deck_scope,
		_on_match_card_load_progress
	)
	var elapsed_sec := (Time.get_ticks_msec() - t0) / 1000.0
	print("%s CardRegistry scope loaded count=%d wall=%.2fs" % [
		LOG_PREFIX,
		loaded_scope.size(),
		elapsed_sec,
	])
	if _match_ended or _peers.size() < REQUIRED_PLAYERS:
		_begin_in_progress = false
		print("%s abort begin_match after card load (peers=%s ended=%s)" % [
			LOG_PREFIX,
			str(_peers),
			str(_match_ended),
		])
		return
	_match_started = true
	_prepare_decks()
	first_player = roll_first_player()
	print("%s begin_match first_player=%d seats=%s" % [
		LOG_PREFIX,
		int(first_player),
		str(_peers),
	])
	for peer_id in _peers:
		var my_ids := _ids_for_peer(peer_id)
		var opp_ids := CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
		var opp_display := ""
		var opp_icon := ""
		var opp_back := ""
		var opp_field := ""
		for other_id in _peers:
			if int(other_id) == int(peer_id):
				continue
			opp_ids = _ids_for_peer(other_id)
			opp_display = String(_display_name_by_peer.get(other_id, ""))
			opp_icon = AccessoryCatalog.resolve_icon_id(
				String(_profile_icon_by_peer.get(other_id, ""))
			)
			opp_back = AccessoryCatalog.resolve_card_back_id(
				String(_card_back_by_peer.get(other_id, ""))
			)
			opp_field = AccessoryCatalog.resolve_field_id(
				String(_field_by_peer.get(other_id, ""))
			)
			break
		var my_side := net_side_for_peer(peer_id)
		NetworkManager.rpc_start_match_loading.rpc_id(
			peer_id,
			CardRegistry.ids_to_names(my_ids),
			CardRegistry.ids_to_names(opp_ids),
			opp_display,
			opp_icon,
			opp_back,
			opp_field,
			int(first_player),
			my_side,
		)
	GameSession.get_hub().change_scene_to_game()


## 양 peer 덱 id 합집합 (고유). ensure_deck_union_tokens_loaded_ids 스코프용.
func _collect_peer_deck_ids() -> Array[int]:
	var merged: Array[int] = []
	for peer_id in _peers:
		merged.append_array(_ids_for_peer(peer_id))
	return CardRegistry.unique_card_ids(merged)


## 매치 스코프 로드 진행 로그 (전량 퍼센트 대신 done/total·label).
func _on_match_card_load_progress(done: int, total: int, label: String) -> void:
	if done == 1 or done == total or done % 10 == 0:
		print("%s CardRegistry scope %d/%d label=%s" % [
			LOG_PREFIX,
			done,
			maxi(total, 1),
			label,
		])


## peer[0]/peer[1] id·등급 덱으로 _deck_entries_by_net_side를 채운다.
func _prepare_decks() -> void:
	_deck_entries_by_net_side = DeckEntryBuilder.prepare_decks_from_ids(
		_ids_for_peer(_peers[0]),
		_ids_for_peer(_peers[1]),
		_rarities_for_peer(_peers[0]),
		_rarities_for_peer(_peers[1])
	)


## peer 덱 id. 없으면 흑 기본.
func _ids_for_peer(peer_id: int) -> Array[int]:
	var raw: Variant = _deck_ids_by_peer.get(peer_id, null)
	if raw is Array:
		var out: Array[int] = []
		for item in raw as Array:
			var v := int(item)
			if v > 0:
				out.append(v)
		if not out.is_empty():
			return out
	return CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)


## peer 덱 등급. id 길이에 맞춰 N 패딩.
func _rarities_for_peer(peer_id: int) -> Array[int]:
	var ids := _ids_for_peer(peer_id)
	var raw: Variant = _deck_rarities_by_peer.get(peer_id, null)
	return _parse_card_rarities(raw if raw != null else [], ids.size())


## intent cardNames → Array[String]. 비면 흑 기본. cardIds 없을 때 폴백용.
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


## 정원 충족 + 모든 peer가 CLIENT_SCENE_READY인지.
func _all_scene_ready() -> bool:
	if _peers.size() < REQUIRED_PLAYERS:
		return false
	for peer_id in _peers:
		if not bool(_scene_ready_by_peer.get(peer_id, false)):
			return false
	return true
