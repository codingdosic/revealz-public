class_name LocalGameSession
extends GameSessionBase

## side별 덱 id 배열.
var _player_deck_ids: Array[int] = []
var _opponent_deck_ids: Array[int] = []
var _player_deck_id: String = ""
var _opponent_deck_id: String = ""
## ids와 병렬 카피 등급 (기본 N).
var _player_deck_rarities: Array[int] = []
var _opponent_deck_rarities: Array[int] = []


## 로컬 세션 초기화. deck_ids 비면 opponent_ids를 player_ids로 복사.
func setup(
	mode: PlayMode,
	deck_ids: Array[int],
	opponent_deck_ids: Array[int] = [],
	deck_rarities: Array[int] = [],
	opponent_deck_rarities: Array[int] = [],
	player_deck_id: String = "",
	opponent_deck_id: String = ""
) -> void:
	play_mode = mode
	_player_deck_ids = deck_ids.duplicate()
	_player_deck_rarities = deck_rarities.duplicate()
	_player_deck_id = player_deck_id.strip_edges()
	_opponent_deck_id = opponent_deck_id.strip_edges()
	if opponent_deck_ids.is_empty():
		_opponent_deck_ids = deck_ids.duplicate()
		_opponent_deck_rarities = deck_rarities.duplicate()
	else:
		_opponent_deck_ids = opponent_deck_ids.duplicate()
		_opponent_deck_rarities = opponent_deck_rarities.duplicate()
	local_card_back_id = DeckStore.card_back_id_of(_player_deck_id) if not _player_deck_id.is_empty() else AccessoryCatalog.DEFAULT_CARD_BACK_ID
	opponent_card_back_id = DeckStore.card_back_id_of(_opponent_deck_id) if not _opponent_deck_id.is_empty() else AccessoryCatalog.DEFAULT_CARD_BACK_ID
	local_field_id = DeckStore.field_id_of(_player_deck_id) if not _player_deck_id.is_empty() else AccessoryCatalog.DEFAULT_FIELD_ID
	opponent_field_id = DeckStore.field_id_of(_opponent_deck_id) if not _opponent_deck_id.is_empty() else AccessoryCatalog.DEFAULT_FIELD_ID
	sync_local_display_name()
	set_default_opponent_display_name()


## side별 덱 id 배열을 반환한다.
func get_deck_ids_for_side(side: GameConstants.Side) -> Array[int]:
	if side == GameConstants.Side.PLAYER:
		return _player_deck_ids.duplicate()
	return _opponent_deck_ids.duplicate()


## side별 덱 이름 배열 (ids_to_names 파생; 호환 유지).
func get_deck_names_for_side(side: GameConstants.Side) -> Array[String]:
	return CardRegistry.ids_to_names(get_deck_ids_for_side(side))


## side별 카피 등급 배열을 반환한다.
func get_deck_rarities_for_side(side: GameConstants.Side) -> Array[int]:
	if side == GameConstants.Side.PLAYER:
		return _player_deck_rarities.duplicate()
	return _opponent_deck_rarities.duplicate()
