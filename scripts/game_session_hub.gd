## Autoload 세션 hub. 활성 GameSessionBase 생성·씬 전환·peer join/leave 라우팅.
extends Node

const MATCH_LOADING_SCENE := "res://scenes/screen/match_loading_screen.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"
const SINGLE_PREPARE_SCENE := "res://scenes/screen/single_play_prepare_screen.tscn"
const ONLINE_PREPARE_SCENE := "res://scenes/screen/online_prepare_screen.tscn"

var active: GameSessionBase = null
## match_loading_screen이 소비할 카드 이름 (중복 제거됨).
var _pending_card_names: Array[String] = []
## match_loading_screen이 소비할 카드 id (중복 제거됨; names와 병렬).
var _pending_card_ids: Array[int] = []
## 온라인 준비 화면 등에서 한 번 보여줄 상태 문구 (덱 거부 등).
var pending_lobby_message: String = ""


## hub Node 자신 (세션이 tree 접근할 때 사용).
func get_hub() -> Node:
	return self


## pending_lobby_message를 읽고 비운다.
func take_pending_lobby_message() -> String:
	var msg := pending_lobby_message
	pending_lobby_message = ""
	return msg


## 싱글 플레이 세션 생성. deck_ids 비면 흑 기본 덱. rarities는 ids와 병렬(기본 N).
func start_local_single(
	player_deck_ids: Array[int] = [],
	opponent_deck_ids: Array[int] = [],
	player_deck_rarities: Array[int] = [],
	opponent_deck_rarities: Array[int] = [],
	player_deck_id: String = "",
	opponent_deck_id: String = ""
) -> void:
	var player_deck := player_deck_ids
	var opponent_deck := opponent_deck_ids
	if player_deck.is_empty():
		player_deck = CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
	if opponent_deck.is_empty():
		opponent_deck = CardRegistry.build_deck_ids_for_color(CardRegistry.DeckColor.BLACK)
	var session := LocalGameSession.new()
	session.setup(
		GameSessionBase.PlayMode.LOCAL_SINGLE,
		player_deck,
		opponent_deck,
		player_deck_rarities,
		opponent_deck_rarities,
		player_deck_id,
		opponent_deck_id
	)
	active = session


## LAN Host 세션 생성. deck_ids 비면 흑 기본 덱.
func start_host(
	deck_ids: Array[int] = [],
	deck_rarities: Array[int] = [],
	deck_id: String = ""
) -> void:
	var session := HostGameSession.new()
	session.setup(deck_ids, deck_rarities, deck_id)
	active = session


## 온라인 클라 세션 생성. deck_ids 비면 흑 기본 덱. rarities는 ids와 병렬.
func start_client(
	deck_ids: Array[int] = [],
	deck_rarities: Array[int] = [],
	deck_id: String = ""
) -> void:
	var session := ClientGameSession.new()
	session.setup(deck_ids, deck_rarities, deck_id)
	active = session


## Dedicated 권위 세션 생성.
func start_dedicated_server() -> void:
	var session := ServerAuthoritySession.new()
	session.setup()
	active = session


## 활성 세션. null이면 싱글 세션을 자동 생성(함정: 의도치 않은 싱글 폴백).
func get_active() -> GameSessionBase:
	if active == null:
		start_local_single()
	return active


## 활성 세션 해제. pending 로드 목록도 비운다.
func clear() -> void:
	active = null
	_pending_card_names.clear()
	_pending_card_ids.clear()


## 매치 종료 후 준비 화면으로 복귀. 온라인면 접속 종료 후 MenuHost를 다시 연다.
func return_to_main() -> void:
	var prepare_path := ""
	if active != null:
		match active.play_mode:
			GameSessionBase.PlayMode.LOCAL_SINGLE:
				prepare_path = SINGLE_PREPARE_SCENE
			GameSessionBase.PlayMode.ONLINE:
				prepare_path = ONLINE_PREPARE_SCENE
	var was_online := NetworkManager.is_online()
	if was_online:
		NetworkManager.disconnect_game()
		if prepare_path.is_empty():
			prepare_path = ONLINE_PREPARE_SCENE
	clear()
	MenuHost.open_root(get_tree(), prepare_path)


## game.tscn으로 전환 (로딩 완료 후·Dedicated 권위용).
func change_scene_to_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


## id 배열로 로딩 스코프를 설정한다 (씬 전환 없음). names는 ids→names 변환으로 파생.
func prepare_match_loading_ids(card_ids: Array[int]) -> void:
	_pending_card_ids = CardRegistry.unique_card_ids(card_ids)
	_pending_card_names = CardRegistry.ids_to_names(_pending_card_ids)


## 이름 배열로 로딩 스코프를 설정한다. 내부에서 ids로 변환 후 prepare_match_loading_ids에 위임.
func prepare_match_loading(card_names: Array[String]) -> void:
	prepare_match_loading_ids(CardRegistry.names_to_ids(card_names))


## 두 색 기본 덱 이름을 pending에 넣는다 (씬 전환 없음).
func prepare_match_loading_from_colors(
	color_a: CardRegistry.DeckColor,
	color_b: CardRegistry.DeckColor
) -> void:
	var merged: Array[int] = []
	merged.append_array(CardRegistry.build_deck_ids_for_color(color_a))
	merged.append_array(CardRegistry.build_deck_ids_for_color(color_b))
	prepare_match_loading_ids(merged)


## id 배열로 로딩 스코프를 설정하고 로딩 씬으로 이동한다.
func begin_match_loading_ids(card_ids: Array[int]) -> void:
	prepare_match_loading_ids(card_ids)
	get_tree().change_scene_to_file(MATCH_LOADING_SCENE)


## 이름 배열로 로딩 스코프를 설정하고 로딩 씬으로 이동한다.
func begin_match_loading(card_names: Array[String]) -> void:
	prepare_match_loading(card_names)
	get_tree().change_scene_to_file(MATCH_LOADING_SCENE)


## 두 색 덱을 합쳐 로딩 씬으로 이동한다.
func begin_match_loading_from_colors(
	color_a: CardRegistry.DeckColor,
	color_b: CardRegistry.DeckColor
) -> void:
	prepare_match_loading_from_colors(color_a, color_b)
	get_tree().change_scene_to_file(MATCH_LOADING_SCENE)


## 로딩 씬이 pending 이름을 꺼낸다. 호출 후 names만 비운다.
func take_pending_card_names() -> Array[String]:
	var names := _pending_card_names.duplicate()
	_pending_card_names.clear()
	return names


## 로딩 씬이 pending id를 꺼낸다. 호출 후 ids만 비운다.
func take_pending_card_ids() -> Array[int]:
	var ids := _pending_card_ids.duplicate()
	_pending_card_ids.clear()
	return ids


## NetworkManager peer 시그널 연결.
func _ready() -> void:
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)


## Host/Dedicated에 peer 입장 전달.
func _on_peer_joined(peer_id: int) -> void:
	if active is HostGameSession:
		(active as HostGameSession).on_client_joined(peer_id)
	elif active is ServerAuthoritySession:
		(active as ServerAuthoritySession).on_player_joined(peer_id)


## Dedicated에만 peer 퇴장(forfeit) 전달. Host LAN 종료는 NetworkManager 담당.
func _on_peer_left(peer_id: int) -> void:
	if active is ServerAuthoritySession:
		(active as ServerAuthoritySession).on_player_left(peer_id)
