extends Node2D
class_name DeckZone

const CARD_DRAW_SPEED := 0.5

## Primary zone arrays store card ids (int); parallel arrays track uuid and rarity.
var deck: Array[int] = []
var _deck_uuids: Array[int] = []
var _deck_rarities: Array[int] = []
var graveyard: Array[int] = []
var _graveyard_uuids: Array[int] = []
var _graveyard_rarities: Array[int] = []
var banishzone: Array[int] = []
var _banish_uuids: Array[int] = []
var _banish_rarities: Array[int] = []
var life_cards: Array[int] = []
var _life_uuids: Array[int] = []
var _life_rarities: Array[int] = []
var hand_limit: int = GameConstants.DEFAULT_HAND_LIMIT

var owner_side: GameConstants.Side = GameConstants.Side.PLAYER


func _ready() -> void:
	pass


## Resolves a network entry dict to a card id; prefers cardId key, falls back to name_to_id.
func _resolve_entry_card_id(entry: Dictionary) -> int:
	var cid := int(entry.get("cardId", 0))
	if cid > 0:
		return cid
	return CardRegistry.name_to_id(String(entry.get("name", "")))


## Packs card id + tracking fields into a network entry dict with dual-write name.
func _pack_zone_entry(card_id: int, uuid: int, rarity: int) -> Dictionary:
	return {
		"cardId": card_id,
		"name": CardRegistry.id_to_name(card_id),
		"uuid": uuid,
		"rarity": rarity,
	}


## Extracts card id from a card node; prefers card_data.id, falls back to name_to_id.
func _card_id_of_node(card: Node) -> int:
	if card == null or not is_instance_valid(card):
		return 0
	var cd: CardData = card.get("card_data") as CardData
	if cd != null and cd.id > 0:
		return int(cd.id)
	var card_name: String = String(card.get("card_name"))
	return CardRegistry.name_to_id(card_name)


## Initialises a fresh match from a list of card ids; empty → build_default_deck_ids.
func init_match(deck_ids: Array[int] = [], deck_rarities: Array[int] = []) -> void:
	if deck_ids.is_empty():
		deck = CardRegistry.build_default_deck_ids()
	else:
		deck = deck_ids.duplicate()
	_deck_uuids.clear()
	for _i in deck.size():
		_deck_uuids.append(0)
	_deck_rarities = _normalize_rarities(deck_rarities, deck.size())
	_shuffle_deck_with_uuids()
	graveyard.clear()
	_graveyard_uuids.clear()
	_graveyard_rarities.clear()
	banishzone.clear()
	_banish_uuids.clear()
	_banish_rarities.clear()
	life_cards.clear()
	_life_uuids.clear()
	_life_rarities.clear()
	hand_limit = GameConstants.DEFAULT_HAND_LIMIT
	_update_deck_ui()


## Initialises match state from authoritative network entry dicts; skips id <= 0.
func init_match_from_entries(entries: Array) -> void:
	deck.clear()
	_deck_uuids.clear()
	_deck_rarities.clear()
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var cid: int = _resolve_entry_card_id(entry)
		if cid <= 0:
			continue
		deck.append(cid)
		_deck_uuids.append(int(entry.get("uuid", 0)))
		_deck_rarities.append(_clamp_rarity(int(entry.get("rarity", CardRarity.Tier.N))))
	graveyard.clear()
	_graveyard_uuids.clear()
	_graveyard_rarities.clear()
	banishzone.clear()
	_banish_uuids.clear()
	_banish_rarities.clear()
	life_cards.clear()
	_life_uuids.clear()
	_life_rarities.clear()
	hand_limit = GameConstants.DEFAULT_HAND_LIMIT
	_update_deck_ui()


## 라이프 3장 제거 직후 덱 맨 위(첫 드로우)에 오도록 카드 1장을 고정한다.
func pin_card_after_life(card_id: int) -> void:
	var idx := deck.find(card_id)
	if idx < 0:
		return
	var rarity := _take_rarity_at(_deck_rarities, idx)
	var uuid := _take_uuid_at(_deck_uuids, idx)
	deck.remove_at(idx)
	var insert_at := GameConstants.LIFE_START_COUNT
	deck.insert(insert_at, card_id)
	_insert_uuid_at(_deck_uuids, insert_at, uuid)
	_insert_rarity_at(_deck_rarities, insert_at, rarity)


## Moves the top count cards of the deck into life_cards; returns ids taken.
func take_cards_to_life(count: int) -> Array[int]:
	var taken: Array[int] = []
	for i in range(count):
		if deck.is_empty():
			break
		var card_id := deck[0]
		var card_uuid := _pop_front_int(_deck_uuids, 0)
		var card_rarity := _pop_front_int(_deck_rarities, CardRarity.Tier.N)
		deck.remove_at(0)
		life_cards.append(card_id)
		_life_uuids.append(card_uuid)
		_life_rarities.append(card_rarity)
		taken.append(card_id)
	_update_deck_ui()
	return taken


## Returns the number of remaining life cards.
func get_life_count() -> int:
	return life_cards.size()


## Pops the first life card into the hand pool; returns a full zone entry dict.
func pop_life_card_for_hand() -> Dictionary:
	if life_cards.is_empty():
		return {}
	var card_id: int = life_cards[0]
	life_cards.remove_at(0)
	var card_uuid := _pop_front_int(_life_uuids, 0)
	var card_rarity := _pop_front_int(_life_rarities, CardRarity.Tier.N)
	hand_limit += 1
	return _pack_zone_entry(card_id, card_uuid, card_rarity)


## Convenience wrapper: pops life card and returns the card name string for UI.
func transfer_life_to_hand() -> String:
	return String(pop_life_card_for_hand().get("name", ""))


## Pushes a card id into the life zone with optional tracking fields.
func push_card_to_life(card_id: int, uuid: int = 0, rarity: int = CardRarity.Tier.N) -> void:
	life_cards.append(card_id)
	_life_uuids.append(uuid)
	_life_rarities.append(_clamp_rarity(rarity))


## Clean-phase bulk send; converts names → ids. Not for effect salvage/reborn paths.
func send_to_graveyard(card_names: Array) -> void:
	for card_name in card_names:
		var cid := CardRegistry.name_to_id(String(card_name))
		send_card_to_graveyard(cid, 0)


## Adds a card id to the graveyard zone; no-op when card_id <= 0.
func send_card_to_graveyard(card_id: int, uuid: int = 0, rarity: int = CardRarity.Tier.N) -> void:
	if card_id <= 0:
		return
	graveyard.append(card_id)
	_graveyard_uuids.append(uuid)
	_graveyard_rarities.append(_clamp_rarity(rarity))


## 덱 맨 아래(드로우 최후순)에 카드 추가 — Clean 페이즈 스택 회수 등
func send_card_to_deck_bottom(card_id: int, uuid: int = 0, rarity: int = CardRarity.Tier.N) -> void:
	if card_id <= 0:
		return
	deck.append(card_id)
	_deck_uuids.append(uuid)
	_deck_rarities.append(_clamp_rarity(rarity))
	_update_deck_ui()


## Adds a card id to the banish zone; no-op when card_id <= 0.
func send_card_to_banishzone(card_id: int, uuid: int = 0, rarity: int = CardRarity.Tier.N) -> void:
	if card_id <= 0:
		return
	banishzone.append(card_id)
	_banish_uuids.append(uuid)
	_banish_rarities.append(_clamp_rarity(rarity))


## Returns the first banish index matching the given uuid, or -1.
func find_banish_index_by_uuid(uuid: int) -> int:
	if uuid <= 0:
		return -1
	for i in _banish_uuids.size():
		if _banish_uuids[i] == uuid:
			return i
	return -1


## Removes a card from the banish zone by uuid; returns true on success.
func remove_from_banishzone_by_uuid(uuid: int) -> bool:
	var idx := find_banish_index_by_uuid(uuid)
	if idx < 0:
		return false
	banishzone.remove_at(idx)
	_banish_uuids.remove_at(idx)
	if idx < _banish_rarities.size():
		_banish_rarities.remove_at(idx)
	return true


## Returns the first graveyard index matching the given uuid, or -1.
func find_graveyard_index_by_uuid(uuid: int) -> int:
	if uuid <= 0:
		return -1
	for i in _graveyard_uuids.size():
		if _graveyard_uuids[i] == uuid:
			return i
	return -1


## Removes a card from the graveyard by uuid; returns true on success.
func remove_from_graveyard_by_uuid(uuid: int) -> bool:
	var idx := find_graveyard_index_by_uuid(uuid)
	if idx < 0:
		return false
	graveyard.remove_at(idx)
	_graveyard_uuids.remove_at(idx)
	if idx < _graveyard_rarities.size():
		_graveyard_rarities.remove_at(idx)
	return true


## Draws until hand_limit; returns a result dict with drawn entries, steps, and zone snapshots.
func draw_to_hand_limit(current_hand_size: int, reveal_on_draw: bool = true) -> Dictionary:
	var result := {
		"drawn_names": [] as Array[String],
		"drawn_entries": [] as Array,
		"graveyard_shuffles": 0,
		"life_transfers": [] as Array[String],
		"steps": [] as Array,
	}

	if current_hand_size >= hand_limit:
		result["hand_limit"] = hand_limit
		result["start_hand_size"] = current_hand_size
		result["hand_entries"] = _pack_hand_entries()
		result["deck_remaining"] = _pack_deck_remaining()
		result["graveyard_remaining"] = _pack_graveyard_remaining()
		result["banish_remaining"] = _pack_banishzone_remaining()
		result["life_remaining"] = _pack_life_remaining()
		return result

	result["start_hand_size"] = current_hand_size

	while _get_hand_size() < hand_limit:
		if deck.is_empty():
			if graveyard.is_empty():
				break
			_shuffle_graveyard_into_deck()
			result.graveyard_shuffles += 1
			result.steps.append({"type": "graveyard_shuffle"})
			var life_pop := pop_life_card_for_hand()
			var life_id := int(life_pop.get("cardId", 0))
			var life_name := String(life_pop.get("name", ""))
			if life_id > 0:
				var life_uuid := int(life_pop.get("uuid", 0))
				var life_rarity := int(life_pop.get("rarity", CardRarity.Tier.N))
				result.life_transfers.append(life_name)
				result.steps.append({
					"type": "life",
					"cardId": life_id,
					"name": life_name,
					"uuid": life_uuid,
					"rarity": life_rarity,
				})
				_spawn_card_to_hand(life_id, reveal_on_draw, life_uuid, life_rarity, true)
			continue

		var drawn := _draw_single_card_name()
		var drawn_id := int(drawn.get("cardId", 0))
		var drawn_name := String(drawn.get("name", ""))
		result.drawn_names.append(drawn_name)
		result.drawn_entries.append(drawn)
		result.steps.append({
			"type": "draw",
			"cardId": drawn_id,
			"name": drawn_name,
			"uuid": int(drawn.get("uuid", 0)),
			"rarity": int(drawn.get("rarity", CardRarity.Tier.N)),
		})
		_spawn_card_to_hand(drawn_id, reveal_on_draw, int(drawn.get("uuid", 0)), int(drawn.get("rarity", CardRarity.Tier.N)))

	result["hand_limit"] = hand_limit
	result["hand_entries"] = _pack_hand_entries()
	result["deck_remaining"] = _pack_deck_remaining()
	result["graveyard_remaining"] = _pack_graveyard_remaining()
	result["banish_remaining"] = _pack_banishzone_remaining()
	result["life_remaining"] = _pack_life_remaining()
	_update_deck_ui()
	return result


## Primary card spawner: creates a card node from a card id and adds it to card_manager.
func spawn_card_by_id(
	card_id: int,
	reveal_on_draw: bool = true,
	uuid: int = 0,
	rarity: int = CardRarity.Tier.N
) -> Node2D:
	return _create_card_instance(card_id, reveal_on_draw, uuid, false, rarity)


## Name-keyed wrapper for spawn_card_by_id; resolves name → id then delegates.
func spawn_card_by_name(
	card_name: String,
	reveal_on_draw: bool = true,
	uuid: int = 0,
	rarity: int = CardRarity.Tier.N
) -> Node2D:
	var cid := CardRegistry.name_to_id(card_name)
	if cid <= 0:
		push_error("DeckZone.spawn_card_by_name: unknown card '%s'" % card_name)
		return null
	return spawn_card_by_id(cid, reveal_on_draw, uuid, rarity)


## Spawns a face-down card node; thin wrapper over _create_card_instance via name.
func spawn_hidden_card(card_name: String, uuid: int, rarity: int = CardRarity.Tier.N) -> Node2D:
	var cid := CardRegistry.name_to_id(card_name)
	if cid <= 0:
		push_error("DeckZone.spawn_hidden_card: unknown card '%s'" % card_name)
		return null
	return _create_card_instance(cid, false, uuid, true, rarity)


## Finds life_card_id in life_cards, removes it, and returns a full zone entry dict.
func consume_life_card_for_hand(life_card_id: int) -> Dictionary:
	if life_card_id <= 0 or life_cards.is_empty():
		return {}
	var idx := 0
	if life_cards[0] != life_card_id:
		idx = life_cards.find(life_card_id)
		if idx < 0:
			return {}
	var card_uuid := _life_uuids[idx] if idx < _life_uuids.size() else 0
	var card_rarity := _life_rarities[idx] if idx < _life_rarities.size() else CardRarity.Tier.N
	life_cards.remove_at(idx)
	if idx < _life_uuids.size():
		_life_uuids.remove_at(idx)
	if idx < _life_rarities.size():
		_life_rarities.remove_at(idx)
	return _pack_zone_entry(life_card_id, card_uuid, card_rarity)


## Applies an authoritative draw-state packet to reconcile local hand/zone state.
func apply_network_draw_state(packet: Dictionary, reveal_on_draw: bool) -> void:
	if packet.has("hand_limit"):
		hand_limit = int(packet.get("hand_limit", hand_limit))

	if packet.has("hand_entries"):
		_sync_hand_to_authoritative_entries(packet.get("hand_entries", []), reveal_on_draw)
	elif packet.has("drawn_entries") or packet.has("life_transfers"):
		if packet.has("start_hand_size"):
			_reconcile_hand_to_start_size(int(packet.get("start_hand_size", 0)))

		for life_name in packet.get("life_transfers", []):
			var life_id: int = CardRegistry.name_to_id(String(life_name))
			_try_spawn_draw_card(String(life_name), 0, reveal_on_draw, true, CardRarity.Tier.N, life_id)
		for raw_entry in packet.get("drawn_entries", []):
			if not (raw_entry is Dictionary):
				continue
			var entry: Dictionary = raw_entry
			var eid: int = _resolve_entry_card_id(entry)
			_try_spawn_draw_card(
				String(entry.get("name", "")),
				int(entry.get("uuid", 0)),
				reveal_on_draw,
				false,
				int(entry.get("rarity", CardRarity.Tier.N)),
				eid
			)
	elif not packet.get("steps", []).is_empty():
		if packet.has("start_hand_size"):
			_reconcile_hand_to_start_size(int(packet.get("start_hand_size", 0)))
		_apply_draw_steps(packet.get("steps", []), reveal_on_draw)

	if packet.has("deck_remaining"):
		_apply_deck_remaining(packet.get("deck_remaining", []))

	if packet.has("graveyard_remaining"):
		_apply_graveyard_remaining(packet.get("graveyard_remaining", []))

	if packet.has("banish_remaining"):
		_apply_banishzone_remaining(packet.get("banish_remaining", []))

	if packet.has("life_remaining"):
		_apply_life_remaining(packet.get("life_remaining", []))

	_trim_hand_to_limit()
	_update_deck_ui()


## Spawns a draw card from name/id; if is_life consumes from life_cards first.
func _try_spawn_draw_card(
	card_name: String,
	uuid: int,
	reveal_on_draw: bool,
	is_life: bool,
	rarity: int = CardRarity.Tier.N,
	card_id: int = 0
) -> void:
	if _get_hand_size() >= hand_limit:
		return
	var resolved_id := card_id if card_id > 0 else CardRegistry.name_to_id(card_name)
	if resolved_id <= 0:
		return
	var spawn_uuid := uuid
	var spawn_rarity := rarity
	if is_life:
		var consumed := consume_life_card_for_hand(resolved_id)
		if consumed.is_empty():
			return
		spawn_uuid = int(consumed.get("uuid", 0))
		spawn_rarity = int(consumed.get("rarity", CardRarity.Tier.N))
	elif _hand_has_uuid_or_id(resolved_id, uuid):
		return
	_spawn_card_to_hand(resolved_id, reveal_on_draw, spawn_uuid, spawn_rarity, is_life)


## Applies ordered draw step entries (graveyard_shuffle / life / draw) to local state.
func _apply_draw_steps(steps: Array, reveal_on_draw: bool) -> void:
	for raw_step in steps:
		if not (raw_step is Dictionary):
			continue
		var step: Dictionary = raw_step
		match String(step.get("type", "")):
			"graveyard_shuffle":
				pass
			"life":
				var life_eid: int = _resolve_entry_card_id(step)
				_try_spawn_draw_card(
					String(step.get("name", "")),
					0,
					reveal_on_draw,
					true,
					int(step.get("rarity", CardRarity.Tier.N)),
					life_eid
				)
			"draw":
				var draw_eid: int = _resolve_entry_card_id(step)
				_try_spawn_draw_card(
					String(step.get("name", "")),
					int(step.get("uuid", 0)),
					reveal_on_draw,
					false,
					int(step.get("rarity", CardRarity.Tier.N)),
					draw_eid
				)


## Overwrites the graveyard zone from a snapshot; prunes and restores presenter nodes.
func _apply_graveyard_remaining(items: Array) -> void:
	graveyard.clear()
	_graveyard_uuids.clear()
	_graveyard_rarities.clear()
	for item in items:
		if item is Dictionary:
			var entry: Dictionary = item
			var cid: int = _resolve_entry_card_id(entry)
			if cid <= 0:
				continue
			graveyard.append(cid)
			_graveyard_uuids.append(int(entry.get("uuid", 0)))
			_graveyard_rarities.append(_clamp_rarity(int(entry.get("rarity", CardRarity.Tier.N))))
		else:
			var name_cid: int = CardRegistry.name_to_id(String(item))
			if name_cid <= 0:
				continue
			graveyard.append(name_cid)
			_graveyard_uuids.append(0)
			_graveyard_rarities.append(CardRarity.Tier.N)
	if graveyard.is_empty():
		_clear_graveyard_presenter()
	else:
		_prune_graveyard_presenter_to_names()
	ensure_graveyard_presenter_nodes()


## 묘지 리스트 SSOT에 맞춰 presenter 노드를 보충한다. ZONE_SNAPSHOT 적용 후 호출.
func ensure_graveyard_presenter_nodes() -> void:
	var ctx := get_effect_context()
	if ctx == null:
		return
	var side := owner_side
	for i in graveyard.size():
		var card_id := graveyard[i]
		if card_id <= 0:
			continue
		var uuid := _graveyard_uuids[i] if i < _graveyard_uuids.size() else 0
		var card_name := CardRegistry.id_to_name(card_id)
		if _presenter_has_graveyard_entry(ctx, side, uuid, card_name):
			continue
		var rarity := _graveyard_rarities[i] if i < _graveyard_rarities.size() else CardRarity.Tier.N
		var card := spawn_card_by_id(card_id, false, uuid, rarity)
		if card == null:
			continue
		# 동기화 복원 — 이동 연출 없이 즉시 묘지 등록
		ctx.move_to_graveyard(card, side, true, true, false)


## Overwrites the banish zone from a snapshot; prunes and restores presenter nodes.
func _apply_banishzone_remaining(items: Array) -> void:
	banishzone.clear()
	_banish_uuids.clear()
	_banish_rarities.clear()
	for item in items:
		if item is Dictionary:
			var entry: Dictionary = item
			var cid: int = _resolve_entry_card_id(entry)
			if cid <= 0:
				continue
			banishzone.append(cid)
			_banish_uuids.append(int(entry.get("uuid", 0)))
			_banish_rarities.append(_clamp_rarity(int(entry.get("rarity", CardRarity.Tier.N))))
		else:
			var name_cid: int = CardRegistry.name_to_id(String(item))
			if name_cid <= 0:
				continue
			banishzone.append(name_cid)
			_banish_uuids.append(0)
			_banish_rarities.append(CardRarity.Tier.N)
	if banishzone.is_empty():
		_clear_banishzone_presenter()
	else:
		_prune_banishzone_presenter_to_names()
	ensure_banishzone_presenter_nodes()


## 밴시 리스트 SSOT에 맞춰 presenter 노드를 보충한다.
func ensure_banishzone_presenter_nodes() -> void:
	var ctx := get_effect_context()
	if ctx == null:
		return
	var side := owner_side
	for i in banishzone.size():
		var card_id := banishzone[i]
		if card_id <= 0:
			continue
		var uuid := _banish_uuids[i] if i < _banish_uuids.size() else 0
		var card_name := CardRegistry.id_to_name(card_id)
		if _presenter_has_banish_entry(ctx, side, uuid, card_name):
			continue
		var rarity := _banish_rarities[i] if i < _banish_rarities.size() else CardRarity.Tier.N
		var card := spawn_card_by_id(card_id, false, uuid, rarity)
		if card == null:
			continue
		# 동기화 복원 — 이동 연출 없이 즉시 제외 등록
		ctx.move_to_banishzone(card, side, false, false)


## Checks whether a banish presenter node already exists by uuid (primary) or name (fallback).
func _presenter_has_banish_entry(
	ctx: EffectContext,
	side: GameConstants.Side,
	uuid: int,
	card_name: String
) -> bool:
	for existing in ctx.banishzone_nodes[side]:
		if not is_instance_valid(existing):
			continue
		if uuid > 0 and int(existing.network_uuid) == uuid:
			return true
		if uuid <= 0 and String(existing.card_name) == card_name:
			return true
	return false


## Checks whether a graveyard presenter node already exists by uuid (primary) or name (fallback).
func _presenter_has_graveyard_entry(
	ctx: EffectContext,
	side: GameConstants.Side,
	uuid: int,
	card_name: String
) -> bool:
	for existing in ctx.graveyard_nodes[side]:
		if not is_instance_valid(existing):
			continue
		if uuid > 0 and int(existing.network_uuid) == uuid:
			return true
		if uuid <= 0 and String(existing.card_name) == card_name:
			return true
	return false


## Removes excess hand cards until the hand is at target_size.
func _reconcile_hand_to_start_size(target_size: int) -> void:
	var hand := get_hand_manager()
	while hand.get_hand_size() > target_size:
		var cards: Array = hand.get_hand_cards()
		if cards.is_empty():
			break
		var excess: Node = cards[cards.size() - 1]
		hand.remove_card_from_hand(excess)
		if is_instance_valid(excess):
			excess.queue_free()


## Packs current hand cards into entry dicts with dual cardId+name write.
func _pack_hand_entries() -> Array:
	var entries: Array = []
	for card in get_hand_manager().get_hand_cards():
		if card == null or not is_instance_valid(card):
			continue
		var cid := _card_id_of_node(card)
		entries.append({
			"cardId": cid,
			"name": String(card.card_name),
			"uuid": int(card.network_uuid),
			"rarity": int(card.get("instance_rarity") if card.get("instance_rarity") != null else CardRarity.Tier.N),
		})
	return entries


## Packs life zone into entry dicts with dual cardId+name write.
func _pack_life_remaining() -> Array:
	var entries: Array = []
	for i in life_cards.size():
		entries.append(_pack_zone_entry(
			life_cards[i],
			_life_uuids[i] if i < _life_uuids.size() else 0,
			_life_rarities[i] if i < _life_rarities.size() else CardRarity.Tier.N
		))
	return entries


## Packs graveyard zone into entry dicts with dual cardId+name write.
func _pack_graveyard_remaining() -> Array:
	var entries: Array = []
	for i in graveyard.size():
		entries.append(_pack_zone_entry(
			graveyard[i],
			_graveyard_uuids[i] if i < _graveyard_uuids.size() else 0,
			_graveyard_rarities[i] if i < _graveyard_rarities.size() else CardRarity.Tier.N
		))
	return entries


## Packs banish zone into entry dicts with dual cardId+name write.
func _pack_banishzone_remaining() -> Array:
	var entries: Array = []
	for i in banishzone.size():
		entries.append(_pack_zone_entry(
			banishzone[i],
			_banish_uuids[i] if i < _banish_uuids.size() else 0,
			_banish_rarities[i] if i < _banish_rarities.size() else CardRarity.Tier.N
		))
	return entries


## Reconciles the hand to an authoritative entry list, spawning/removing nodes as needed.
func _sync_hand_to_authoritative_entries(entries: Array, reveal_on_draw: bool) -> void:
	var hand := get_hand_manager()
	var want_by_uuid: Dictionary = {}
	var want_zero: Array = []

	for raw in entries:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var cid: int = _resolve_entry_card_id(entry)
		var uuid: int = int(entry.get("uuid", 0))
		var rarity: int = _clamp_rarity(int(entry.get("rarity", CardRarity.Tier.N)))
		if cid <= 0:
			continue
		if uuid > 0:
			want_by_uuid[uuid] = {"cardId": cid, "rarity": rarity}
		else:
			want_zero.append({"cardId": cid, "rarity": rarity})

	var unmatched_hand: Array = []
	for card in hand.get_hand_cards().duplicate():
		if card == null or not is_instance_valid(card):
			continue
		var matched := false
		if card.network_uuid > 0 and want_by_uuid.has(card.network_uuid):
			var want: Dictionary = want_by_uuid[card.network_uuid]
			if _card_id_of_node(card) == int(want.get("cardId", 0)):
				want_by_uuid.erase(card.network_uuid)
				matched = true
		elif card.network_uuid <= 0:
			var node_id := _card_id_of_node(card)
			for zi in want_zero.size():
				if int(want_zero[zi].get("cardId", 0)) == node_id:
					want_zero.remove_at(zi)
					matched = true
					break
		if not matched:
			unmatched_hand.append(card)

	for card in unmatched_hand:
		hand.remove_card_from_hand(card)
		card.queue_free()

	for uuid in want_by_uuid:
		var want: Dictionary = want_by_uuid[uuid]
		_spawn_card_to_hand(int(want.get("cardId", 0)), reveal_on_draw, int(uuid), int(want.get("rarity", CardRarity.Tier.N)))
	for item in want_zero:
		_spawn_card_to_hand(int(item.get("cardId", 0)), reveal_on_draw, 0, int(item.get("rarity", CardRarity.Tier.N)))


## Removes excess hand nodes beyond hand_limit.
func _trim_hand_to_limit() -> void:
	var hand := get_hand_manager()
	while hand.get_hand_size() > hand_limit:
		var cards: Array = hand.get_hand_cards()
		if cards.is_empty():
			break
		var excess: Node = cards[cards.size() - 1]
		hand.remove_card_from_hand(excess)
		if is_instance_valid(excess):
			excess.queue_free()


## Overwrites life zone from a snapshot array.
func _apply_life_remaining(items: Array) -> void:
	life_cards.clear()
	_life_uuids.clear()
	_life_rarities.clear()
	for item in items:
		if item is Dictionary:
			var entry: Dictionary = item
			var cid: int = _resolve_entry_card_id(entry)
			if cid <= 0:
				continue
			life_cards.append(cid)
			_life_uuids.append(int(entry.get("uuid", 0)))
			_life_rarities.append(_clamp_rarity(int(entry.get("rarity", CardRarity.Tier.N))))
		else:
			var name_cid: int = CardRegistry.name_to_id(String(item))
			if name_cid <= 0:
				continue
			life_cards.append(name_cid)
			_life_uuids.append(0)
			_life_rarities.append(CardRarity.Tier.N)


## 묘지 presenter 노드를 전부 비운다.
func _clear_graveyard_presenter() -> void:
	var ctx := get_effect_context()
	if ctx:
		ctx.clear_graveyard_nodes(owner_side)


## 묘지 리스트에 없는 presenter 노드를 제거·정리한다 (uuid → id → name 순 매칭).
func _prune_graveyard_presenter_to_names() -> void:
	var ctx := get_effect_context()
	if ctx == null:
		return
	var side := owner_side
	var kept: Array = []
	var unmatched_ids: Array[int] = graveyard.duplicate()
	for card in ctx.graveyard_nodes[side]:
		if not is_instance_valid(card):
			continue
		var uuid := int(card.get("network_uuid"))
		if uuid > 0:
			var idx := find_graveyard_index_by_uuid(uuid)
			if idx >= 0 and _card_id_of_node(card) == graveyard[idx]:
				kept.append(card)
				unmatched_ids.erase(graveyard[idx])
				continue
		var node_id := _card_id_of_node(card)
		var name_idx := unmatched_ids.find(node_id)
		if name_idx >= 0:
			kept.append(card)
			unmatched_ids.remove_at(name_idx)
		else:
			card.queue_free()
	ctx.graveyard_nodes[side] = kept
	if ctx.effect_manager and ctx.effect_manager.has_method("notify_graveyard_changed"):
		ctx.effect_manager.notify_graveyard_changed(side)


## 밴시 presenter 노드를 전부 비운다.
func _clear_banishzone_presenter() -> void:
	var ctx := get_effect_context()
	if ctx:
		ctx.clear_banishzone_nodes(owner_side)


## 밴시 리스트에 없는 presenter 노드를 제거·정리한다 (uuid → id → name 순 매칭).
func _prune_banishzone_presenter_to_names() -> void:
	var ctx := get_effect_context()
	if ctx == null:
		return
	var side := owner_side
	var kept: Array = []
	var unmatched_ids: Array[int] = banishzone.duplicate()
	for card in ctx.banishzone_nodes[side]:
		if not is_instance_valid(card):
			continue
		var uuid := int(card.get("network_uuid"))
		if uuid > 0:
			var idx := find_banish_index_by_uuid(uuid)
			if idx >= 0 and _card_id_of_node(card) == banishzone[idx]:
				kept.append(card)
				unmatched_ids.erase(banishzone[idx])
				continue
		var node_id := _card_id_of_node(card)
		var name_idx := unmatched_ids.find(node_id)
		if name_idx >= 0:
			kept.append(card)
			unmatched_ids.remove_at(name_idx)
		else:
			card.queue_free()
	ctx.banishzone_nodes[side] = kept


## Checks if hand already contains a card by uuid (primary) or card id when uuid == 0.
func _hand_has_uuid_or_id(card_id: int, uuid: int) -> bool:
	for card in get_hand_manager().get_hand_cards():
		if uuid > 0 and card.network_uuid == uuid:
			return true
		if card_id > 0 and uuid <= 0 and _card_id_of_node(card) == card_id:
			return true
	return false


## Packs deck zone into entry dicts with dual cardId+name write.
func _pack_deck_remaining() -> Array:
	var entries: Array = []
	for i in deck.size():
		entries.append(_pack_zone_entry(
			deck[i],
			_deck_uuids[i] if i < _deck_uuids.size() else 0,
			_deck_rarities[i] if i < _deck_rarities.size() else CardRarity.Tier.N
		))
	return entries


## Overwrites the deck zone from a snapshot array using _resolve_entry_card_id.
func _apply_deck_remaining(entries: Array) -> void:
	deck.clear()
	_deck_uuids.clear()
	_deck_rarities.clear()
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var cid: int = _resolve_entry_card_id(entry)
		if cid <= 0:
			continue
		deck.append(cid)
		_deck_uuids.append(int(entry.get("uuid", 0)))
		_deck_rarities.append(_clamp_rarity(int(entry.get("rarity", CardRarity.Tier.N))))


## Spawns drawn cards to hand from an authoritative entries array, removing them from deck.
func sync_draw_from_entries(entries: Array, reveal_on_draw: bool) -> void:
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var cid: int = _resolve_entry_card_id(entry)
		var uuid: int = int(entry.get("uuid", 0))
		var rarity: int = _clamp_rarity(int(entry.get("rarity", CardRarity.Tier.N)))
		if deck.is_empty():
			break
		deck.remove_at(0)
		_pop_front_int(_deck_uuids, 0)
		_pop_front_int(_deck_rarities, CardRarity.Tier.N)
		if cid <= 0:
			push_warning("DeckZone: sync_draw missing card id for uuid %d" % uuid)
			continue
		_spawn_card_to_hand(cid, reveal_on_draw, uuid, rarity)
	_update_deck_ui()


## Pops count cards from deck top as hidden (opponent-side) hand nodes.
func sync_hidden_draws(count: int) -> void:
	for _i in range(count):
		if deck.is_empty():
			break
		var card_id := deck[0]
		var uuid := _pop_front_int(_deck_uuids, 0)
		var rarity := _pop_front_int(_deck_rarities, CardRarity.Tier.N)
		deck.remove_at(0)
		_spawn_hidden_card_to_hand(card_id, uuid, rarity)
	_update_deck_ui()


## Pops the top deck card; returns a full zone entry dict {cardId, name, uuid, rarity}.
func _draw_single_card_name() -> Dictionary:
	var card_id := deck[0]
	deck.remove_at(0)
	var uuid := _pop_front_int(_deck_uuids, 0)
	var rarity := _pop_front_int(_deck_rarities, CardRarity.Tier.N)
	return _pack_zone_entry(card_id, uuid, rarity)


## Moves all graveyard cards into the deck and shuffles.
func _shuffle_graveyard_into_deck() -> void:
	if not graveyard.is_empty():
		_clear_graveyard_presenter()
	for i in graveyard.size():
		deck.append(graveyard[i])
		_deck_uuids.append(_graveyard_uuids[i] if i < _graveyard_uuids.size() else 0)
		_deck_rarities.append(
			_graveyard_rarities[i] if i < _graveyard_rarities.size() else CardRarity.Tier.N
		)
	graveyard.clear()
	_graveyard_uuids.clear()
	_graveyard_rarities.clear()
	_shuffle_deck_with_uuids()


## Shuffles deck in-place preserving uuid/rarity parallel arrays; uses cardId key in pairs.
func _shuffle_deck_with_uuids() -> void:
	var pairs: Array = []
	for i in deck.size():
		pairs.append({
			"cardId": deck[i],
			"uuid": _deck_uuids[i] if i < _deck_uuids.size() else 0,
			"rarity": _deck_rarities[i] if i < _deck_rarities.size() else CardRarity.Tier.N,
		})
	pairs.shuffle()
	deck.clear()
	_deck_uuids.clear()
	_deck_rarities.clear()
	for pair in pairs:
		deck.append(int(pair.get("cardId", 0)))
		_deck_uuids.append(int(pair.get("uuid", 0)))
		_deck_rarities.append(_clamp_rarity(int(pair.get("rarity", CardRarity.Tier.N))))


## Updates deck counter sprite/label visibility based on current deck size.
func _update_deck_ui() -> void:
	_apply_deck_pile_texture()
	if has_node("RichTextLabel"):
		$RichTextLabel.text = str(deck.size())
	if deck.is_empty():
		if has_node("Area2D/CollisionShape2D"):
			$Area2D/CollisionShape2D.disabled = true
		if has_node("Sprite2D"):
			$Sprite2D.visible = false
		if has_node("RichTextLabel"):
			$RichTextLabel.visible = false
	else:
		if has_node("Area2D/CollisionShape2D"):
			$Area2D/CollisionShape2D.disabled = false
		if has_node("Sprite2D"):
			$Sprite2D.visible = true
		if has_node("RichTextLabel"):
			$RichTextLabel.visible = true


## 덱 더미(Sprite2D)에 owner_side별 카드 뒷면 텍스처를 적용한다.
func _apply_deck_pile_texture() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	sprite.texture = AccessoryRuntime.card_back_texture(
		AccessoryRuntime.card_back_id_for_owner_side(owner_side)
	)


## Creates a card node from a card id using get_by_id; asset path still uses data.card_name.
func _create_card_instance(
	card_id: int,
	reveal_on_draw: bool,
	uuid: int = 0,
	force_hidden: bool = false,
	rarity: int = CardRarity.Tier.N
) -> Node2D:
	var data: CardData = CardRegistry.get_by_id(card_id)
	if data == null:
		push_error("DeckZone: unknown card id %d" % card_id)
		return null

	var new_card: Node2D = get_card_scene().instantiate()
	new_card.init_from_data(data, owner_side, "", uuid, rarity)

	AccessoryRuntime.apply_card_back(
		new_card,
		AccessoryRuntime.card_back_id_for_owner_side(owner_side)
	)

	if not data.illustration:
		var card_image_path := "res://assets/Black/%s.png" % data.card_name
		if new_card.has_node("CardImage"):
			new_card.get_node("CardImage").texture = load(card_image_path)

	new_card.name = "Card"
	get_card_manager().add_child(new_card)
	_connect_effect_signals(new_card)

	if reveal_on_draw:
		if owner_side == GameConstants.Side.OPPONENT or force_hidden:
			new_card.apply_hand_hidden()
		else:
			new_card.apply_hand_visual()
	elif owner_side == GameConstants.Side.OPPONENT or force_hidden:
		new_card.apply_hand_hidden()
	else:
		new_card.apply_hand_visual()

	return new_card


## Connects effect click signal of a card node to the EffectManager.
func _connect_effect_signals(card: Node2D) -> void:
	var em := get_effect_manager()
	if em and card.has_signal("card_clicked"):
		if not card.card_clicked.is_connected(em.on_card_clicked):
			card.card_clicked.connect(em.on_card_clicked)


## Public entry point to (re-)wire effect click signal on an existing card node.
func ensure_effect_click_connection(card: Node2D) -> void:
	_connect_effect_signals(card)


## Spawns a card by id and adds it to hand at CARD_DRAW_SPEED.
func _spawn_card_to_hand(
	card_id: int,
	reveal_on_draw: bool,
	uuid: int = 0,
	rarity: int = CardRarity.Tier.N,
	from_life: bool = false
) -> void:
	var new_card := _create_card_instance(card_id, reveal_on_draw, uuid, false, rarity)
	if new_card:
		if from_life:
			_place_card_at_life_for_hand_fx(new_card)
		else:
			_place_card_at_deck_for_draw_fx(new_card)
		get_hand_manager().add_card_to_hand(new_card, CARD_DRAW_SPEED)


## Spawns a hidden (face-down) card by id and adds it to hand.
func _spawn_hidden_card_to_hand(
	card_id: int,
	uuid: int,
	rarity: int = CardRarity.Tier.N
) -> void:
	var new_card := _create_card_instance(card_id, false, uuid, true, rarity)
	if new_card:
		_place_card_at_deck_for_draw_fx(new_card)
		get_hand_manager().add_card_to_hand(new_card, CARD_DRAW_SPEED)


## 드로우 연출 시작점을 덱 더미로 맞춘다.
func _place_card_at_deck_for_draw_fx(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.global_position = global_position
	card.rotation = 0.0


## 라이프→패 연출 시작점을 LifeContainer 스택 맨 앞으로 맞춘다.
func _place_card_at_life_for_hand_fx(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	var node_name := "PlayerLifeContainer" if owner_side == GameConstants.Side.PLAYER else "OpponentLifeContainer"
	var display := FieldBoardBuilder.find_under_field(self, node_name) as LifeContainerDisplay
	if display:
		display.place_card_for_hand_fx(card)
	else:
		card.global_position = global_position


## Override in subclass to return the PackedScene used to instantiate card nodes.
func get_card_scene() -> PackedScene:
	push_error("DeckZone.get_card_scene() must be overridden")
	return null


## Override in subclass to return the hand manager node for this side.
func get_hand_manager() -> Node:
	push_error("DeckZone.get_hand_manager() must be overridden")
	return null


## Returns the CardManager node by searching the field tree.
func get_card_manager() -> Node:
	var found := FieldBoardBuilder.find_under_field(self, "CardManager")
	return found if found else get_node_or_null("../CardManager")


## 씬 트리에서 EffectManager를 찾는다 (존 동기화·클릭 연결용).
func get_effect_manager() -> Node:
	var found := FieldBoardBuilder.find_under_field(self, "EffectManager")
	if found:
		return found
	var pm := FieldBoardBuilder.find_under_field(self, "PhaseManager")
	if pm and pm.get_parent():
		return pm.get_parent().get_node_or_null("EffectManager")
	return get_node_or_null("../EffectManager")


## EM이 소유한 매치 EffectContext. S3: static instance 대신 EM.context 경로.
func get_effect_context() -> EffectContext:
	var em := get_effect_manager()
	if em != null and em.get("context") != null:
		return em.context as EffectContext
	return null


## Returns current hand size via the hand manager.
func _get_hand_size() -> int:
	return get_hand_manager().get_hand_size()


## Clamps rarity to the valid CardRarity.Tier range.
func _clamp_rarity(rarity: int) -> int:
	return clampi(rarity, CardRarity.Tier.N, CardRarity.Tier.UR)


## Builds a typed Array[int] of length `length` from `source`, padding with N rarity.
func _normalize_rarities(source: Array, length: int) -> Array[int]:
	var out: Array[int] = []
	for i in length:
		if i < source.size():
			out.append(_clamp_rarity(int(source[i])))
		else:
			out.append(CardRarity.Tier.N)
	return out


## Pops and returns the front element of an int array, or fallback if empty.
func _pop_front_int(arr: Array[int], fallback: int) -> int:
	if arr.is_empty():
		return fallback
	var v := arr[0]
	arr.remove_at(0)
	return v


## Takes and returns the rarity at idx, removing it from the array.
func _take_rarity_at(arr: Array[int], idx: int) -> int:
	if idx < 0 or idx >= arr.size():
		return CardRarity.Tier.N
	var v := arr[idx]
	arr.remove_at(idx)
	return _clamp_rarity(v)


## Takes and returns the uuid at idx, removing it from the array.
func _take_uuid_at(arr: Array[int], idx: int) -> int:
	if idx < 0 or idx >= arr.size():
		return 0
	var v := arr[idx]
	arr.remove_at(idx)
	return v


## Inserts a uuid at idx, padding with 0 if needed.
func _insert_uuid_at(arr: Array[int], idx: int, value: int) -> void:
	while arr.size() < idx:
		arr.append(0)
	arr.insert(idx, value)


## Inserts a rarity at idx, padding with N rarity if needed.
func _insert_rarity_at(arr: Array[int], idx: int, value: int) -> void:
	while arr.size() < idx:
		arr.append(CardRarity.Tier.N)
	arr.insert(idx, _clamp_rarity(value))
