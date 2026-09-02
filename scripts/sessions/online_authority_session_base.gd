class_name OnlineAuthoritySessionBase
extends GameSessionBase
## LAN Host + Dedicated 공용 Logic-authority 베이스.
## placement wait·DRAW 캐시·덱 엔트리·매치 broadcast duck API (S2).
## join/seat/forfeit·per-peer 송신만 서브클래스. Host는 폐기하지 않음 (B-OA-01~05).

## net_side(int) → 셔플된 덱 엔트리 배열
var _deck_entries_by_net_side: Dictionary = {}
## 마지막 DRAW_RESULT 이벤트 (scene-ready 타임아웃 시 resend용)
var _last_draw_event: Dictionary = {}
## 원격 PLACE intent 대기 중이면 true
var _awaiting_remote_place: bool = false
## finish_remote_placement_wait가 호출되면 true → wait 루프 탈출
var _remote_place_done: bool = false


## 이 세션은 항상 Logic 권위다 (판정·이벤트 송신 주체).
func is_authoritative() -> bool:
	return true


## 로컬 side에 해당하는 덱 엔트리 복사본을 반환한다 (PhaseManager 초기화용).
func get_deck_entries_for_local_side(local_side: GameConstants.Side) -> Array:
	var net_side := local_side_to_network(local_side)
	return _deck_entries_by_net_side.get(net_side, []).duplicate(true)


## 모든 원격 peer에 동일 이벤트를 RPC로 보낸다.
func broadcast_event(event: Dictionary) -> void:
	NetworkManager.broadcast_event(event)


## DRAW_RESULT를 캐시한다. CLIENT_SCENE_READY 타임아웃 시 GAME_START+DRAW 재전송에 쓴다.
func store_last_draw_event(event: Dictionary) -> void:
	_last_draw_event = event.duplicate(true)


## 원격 배치 대기 플래그를 켠다 (wait 전에 PM이 명시 호출하는 경로).
func begin_remote_placement_wait() -> void:
	_awaiting_remote_place = true
	_remote_place_done = false


## 원격 배치 대기를 해제한다. PLACE 성공·실패·forfeit 후 PM/세션이 호출.
func finish_remote_placement_wait() -> void:
	_awaiting_remote_place = false
	_remote_place_done = true


## INTENT_PLACE(또는 finish/abort)까지 프레임 대기한다. Dedicated는 forfeit 시 훅으로 탈출.
func wait_for_remote_placement() -> void:
	_awaiting_remote_place = true
	_remote_place_done = false
	var tree := GameSession.get_hub().get_tree()
	while _awaiting_remote_place and not _remote_place_done and tree and not _is_remote_placement_aborted():
		await tree.process_frame


## 배치 wait를 강제로 끊을지. 기본 false. Dedicated는 _match_ended(forfeit)일 때 true.
func _is_remote_placement_aborted() -> bool:
	return false


## peer seat에 맞게 EVENT_GAME_START를 보낸다. PM start_match가 scene-ready 대기 후 호출.
## 서브클래스 필수 구현 (Host=단일 클라 스왑, Dedicated=per-peer mySide).
func dispatch_game_start() -> void:
	push_error("OnlineAuthoritySessionBase.dispatch_game_start must be overridden")


## scene-ready 타임아웃 시 GAME_START(+캐시 DRAW) 재전송. PM이 is_client_scene_ready 실패 시 호출.
## 서브클래스 필수 구현. 프로토콜·페이로드는 send_game_start_* 와 동일.
func resend_match_init() -> void:
	push_error("OnlineAuthoritySessionBase.resend_match_init must be overridden")


## 권위 좌표 DRAW를 peer seat 시점으로 송신한다. PM enter_draw_phase(권위)가 호출.
## 서브클래스 필수 구현. 왜: Host는 단일 스왑 broadcast, Dedicated는 per-peer remap.
func dispatch_draw_result(_player_draw: Dictionary, _opponent_draw: Dictionary) -> void:
	push_error("OnlineAuthoritySessionBase.dispatch_draw_result must be overridden")


## SETTING 턴 동기용 TURN_CHANGED를 송신한다. PM enter_setting / 배치 confirm 후 호출.
## 서브클래스 필수 구현. 왜: Dedicated만 placement를 seat self/opp로 재매핑 (Host는 권위 좌표 그대로).
func dispatch_turn_changed(
	_active_side: GameConstants.Side,
	_placements_remaining: Dictionary,
	_setting_turn_index: int,
	_permissions: Dictionary = {}
) -> void:
	push_error("OnlineAuthoritySessionBase.dispatch_turn_changed must be overridden")


## DRAW_RESULT 이벤트 Dictionary를 만든다 (중첩 패킷 + flat legacy keys).
## Host/Dedicated dispatch_draw_result가 공통으로 사용. 프로토콜 키는 변경하지 않음.
func make_draw_result_event(self_draw: Dictionary, opponent_draw: Dictionary) -> Dictionary:
	return {
		"type": NetworkConstants.EVENT_DRAW_RESULT,
		"selfDraw": self_draw,
		"opponentDraw": opponent_draw,
		"selfHandLimit": int(self_draw.get("hand_limit", 0)),
		"selfHandEntries": self_draw.get("hand_entries", []),
		"selfDeckRemaining": self_draw.get("deck_remaining", []),
		"selfGraveyardRemaining": self_draw.get("graveyard_remaining", []),
		"selfLifeRemaining": self_draw.get("life_remaining", []),
		"selfStartHandSize": int(self_draw.get("start_hand_size", 0)),
		"opponentHandLimit": int(opponent_draw.get("hand_limit", 0)),
		"opponentHandEntries": opponent_draw.get("hand_entries", []),
		"opponentDeckRemaining": opponent_draw.get("deck_remaining", []),
		"opponentGraveyardRemaining": opponent_draw.get("graveyard_remaining", []),
		"opponentLifeRemaining": opponent_draw.get("life_remaining", []),
		"opponentStartHandSize": int(opponent_draw.get("start_hand_size", 0)),
	}
