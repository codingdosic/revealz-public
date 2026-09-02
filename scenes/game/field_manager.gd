## 필드 슬롯 조회·라인 파워·CLEAN 정리. EffectContext는 EM.context로 접근 (S3 DI).
extends Node2D
class_name FieldManager

var _slots_by_side: Dictionary = {}


## 형제 EffectManager가 소유한 매치 EffectContext를 반환한다.
func _effect_context() -> EffectContext:
	var em := get_node_or_null("../EffectManager")
	if em != null and em.get("context") != null:
		return em.context as EffectContext
	return null


func _ready() -> void:
	_register_slots()


func _register_slots() -> void:
	_slots_by_side = {
		GameConstants.Side.PLAYER: [],
		GameConstants.Side.OPPONENT: [],
	}

	var field: Node = get_parent()
	var roots: Array = []
	var player_slots := field.get_node_or_null("PlayerBoard/CardSlots")
	var opponent_slots := field.get_node_or_null("OpponentBoard/CardSlots")
	var legacy := field.get_node_or_null("CardSlots")
	if player_slots:
		roots.append(player_slots)
	if opponent_slots:
		roots.append(opponent_slots)
	if legacy and roots.is_empty():
		roots.append(legacy)
	for card_slots_root in roots:
		for group_name in card_slots_root.get_children():
			var parsed := _parse_slot_group(group_name.name)
			if parsed.is_empty():
				continue
			var side: GameConstants.Side = parsed.side
			var line: GameConstants.Line = parsed.line
			for child in group_name.get_children():
				if child is CardSlot:
					child.side = side
					child.line = line
					_slots_by_side[side].append(child)


func _parse_slot_group(group_name: String) -> Dictionary:
	if group_name.begins_with("PlayerLeft"):
		return {"side": GameConstants.Side.PLAYER, "line": GameConstants.Line.LEFT}
	if group_name.begins_with("PlayerCenter"):
		return {"side": GameConstants.Side.PLAYER, "line": GameConstants.Line.CENTER}
	if group_name.begins_with("PlayerRight"):
		return {"side": GameConstants.Side.PLAYER, "line": GameConstants.Line.RIGHT}
	if group_name.begins_with("OpponentLeft"):
		return {"side": GameConstants.Side.OPPONENT, "line": GameConstants.Line.LEFT}
	if group_name.begins_with("OpponentCenter"):
		return {"side": GameConstants.Side.OPPONENT, "line": GameConstants.Line.CENTER}
	if group_name.begins_with("OpponentRight"):
		return {"side": GameConstants.Side.OPPONENT, "line": GameConstants.Line.RIGHT}
	return {}


func get_empty_slots(side: GameConstants.Side, line: GameConstants.Line = -1) -> Array:
	var result: Array = []
	for slot in _slots_by_side.get(side, []):
		if line != -1 and slot.line != line:
			continue
		if slot.is_empty():
			result.append(slot)
	return result


func get_random_empty_slot(side: GameConstants.Side) -> CardSlot:
	var empty := get_empty_slots(side)
	if empty.is_empty():
		return null
	return empty[randi() % empty.size()]


func get_slots_for_side_line(side: GameConstants.Side, line: GameConstants.Line) -> Array:
	var result: Array = []
	for slot in _slots_by_side.get(side, []):
		if slot.line == line:
			result.append(slot)
	return result


func get_slot_index_for_slot(slot: CardSlot) -> int:
	if slot == null:
		return 0
	return get_slots_for_side_line(slot.side, slot.line).find(slot)


func get_slot_for_side_line_index(
	side: GameConstants.Side,
	line: GameConstants.Line,
	slot_index: int = 0
) -> CardSlot:
	var slots: Array = get_slots_for_side_line(side, line)
	if slots.is_empty():
		return null
	return slots[clampi(slot_index, 0, slots.size() - 1)]


func get_slot_for_side_line(side: GameConstants.Side, line: GameConstants.Line) -> CardSlot:
	return get_slot_for_side_line_index(side, line, 0)


## 카드를 슬롯에 붙인다. 손패 부채 회전은 여기서 0으로 되돌린다.
func place_card_on_slot(card: Node2D, slot: CardSlot) -> void:
	if not slot.is_empty() and slot.card_in_slot != card:
		slot.release()
	slot.occupy(card)
	card.visible = true
	card.rotation = 0.0
	card.global_position = slot.global_position
	card.scale = Vector2(0.4, 0.4)
	if card.get("zone") != null:
		card.zone = EffectTypes.Location.FIELD
	_ensure_effect_click(card)
	if card.has_method("update_on_field_power"):
		card.update_on_field_power()

func remove_card_from_slot(card: Node2D) -> void:
	if card.card_slot_card_is_in:
		card.card_slot_card_is_in.release()


func get_cards_by_line(side: GameConstants.Side) -> Dictionary:
	var by_line := {
		GameConstants.Line.LEFT: [],
		GameConstants.Line.CENTER: [],
		GameConstants.Line.RIGHT: [],
	}
	for slot in _slots_by_side.get(side, []):
		if slot.card_in_slot and slot.card_in_slot.card_name != "":
			by_line[slot.line].append(slot.card_in_slot)
	return by_line


func get_line_power_diffs() -> Dictionary:
	var diffs := {
		GameConstants.Line.LEFT: 0,
		GameConstants.Line.CENTER: 0,
		GameConstants.Line.RIGHT: 0,
	}
	for line in diffs:
		var player_cards := _get_power_cards(GameConstants.Side.PLAYER, line)
		var opponent_cards := _get_power_cards(GameConstants.Side.OPPONENT, line)
		var player_power := BattleResolver.sum_line_power_nodes(
			player_cards, line, GameConstants.Side.PLAYER
		)
		var opponent_power := BattleResolver.sum_line_power_nodes(
			opponent_cards, line, GameConstants.Side.OPPONENT
		)
		diffs[line] = player_power - opponent_power
	return diffs


func _get_power_cards(side: GameConstants.Side, line: GameConstants.Line) -> Array:
	var cards: Array = []
	for slot in _slots_by_side.get(side, []):
		if slot.line != line or slot.card_in_slot == null:
			continue
		var card: Node2D = slot.card_in_slot
		if card.card_name == "":
			continue
		if not CardHelpers.contributes_field_power(card):
			continue
		if side == GameConstants.Side.OPPONENT:
			if card.reveal_state != GameConstants.RevealState.REVEALED:
				continue
		cards.append(card)
	return cards


## 배치된 카드에 효과 클릭 시그널을 연결한다 (player_deck 경로).
func _ensure_effect_click(card: Node2D) -> void:
	var ctx := _effect_context()
	if ctx == null:
		return
	var player_deck: DeckZone = ctx.player_deck
	if player_deck:
		player_deck.ensure_effect_click_connection(card)


## CLEAN 페이즈 — 필드 카드를 묘지로 보낸다. context가 있으면 destroy_card 경로.
func clear_field_to_graveyard(player_deck: DeckZone, opponent_deck: DeckZone, suppress_trash: bool = true) -> void:
	var ctx := _effect_context()
	if ctx:
		ctx.is_clean_phase = true
		ctx.clean_phase_return_stacks_to_deck_bottom(GameConstants.Side.PLAYER)
		ctx.clean_phase_return_stacks_to_deck_bottom(GameConstants.Side.OPPONENT)

	var pending: Array = []
	for slot in _slots_by_side[GameConstants.Side.PLAYER]:
		if slot.card_in_slot:
			var card = slot.card_in_slot
			slot.release()
			pending.append({"card": card, "side": GameConstants.Side.PLAYER, "deck": player_deck})

	for slot in _slots_by_side[GameConstants.Side.OPPONENT]:
		if slot.card_in_slot:
			var card = slot.card_in_slot
			slot.release()
			pending.append({"card": card, "side": GameConstants.Side.OPPONENT, "deck": opponent_deck})

	if ctx and MatchVfx.is_active() and not pending.is_empty():
		var moves: Array = []
		for item in pending:
			var card: Node2D = item["card"] as Node2D
			if card == null or not is_instance_valid(card):
				continue
			var side: GameConstants.Side = item["side"]
			var params := MatchVfx.default_grave_params()
			params["trail"] = false
			params["from"] = card.global_position
			params["to"] = ctx.graveyard_world_pos(side)
			params["face"] = MatchVfx.FACE_UP
			moves.append({"card": card, "params": params})
		await MatchVfx.await_parallel_moves(moves)

	for item in pending:
		var card = item["card"]
		var side: GameConstants.Side = item["side"]
		var deck: DeckZone = item["deck"]
		if ctx:
			await ctx.destroy_card(card, suppress_trash, false)
		else:
			if is_instance_valid(card):
				deck.send_card_to_graveyard(
					deck._card_id_of_node(card),
					card.network_uuid,
					int(card.get("instance_rarity") if card.get("instance_rarity") != null else CardRarity.Tier.N)
				)
				card.queue_free()

	if ctx:
		ctx.is_clean_phase = false
