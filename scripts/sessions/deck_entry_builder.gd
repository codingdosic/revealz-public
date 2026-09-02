class_name DeckEntryBuilder
extends RefCounted
## 온라인 권위(Host/Dedicated) 공용 덱 빌더.
## Host·Dedicated 엔트리 형식이 같고, seat별 색만 다르기 때문에 분리함 (B-OA-01/02).


## id(+선택 rarities) 배열을 셔플하고 {cardId, name, uuid, rarity} 엔트리로 만든다.
## uuid는 net_side별로 대역을 나눠 PLAYER/OPPONENT 충돌을 막는다.
static func build_shuffled_deck_entries_from_ids(
	net_side: GameConstants.Side,
	card_ids: Array[int],
	card_rarities: Array[int] = []
) -> Array:
	var pairs: Array = []
	for i in card_ids.size():
		var rarity := CardRarity.Tier.N
		if i < card_rarities.size():
			rarity = clampi(int(card_rarities[i]), CardRarity.Tier.N, CardRarity.Tier.UR)
		pairs.append({"cardId": card_ids[i], "rarity": rarity})
	pairs.shuffle()
	var entries: Array = []
	var counter := 0
	for pair in pairs:
		counter += 1
		var uuid := ((int(net_side) + 1) * 10000) + counter
		var cid := int(pair.get("cardId", 0))
		entries.append({
			"cardId": cid,
			"name": CardRegistry.id_to_name(cid),
			"uuid": uuid,
			"rarity": int(pair.get("rarity", CardRarity.Tier.N)),
		})
	return entries


## 이름(+선택 rarities) 배열을 셔플하고 {cardId, name, uuid, rarity} 엔트리로 만든다 (G3b).
## 내부에서 names→ids 변환 후 build_shuffled_deck_entries_from_ids에 위임한다.
static func build_shuffled_deck_entries_from_names(
	net_side: GameConstants.Side,
	card_names: Array[String],
	card_rarities: Array[int] = []
) -> Array:
	return build_shuffled_deck_entries_from_ids(
		net_side,
		CardRegistry.names_to_ids(card_names),
		card_rarities
	)


## 색상 덱 id를 셔플하고 {cardId, name, uuid, rarity} 엔트리 배열을 만든다.
static func build_shuffled_deck_entries(
	net_side: GameConstants.Side,
	color: CardRegistry.DeckColor
) -> Array:
	return build_shuffled_deck_entries_from_ids(
		net_side,
		CardRegistry.build_deck_ids_for_color(color)
	)


## id(+선택 rarities) 배열로 seat별 덱 엔트리를 만든다.
static func prepare_decks_from_ids(
	player_ids: Array[int],
	opponent_ids: Array[int],
	player_rarities: Array[int] = [],
	opponent_rarities: Array[int] = []
) -> Dictionary:
	return {
		int(GameConstants.Side.PLAYER): build_shuffled_deck_entries_from_ids(
			GameConstants.Side.PLAYER,
			player_ids,
			player_rarities
		),
		int(GameConstants.Side.OPPONENT): build_shuffled_deck_entries_from_ids(
			GameConstants.Side.OPPONENT,
			opponent_ids,
			opponent_rarities
		),
	}


## 이름(+선택 rarities) 배열로 seat별 덱 엔트리를 만든다 (G3b). 내부에서 ids 경로로 위임.
static func prepare_decks_from_names(
	player_names: Array[String],
	opponent_names: Array[String],
	player_rarities: Array[int] = [],
	opponent_rarities: Array[int] = []
) -> Dictionary:
	return prepare_decks_from_ids(
		CardRegistry.names_to_ids(player_names),
		CardRegistry.names_to_ids(opponent_names),
		player_rarities,
		opponent_rarities
	)


## 두 색 기본 덱 id로 seat별 덱 엔트리를 만든다.
static func prepare_decks_from_colors(
	player_color: CardRegistry.DeckColor,
	opponent_color: CardRegistry.DeckColor
) -> Dictionary:
	return prepare_decks_from_ids(
		CardRegistry.build_deck_ids_for_color(player_color),
		CardRegistry.build_deck_ids_for_color(opponent_color)
	)


## INTENT/RPC cardRarities Variant → Array[int]. PackedInt32Array·Array 모두 허용. length에 N 패딩.
static func parse_rarities(raw: Variant, length: int) -> Array[int]:
	var out: Array[int] = []
	if raw is PackedInt32Array:
		for v in raw as PackedInt32Array:
			out.append(clampi(int(v), CardRarity.Tier.N, CardRarity.Tier.UR))
	elif raw is Array:
		for item in raw as Array:
			out.append(clampi(int(item), CardRarity.Tier.N, CardRarity.Tier.UR))
	while out.size() < length:
		out.append(CardRarity.Tier.N)
	if out.size() > length:
		out.resize(length)
	return out


## INTENT/RPC cardIds Variant → Array[int]. PackedInt32Array·Array 모두 허용. <=0 스킵.
static func parse_card_ids(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if raw is PackedInt32Array:
		for v in raw as PackedInt32Array:
			if int(v) > 0:
				out.append(int(v))
	elif raw is Array:
		for item in raw as Array:
			var v := int(item)
			if v > 0:
				out.append(v)
	return out
