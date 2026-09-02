## 온라인 thin client 세션. GAME_START/덱은 PM 네트워크 큐로 적용한다.
## 권위 로직·덱 엔트리 소유 없음. INTENT만 서버로 올린다.
class_name ClientGameSession
extends GameSessionBase

var _pending_events: Array = []
## 준비 화면에서 고른 덱 카드 id (G3b INTENT_DECK IdKey Phase 2).
var _deck_ids: Array[int] = []
var _deck_rarities: Array[int] = []
var _deck_id: String = ""


## 온라인 클라 세션 초기화. my_network_side 기본값은 OPPONENT(서버가 GAME_START로 덮음).
func setup(
	deck_ids: Array[int] = [],
	deck_rarities: Array[int] = [],
	deck_id: String = ""
) -> void:
	play_mode = PlayMode.ONLINE
	effects_enabled = true
	my_network_side = GameConstants.Side.OPPONENT
	_deck_id = deck_id.strip_edges()
	if deck_ids.is_empty():
		_deck_ids = CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
		_deck_rarities = []
	else:
		_deck_ids = deck_ids.duplicate()
		_deck_rarities = deck_rarities.duplicate()
	sync_local_display_name()
	sync_local_card_back()
	sync_local_field()
	opponent_display_name = ""


func sync_local_card_back() -> void:
	if _deck_id.is_empty():
		local_card_back_id = AccessoryCatalog.DEFAULT_CARD_BACK_ID
	else:
		local_card_back_id = DeckStore.card_back_id_of(_deck_id)


func sync_local_field() -> void:
	if _deck_id.is_empty():
		local_field_id = AccessoryCatalog.DEFAULT_FIELD_ID
	else:
		local_field_id = DeckStore.field_id_of(_deck_id)


## INTENT_DECK에 실을 카드 id 배열.
func get_deck_ids() -> Array[int]:
	return _deck_ids.duplicate()


## INTENT_DECK에 실을 카드 이름 배열 (ids_to_names 파생; 호환 유지).
func get_deck_names() -> Array[String]:
	return CardRegistry.ids_to_names(_deck_ids)


## INTENT_DECK에 실을 카피 등급 배열 (ids와 병렬).
func get_deck_rarities() -> Array[int]:
	return _deck_rarities.duplicate()


## 클라는 비권위.
func is_authoritative() -> bool:
	return false


## 로컬에서 start_match 덱 초기화를 돌리지 않음 — GAME_START 이벤트 대기.
func should_start_match_locally() -> bool:
	return false


## INTENT를 서버(peer 1)로 RPC.
func submit_intent(intent: Dictionary) -> void:
	NetworkManager.rpc_submit_intent.rpc_id(1, intent)


## PM 등록 시 pending flush + SCENE_READY.
func register_phase_manager(pm: Node) -> void:
	super.register_phase_manager(pm)
	for event in _pending_events:
		pm.enqueue_network_event(event)
	_pending_events.clear()
	sync_local_card_back()
	sync_local_field()
	sync_local_profile_icon()
	submit_intent({
		"type": NetworkConstants.INTENT_CLIENT_SCENE_READY,
		"displayName": local_display_name.strip_edges(),
		"profileIconId": local_profile_icon_id,
		"cardBackId": local_card_back_id,
		"fieldId": local_field_id,
	})


## 권위→클라 이벤트. PM 전이면 큐, 이후 enqueue.
func receive_game_event(event: Dictionary) -> void:
	# M1 probe — logged in NetworkManager; do not apply as match event.
	if String(event.get("type", "")) == NetworkConstants.EVENT_FANOUT_PROBE:
		return
	if String(event.get("type", "")) == NetworkConstants.EVENT_DECK_REJECTED:
		_on_deck_rejected(String(event.get("reason", "not_owned")))
		return
	if _phase_manager == null:
		_pending_events.append(event)
		return
	_phase_manager.enqueue_network_event(event)


## G3.1 덱 거부 — 접속 종료 후 온라인 준비로 돌아가 사유 표시.
func _on_deck_rejected(reason: String) -> void:
	var msg := "덱이 서버 보유와 맞지 않습니다"
	match reason:
		"not_owned":
			msg = "보유하지 않은 카드가 덱에 포함되어 있습니다"
		"account_not_found", "account_key_required":
			msg = "계정 메타를 확인할 수 없습니다"
		"empty_deck":
			msg = "덱이 비어 있습니다"
	print("[MP] DECK_REJECTED reason=%s" % reason)
	GameSession.pending_lobby_message = msg
	NetworkManager.disconnect_game()
	GameSession.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		MenuHost.open_root(tree, GameSession.ONLINE_PREPARE_SCENE)
