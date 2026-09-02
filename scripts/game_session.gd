class_name GameSessionBase
extends RefCounted

enum PlayMode { LOCAL_SINGLE, ONLINE }

var play_mode: PlayMode = PlayMode.LOCAL_SINGLE
var first_player: GameConstants.Side = GameConstants.Side.PLAYER
var my_network_side: GameConstants.Side = GameConstants.Side.PLAYER
var effects_enabled: bool = true
## 표시용 id (AccountService.display_name). 인게임 좌하단.
var local_display_name: String = ""
var local_profile_icon_id: String = ""
## 상대 표시용 id. 싱글=COM, 온라인=INTENT_DECK/GAME_START로 수신.
var opponent_display_name: String = ""
var opponent_profile_icon_id: String = ""
var local_card_back_id: String = ""
var opponent_card_back_id: String = ""
var local_field_id: String = ""
var opponent_field_id: String = ""

var _phase_manager: Node = null


## 로컬 표시명을 AccountService에서 채운다.
func sync_local_display_name() -> void:
	if AccountService.is_bootstrapped():
		local_display_name = " " + AccountService.display_name()
		sync_local_profile_icon()


## 로컬 프로필 아이콘 id.
func sync_local_profile_icon() -> void:
	if AccountService.is_bootstrapped():
		local_profile_icon_id = AccessoryCatalog.resolve_icon_id(AccountService.profile_icon_id())


## 로컬 덱 카드 뒷면 id. 온라인 서브클래스에서 오버라이드.
func sync_local_card_back() -> void:
	pass


## 로컬 덱 field id. 온라인 서브클래스에서 오버라이드.
func sync_local_field() -> void:
	pass


## 싱글 기본 상대명·아이콘.
func set_default_opponent_display_name() -> void:
	if play_mode == PlayMode.LOCAL_SINGLE:
		opponent_display_name = "COM "
		opponent_profile_icon_id = AccessoryCatalog.DEFAULT_ICON_ID


## 온라인 상대 표시명·프로필·덱 뒷면·field id (RPC/GAME_START 공용).
func apply_opponent_profile_from_network(
	display_name: String,
	profile_icon_id: String = "",
	card_back_id: String = "",
	field_id: String = ""
) -> void:
	var name := display_name.strip_edges()
	if not name.is_empty():
		opponent_display_name = name
	var icon := AccessoryCatalog.resolve_icon_id(profile_icon_id.strip_edges())
	if not icon.is_empty():
		opponent_profile_icon_id = icon
	var back := AccessoryCatalog.resolve_card_back_id(card_back_id.strip_edges())
	if not back.is_empty():
		opponent_card_back_id = back
	var field := AccessoryCatalog.resolve_field_id(field_id.strip_edges())
	if not field.is_empty():
		opponent_field_id = field
	_refresh_field_boards()


## owner_side(플레이어/상대 덱 존)에 해당하는 field catalog id.
func field_id_for_owner_side(side: GameConstants.Side) -> String:
	if side == GameConstants.Side.PLAYER:
		return AccessoryCatalog.resolve_field_id(local_field_id)
	return AccessoryCatalog.resolve_field_id(opponent_field_id)


func _refresh_field_boards() -> void:
	if _phase_manager == null:
		return
	var field := _phase_manager.get_parent()
	if field == null or field.name != "Field":
		return
	AccessoryRuntime.apply_field_boards(field)

## side별 덱 id 배열 stub. 서브클래스에서 오버라이드한다.
func get_deck_ids_for_side(_side: GameConstants.Side) -> Array[int]:
	return []


## owner_side(플레이어/상대 덱 존)에 해당하는 카드 뒷면 catalog id.
func card_back_id_for_owner_side(side: GameConstants.Side) -> String:
	if side == GameConstants.Side.PLAYER:
		return AccessoryCatalog.resolve_card_back_id(local_card_back_id)
	return AccessoryCatalog.resolve_card_back_id(opponent_card_back_id)


func get_deck_names_for_side(_side: GameConstants.Side) -> Array[String]:
	return CardRegistry.build_default_deck()


## 덱 카피 등급 병렬 배열. 기본은 빈 배열(호출측이 N으로 패딩).
func get_deck_rarities_for_side(_side: GameConstants.Side) -> Array[int]:
	return []


func get_deck_entries_for_local_side(_local_side: GameConstants.Side) -> Array:
	return []


func roll_first_player() -> GameConstants.Side:
	first_player = (
		GameConstants.Side.PLAYER
		if randi() % 2 == 0
		else GameConstants.Side.OPPONENT
	)
	return first_player


## VS 연출 전에 권위가 보낸 seat·선공(net)을 로컬 좌표로 반영한다.
func apply_match_intro_seat(my_side_net: int, first_player_net: int) -> void:
	my_network_side = my_side_net as GameConstants.Side
	first_player = network_side_to_local(first_player_net)


func register_phase_manager(pm: Node) -> void:
	_phase_manager = pm


func get_phase_manager() -> Node:
	return _phase_manager


func network_side_to_local(net_side: int) -> GameConstants.Side:
	return (
		GameConstants.Side.PLAYER
		if net_side == int(my_network_side)
		else GameConstants.Side.OPPONENT
	)


func local_side_to_network(local_side: GameConstants.Side) -> int:
	if local_side == GameConstants.Side.PLAYER:
		return int(my_network_side)
	return int(GameConstants.opposite_side(my_network_side))


## PhaseManager intent 경유 — 로컬 no-op, 네트워크 세션에서 RPC로 교체.
func submit_intent(_intent: Dictionary) -> void:
	pass


## 로컬 플레이어 자발적 항복. 싱글·Host는 즉시 적용, thin client는 INTENT_FORFEIT.
func request_surrender() -> void:
	if _phase_manager == null or not _phase_manager.has_method("force_surrender_game_over"):
		return
	if play_mode == PlayMode.LOCAL_SINGLE:
		_phase_manager.force_surrender_game_over(GameConstants.Side.OPPONENT)
		return
	if is_authoritative() and has_local_player_input():
		_apply_local_authority_surrender()
		return
	submit_intent({"type": NetworkConstants.INTENT_FORFEIT})


## Host LAN: 로컬 seat 항복. Dedicated는 오버라이드하지 않음(UI 없음).
func _apply_local_authority_surrender() -> void:
	pass


func is_authoritative() -> bool:
	return true


func should_start_match_locally() -> bool:
	return is_authoritative()


func handle_intent(_peer_id: int, _intent: Dictionary) -> void:
	pass


func receive_game_event(_event: Dictionary) -> void:
	pass


func broadcast_event(_event: Dictionary) -> void:
	pass


func is_match_ready() -> bool:
	if _phase_manager and _phase_manager.has_method("is_match_ready"):
		return _phase_manager.is_match_ready()
	return true


## False on dedicated headless authority (no seated player / no local effect UI).
func has_local_player_input() -> bool:
	return true


func wait_for_client_scene_ready(_timeout_sec: float = 10.0) -> bool:
	return true


func is_client_scene_ready() -> bool:
	return true
