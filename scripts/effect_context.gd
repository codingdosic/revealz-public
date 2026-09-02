## 매치 단위 효과 존·선택·기록 facade. EffectManager.setup이 생성·소유한다.
## static instance 없음 (S3 / B-EC-03) — Runner·Applier·Steps는 DI, 카드/존은 EM.context.
## Mutator/Query 전면 분할은 비범위 (B-EC-01 → S7).
extends RefCounted
class_name EffectContext

var phase_manager: Node
var field_manager: FieldManager
var player_deck: DeckZone
var opponent_deck: DeckZone
var player_hand: Node
var opponent_hand: Node
var card_manager: Node
var effect_manager: Node

var graveyard_nodes: Dictionary = {
	GameConstants.Side.PLAYER: [],
	GameConstants.Side.OPPONENT: [],
}

var banishzone_nodes: Dictionary = {
	GameConstants.Side.PLAYER: [],
	GameConstants.Side.OPPONENT: [],
}

## 덱탑 공개 선택 중 임시 노드 (핸드/필드 밖). MP SELECT·MOVE 조회용.
var reveal_select_nodes: Array = []

var turn_effect_history: Dictionary = {
	GameConstants.Side.PLAYER: {},
	GameConstants.Side.OPPONENT: {},
}

var is_in_open_window: bool = false
var is_clean_phase: bool = false
var is_life_check: bool = false
var current_effect_trigger: String = "OPEN"
var current_effect_all_line: bool = true
var current_effect_action: EffectAction = null

## OPEN 창 중 필드 위치가 바뀐 카드 instance_id. 해당 카드의 이번 OPEN 발동 차단.
var _open_relocated_ids: Dictionary = {}

var _pending_milled_cards: Array = []

var _next_instance_id: int = 1
var _pending_trash: Array = []
var _trash_wave_processed: Dictionary = {}
var _pending_bind: Array = []
var _bind_wave_processed: Dictionary = {}
var _deferred_life_queue: Array = []

var recorder: EffectChangeRecorder = null
var _suppress_recording: bool = false
## 파이프라인 StepMoveCards 등이 설정. MatchVfx.merge_opts로 이동 params에 합침.
var _move_vfx_override: Dictionary = {}

var step_results: Dictionary = {}
var execution_pool: Array = []
var _next_spawn_uuid: int = 0


## PhaseManager·존·핸드·EM 참조를 주입한다. EM.setup이 매치 시작 시 한 번 호출.
func setup(
	p_phase_manager: Node,
	p_field_manager: FieldManager,
	p_player_deck: DeckZone,
	p_opponent_deck: DeckZone,
	p_player_hand: Node,
	p_opponent_hand: Node,
	p_card_manager: Node,
	p_effect_manager: Node
) -> void:
	phase_manager = p_phase_manager
	field_manager = p_field_manager
	player_deck = p_player_deck
	opponent_deck = p_opponent_deck
	player_hand = p_player_hand
	opponent_hand = p_opponent_hand
	card_manager = p_card_manager
	effect_manager = p_effect_manager


## 카드 instance_id 발급. 네트워크 uuid가 없을 때 로컬 고유키로 쓴다.
func new_instance_id() -> String:
	var id := str(_next_instance_id)
	_next_instance_id += 1
	return id


func get_deck(side: GameConstants.Side) -> DeckZone:
	return player_deck if side == GameConstants.Side.PLAYER else opponent_deck


func get_hand(side: GameConstants.Side) -> Node:
	return player_hand if side == GameConstants.Side.PLAYER else opponent_hand


func current_phase() -> GameConstants.Phase:
	return phase_manager.current_phase


func first_player() -> GameConstants.Side:
	return phase_manager.first_player


func is_com_side(side: GameConstants.Side) -> bool:
	if phase_manager and phase_manager.has_method("_is_online") and phase_manager._is_online():
		return false
	return side == GameConstants.Side.OPPONENT


func set_recorder(p_recorder: EffectChangeRecorder) -> void:
	recorder = p_recorder


func _should_record() -> bool:
	return recorder != null and recorder.is_recording() and not _suppress_recording


## 이 스텝의 이동 연출 오버라이드. source가 있으면 색 미지정 시 카드 색 기본.
func begin_move_vfx(opts: Dictionary, source: Node = null) -> void:
	var merged := opts.duplicate() if not opts.is_empty() else {}
	if not merged.has("color") and source != null and is_instance_valid(source):
		merged["color"] = MatchVfx.trail_color_for_card(source)
	_move_vfx_override = merged
	if recorder:
		recorder.pending_vfx = merged.duplicate(true)


## 이동 연출 오버라이드를 해제한다.
func end_move_vfx() -> void:
	_move_vfx_override.clear()
	if recorder:
		recorder.pending_vfx.clear()


## 기본 이동 params에 파이프라인 오버라이드를 합친다.
func apply_move_vfx(params: Dictionary) -> Dictionary:
	return MatchVfx.merge_opts(params, _move_vfx_override)


## STAT 기록에 붙일 EffectFx opts (MP presenter 배치 재생용).
func begin_stat_fx(opts: Dictionary) -> void:
	if recorder:
		recorder.pending_stat_fx = opts.duplicate(true) if not opts.is_empty() else {}


## STAT EffectFx opts 기록을 해제한다.
func end_stat_fx() -> void:
	if recorder:
		recorder.pending_stat_fx.clear()


## 카드 카피 등급. null/미설정이면 N.
func _card_rarity(card: Node) -> int:
	if card == null:
		return CardRarity.Tier.N
	var raw: Variant = card.get("instance_rarity")
	if raw == null:
		return CardRarity.Tier.N
	return clampi(int(raw), CardRarity.Tier.N, CardRarity.Tier.UR)


## 카드 노드에서 카탈로그 id를 반환한다. card_data.id 우선, 없으면 CardRegistry.name_to_id.
func _card_catalog_id(card: Node) -> int:
	if card == null:
		return 0
	var cd: CardData = card.get("card_data") as CardData
	if cd != null and cd.id > 0:
		return int(cd.id)
	return CardRegistry.name_to_id(String(card.get("card_name")))


func record_stat_change(card: Node, delta: int, line: int = -1, source: Node = null) -> void:
	if not _should_record() or card == null:
		return
	var stats := {}
	if line >= 0:
		stats["line"] = line
		stats["delta"] = delta
	else:
		stats["l"] = int(card.stat_l)
		stats["c"] = int(card.stat_c)
		stats["r"] = int(card.stat_r)
		stats["delta"] = delta
	var source_uuid := 0
	if source != null and is_instance_valid(source):
		source_uuid = int(source.get("network_uuid"))
	recorder.record_stat(int(card.network_uuid), stats, source_uuid)


func record_zone_snapshot_for_side(side: GameConstants.Side) -> void:
	if not _should_record():
		return
	var session := GameSession.get_active()
	var net_side := session.local_side_to_network(side)
	recorder.record_zone_snapshot(net_side, get_deck(side))


func get_owner_side(card: Node) -> GameConstants.Side:
	return card.owner_side


func grave_count(side: GameConstants.Side) -> int:
	return get_deck(side).graveyard.size()


func banishzone_count(side: GameConstants.Side) -> int:
	return get_deck(side).banishzone.size()


func get_supply_count(side: GameConstants.Side) -> int:
	var deck := get_deck(side)
	return deck.deck.size() + deck.graveyard.size()


func can_supply(side: GameConstants.Side, needed: int) -> bool:
	if needed <= 0:
		return true
	return get_supply_count(side) >= needed


func hand_count(side: GameConstants.Side) -> int:
	return get_hand(side).get_hand_size()


func field_has_cards(side: GameConstants.Side, ally_only: bool = true) -> bool:
	return get_field_cards(side, ally_only).size() > 0


func get_field_cards(side: GameConstants.Side, include_all: bool = true) -> Array:
	var cards: Array = []
	for slot in field_manager._slots_by_side.get(side, []):
		if slot.card_in_slot:
			cards.append(slot.card_in_slot)
	if not include_all:
		return cards
	for opp_side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		if opp_side == side:
			continue
		for slot in field_manager._slots_by_side.get(opp_side, []):
			if slot.card_in_slot:
				cards.append(slot.card_in_slot)
	return cards


func get_graveyard_card_nodes(side: GameConstants.Side) -> Array:
	return graveyard_nodes[side].duplicate()


func get_banishzone_card_nodes(side: GameConstants.Side) -> Array:
	return banishzone_nodes[side].duplicate()


func line_of_card(card: Node) -> int:
	if card == null or not is_instance_valid(card):
		return -1
	var slot = card.get("card_slot_card_is_in")
	if slot == null:
		return -1
	return slot.line


func effect_target_line(source: Node, all_line: bool) -> int:
	if all_line:
		return -1
	return line_of_card(source)


func get_empty_field_slots(side: GameConstants.Side, line: int = -1) -> Array:
	return field_manager.get_empty_slots(side, line)


func filter_field_cards_by_line(cards: Array, source: Node, all_line: bool) -> Array:
	if all_line:
		return cards
	var source_line := line_of_card(source)
	if source_line < 0:
		return cards
	var filtered: Array = []
	for card in cards:
		if line_of_card(card) == source_line:
			filtered.append(card)
	return filtered


func filter_reborn_graveyard_cards(source: Node, cards: Array, all_line: bool) -> Array:
	var line := effect_target_line(source, all_line)
	var side: GameConstants.Side = source.owner_side
	var filtered: Array = []
	for card in cards:
		if not is_instance_valid(card):
			continue
		if not get_empty_field_slots(side, line).is_empty():
			filtered.append(card)
	return filtered


func can_reborn_from_source(source: Node, all_line: bool, target: EffectTypes.Target) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var line := effect_target_line(source, all_line)
	match target:
		EffectTypes.Target.ALLY:
			return _side_has_reborn_slot(source.owner_side, line)
		EffectTypes.Target.OPPONENT:
			return _side_has_reborn_slot(GameConstants.opposite_side(source.owner_side), line)
		EffectTypes.Target.BOTH:
			var has_grave := false
			for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
				if _side_has_grave_cards(side):
					has_grave = true
					break
			return has_grave and _side_has_reborn_slot(source.owner_side, line)
	return false


func _side_has_grave_cards(side: GameConstants.Side) -> bool:
	return not graveyard_nodes[side].is_empty()


func _side_has_reborn_slot(side: GameConstants.Side, line: int) -> bool:
	return not get_empty_field_slots(side, line).is_empty()


func get_reborn_slots_for_card(source: Node, _grave_card: Node, all_line: bool) -> Array:
	if source == null or not is_instance_valid(source):
		return []
	var line := effect_target_line(source, all_line)
	return get_empty_field_slots(source.owner_side, line)


func select_reborn_slot(source: Node, grave_card: Node, all_line: bool) -> CardSlot:
	var slots: Array = get_reborn_slots_for_card(source, grave_card, all_line)
	if slots.is_empty():
		return null
	if slots.size() == 1:
		return slots[0] as CardSlot
	if effect_manager and effect_manager.has_method("select_slots"):
		var picked: Array = await effect_manager.select_slots(slots, 1, source)
		if picked.is_empty():
			return null
		return picked[0] as CardSlot
	return slots[0] as CardSlot


func get_cards_in_location(
	side: GameConstants.Side,
	location: EffectTypes.Location,
	target: EffectTypes.Target,
	source: Node,
	trigger: String
) -> Array:
	var cards: Array = []
	var sides: Array = []
	match target:
		EffectTypes.Target.ALLY:
			sides = [get_owner_side(source)]
		EffectTypes.Target.OPPONENT:
			sides = [GameConstants.opposite_side(get_owner_side(source))]
		EffectTypes.Target.BOTH:
			sides = [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]

	for s in sides:
		match location:
			EffectTypes.Location.HAND:
				for c in get_hand(s).get_hand_cards():
					cards.append(c)
			EffectTypes.Location.GRAVE:
				for c in graveyard_nodes[s]:
					if is_instance_valid(c):
						cards.append(c)
			EffectTypes.Location.BANISH:
				for c in banishzone_nodes[s]:
					if is_instance_valid(c):
						cards.append(c)
			EffectTypes.Location.FIELD:
				var owner := get_owner_side(source)
				var source_line := line_of_card(source) if not current_effect_all_line else -1
				for slot in field_manager._slots_by_side.get(s, []):
					if not slot.card_in_slot:
						continue
					if source_line >= 0 and slot.line != source_line:
						continue
					var field_card = slot.card_in_slot
					if (
						trigger == "OPEN"
						and target == EffectTypes.Target.ALLY
						and s == owner
						and field_card == source
					):
						continue
					if EffectZoneQuery.is_effect_target_blocked(source, field_card):
						continue
					if EffectZoneQuery.is_skill_immune_to_source(source, field_card):
						continue
					cards.append(field_card)
	return cards


func reset_turn_history() -> void:
	turn_effect_history[GameConstants.Side.PLAYER].clear()
	turn_effect_history[GameConstants.Side.OPPONENT].clear()


func reset_pipeline_state() -> void:
	step_results.clear()
	execution_pool.clear()


func reset_trash_wave() -> void:
	_trash_wave_processed.clear()


func reset_bind_wave() -> void:
	_bind_wave_processed.clear()


## OPEN 창 시작/종료 시 호출. 이번 창의 이동 무효 목록을 비운다.
func reset_open_relocate_flags() -> void:
	_open_relocated_ids.clear()


## OPEN 창 중 필드 위치가 바뀐 카드를 기록. 이후 이번 OPEN 발동 불가.
func mark_open_relocated(card: Node) -> void:
	if not is_in_open_window:
		return
	if card == null or not is_instance_valid(card):
		return
	var iid = card.get("instance_id")
	if iid == null or String(iid).is_empty():
		return
	_open_relocated_ids[String(iid)] = true


## OPEN 창 중 위치가 바뀌어 이번 OPEN이 막혔는지.
func was_relocated_during_open(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	var iid = card.get("instance_id")
	if iid == null:
		return false
	return _open_relocated_ids.has(String(iid))


func enqueue_trash_candidate(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if card in _pending_trash:
		return
	_pending_trash.append(card)


func drain_trash_candidates() -> Array:
	var batch := _pending_trash.duplicate()
	_pending_trash.clear()
	return batch


func mark_trash_processed(instance_id: String) -> void:
	_trash_wave_processed[instance_id] = true


func was_trash_processed_this_wave(instance_id: String) -> bool:
	return _trash_wave_processed.has(instance_id)


func remove_from_trash_queue(card: Node) -> void:
	_pending_trash.erase(card)


func enqueue_bind_candidate(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if card in _pending_bind:
		return
	_pending_bind.append(card)


func drain_bind_candidates() -> Array:
	var batch := _pending_bind.duplicate()
	_pending_bind.clear()
	return batch


func mark_bind_processed(instance_id: String) -> void:
	_bind_wave_processed[instance_id] = true


func was_bind_processed_this_wave(instance_id: String) -> bool:
	return _bind_wave_processed.has(instance_id)


func remove_from_bind_queue(card: Node) -> void:
	_pending_bind.erase(card)


func _enqueue_bind_trigger_if_needed(card: Node) -> void:
	if is_clean_phase or is_life_check:
		return
	if effect_manager and effect_manager.has_method("is_presenter_only") and effect_manager.is_presenter_only():
		return
	enqueue_bind_candidate(card)


func shuffle_graveyard_into_deck(side: GameConstants.Side) -> void:
	var deck := get_deck(side)
	if deck.graveyard.is_empty():
		return
	deck._shuffle_graveyard_into_deck()
	deck._update_deck_ui()


func draw_cards(side: GameConstants.Side, count: int) -> void:
	var deck := get_deck(side)
	var hand := get_hand(side)
	for i in range(count):
		if hand.get_hand_size() >= deck.hand_limit:
			break
		if not _prepare_next_deck_card(side):
			break
		var drawn := deck._draw_single_card_name()
		var drawn_id := int(drawn.get("cardId", 0))
		var drawn_rarity := int(drawn.get("rarity", CardRarity.Tier.N))
		var new_card := deck.spawn_card_by_id(
			drawn_id,
			side == GameConstants.Side.PLAYER,
			int(drawn.get("uuid", 0)),
			drawn_rarity
		)
		if new_card is Node2D:
			deck._place_card_at_deck_for_draw_fx(new_card as Node2D)
		if _should_record():
			var net_side := GameSession.get_active().local_side_to_network(side)
			recorder.record_move(
				int(drawn.get("uuid", 0)),
				String(drawn.get("name", "")),
				"deck",
				"hand",
				net_side,
				side == GameConstants.Side.PLAYER,
				-1,
				-1,
				drawn_rarity,
				drawn_id
			)
		hand.add_card_to_hand(new_card, DeckZone.CARD_DRAW_SPEED)
	deck._update_deck_ui()


func mill_deck_to_graveyard(side: GameConstants.Side, count: int) -> Array:
	var deck := get_deck(side)
	var milled: Array = []
	for i in range(count):
		if not _prepare_next_deck_card(side):
			break
		var drawn := deck._draw_single_card_name()
		var drawn_id := int(drawn.get("cardId", 0))
		var drawn_rarity := int(drawn.get("rarity", CardRarity.Tier.N))
		var card := deck.spawn_card_by_id(drawn_id, false, int(drawn.get("uuid", 0)), drawn_rarity)
		if card is Node2D:
			deck._place_card_at_deck_for_draw_fx(card as Node2D)
		if _should_record():
			var net_side := GameSession.get_active().local_side_to_network(side)
			recorder.record_move(
				int(drawn.get("uuid", 0)), String(drawn.get("name", "")),
				"deck", "grave", net_side, false, -1, -1, drawn_rarity, drawn_id
			)
		await move_to_graveyard(card, side, false, false)
		milled.append(card)
	deck._update_deck_ui()
	_pending_milled_cards = milled
	return milled


func take_milled_cards() -> Array:
	var result := _pending_milled_cards.duplicate()
	_pending_milled_cards.clear()
	return result


func can_reveal_deck_top(side: GameConstants.Side, reveal_count: int) -> bool:
	var deck := get_deck(side)
	if deck == null:
		return false
	if deck.deck.size() >= mini(maxi(reveal_count, 1), 1):
		return true
	return not deck.graveyard.is_empty()


func count_available_deck_cards(side: GameConstants.Side) -> int:
	var deck := get_deck(side)
	if deck == null:
		return 0
	if not deck.deck.is_empty():
		return deck.deck.size()
	if not deck.graveyard.is_empty():
		return deck.graveyard.size()
	return 0


func reveal_deck_top_and_pick(source: Node, reveal_count: int, pick_count: int) -> void:
	if source == null or not is_instance_valid(source):
		return
	var side: GameConstants.Side = source.owner_side
	var deck := get_deck(side)
	var hand := get_hand(side)
	if deck == null or hand == null:
		return
	var want := maxi(reveal_count, 0)
	if want > 0 and deck.deck.size() < want and not deck.graveyard.is_empty():
		shuffle_graveyard_into_deck(side)
	var to_reveal := mini(want, deck.deck.size())
	if to_reveal <= 0:
		return
	var revealed: Array = []
	for _i in range(to_reveal):
		if not _prepare_next_deck_card(side):
			break
		var drawn := deck._draw_single_card_name()
		var drawn_id := int(drawn.get("cardId", 0))
		var drawn_rarity := int(drawn.get("rarity", CardRarity.Tier.N))
		var card := deck.spawn_card_by_id(
			drawn_id,
			side == GameConstants.Side.PLAYER,
			int(drawn.get("uuid", 0)),
			drawn_rarity
		)
		if card == null:
			continue
		card.set("zone", EffectTypes.Location.DECK)
		card.visible = false
		CardHelpers.disable_interaction(card)
		register_reveal_select_card(card)
		revealed.append(card)
	deck._update_deck_ui()
	if revealed.is_empty():
		return
	var needed := clampi(pick_count, 1, revealed.size())
	var hint := {"targetLocation": EffectTypes.Location.HAND}
	var picked: Array = await select_card_from(revealed, needed, source, -1, hint)
	if picked.is_empty():
		for card in revealed:
			return_revealed_to_deck_bottom(card)
		deck._update_deck_ui()
		schedule_passive_refresh()
		return
	var picked_set: Dictionary = {}
	for card in picked:
		if is_instance_valid(card):
			picked_set[card] = true
	for card in revealed:
		if not is_instance_valid(card):
			continue
		if picked_set.has(card):
			deck_reveal_to_hand(card, side)
		else:
			return_revealed_to_deck_bottom(card)
	deck._update_deck_ui()
	schedule_passive_refresh()


func deck_reveal_to_hand(card: Node, side: GameConstants.Side) -> void:
	if card == null or not is_instance_valid(card):
		return
	var hand := get_hand(side)
	var deck := get_deck(side)
	if hand == null or not hand.has_method("add_card_to_hand"):
		return
	if deck != null and hand.get_hand_size() >= deck.hand_limit:
		return_revealed_to_deck_bottom(card)
		return
	unregister_reveal_select_card(card)
	card.visible = true
	card.set("zone", EffectTypes.Location.HAND)
	CardHelpers.prepare_for_hand(card, side)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			int(card.network_uuid),
			String(card.card_name),
			"deck",
			"hand",
			net_side,
			side == GameConstants.Side.PLAYER,
			-1,
			-1,
			_card_rarity(card)
		)
	hand.add_card_to_hand(card, DeckZone.CARD_DRAW_SPEED)


func return_revealed_to_deck_bottom(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if _vanish_token_if_needed(card):
		return
	unregister_reveal_select_card(card)
	var side: GameConstants.Side = card.owner_side
	var card_id := _card_catalog_id(card)
	var card_name := String(card.card_name)
	var uuid := int(card.get("network_uuid"))
	card.visible = false
	card.set("zone", EffectTypes.Location.DECK)
	var rarity := _card_rarity(card)
	get_deck(side).send_card_to_deck_bottom(card_id, uuid, rarity)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			uuid, card_name, "deck", "deck", net_side, side == GameConstants.Side.PLAYER,
			-1, -1, rarity, card_id
		)
	card.queue_free()


func register_reveal_select_card(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	# 덱탑 공개 선택(뤼트 등): zone=DECK이어도 의도적으로 공개된 카드 → 사이드바 허용.
	card.set_meta(CardInfoRules.META_REVEAL_SELECT, true)
	if card not in reveal_select_nodes:
		reveal_select_nodes.append(card)


func unregister_reveal_select_card(card: Node) -> void:
	if card != null and is_instance_valid(card) and card.has_meta(CardInfoRules.META_REVEAL_SELECT):
		card.remove_meta(CardInfoRules.META_REVEAL_SELECT)
	reveal_select_nodes.erase(card)
	reveal_select_nodes = reveal_select_nodes.filter(
		func(c): return c != null and is_instance_valid(c)
	)

func _prepare_next_deck_card(side: GameConstants.Side) -> bool:
	var deck := get_deck(side)
	if not deck.deck.is_empty():
		return true
	if deck.graveyard.is_empty():
		return false
	shuffle_graveyard_into_deck(side)
	record_zone_snapshot_for_side(side)
	var life_pop := deck.pop_life_card_for_hand()
	var life_id := int(life_pop.get("cardId", 0))
	var life_name := String(life_pop.get("name", ""))
	if life_id > 0 or life_name != "":
		var life_uuid := int(life_pop.get("uuid", 0))
		var life_rarity := int(life_pop.get("rarity", CardRarity.Tier.N))
		var life_card: Node = null
		if life_id > 0:
			life_card = deck.spawn_card_by_id(
				life_id,
				side == GameConstants.Side.PLAYER,
				life_uuid,
				life_rarity
			)
		else:
			life_card = deck.spawn_card_by_name(
				life_name,
				side == GameConstants.Side.PLAYER,
				life_uuid,
				life_rarity
			)
		if life_card is Node2D:
			deck._place_card_at_life_for_hand_fx(life_card as Node2D)
		get_hand(side).add_card_to_hand(life_card, DeckZone.CARD_DRAW_SPEED)
		if _should_record():
			var net_side := GameSession.get_active().local_side_to_network(side)
			recorder.record_move(
				life_uuid, life_name, "life", "hand", net_side, side == GameConstants.Side.PLAYER,
				-1, -1, life_rarity, life_id
			)
			recorder.record({"op": "HAND_LIMIT", "side": net_side, "value": deck.hand_limit})
		if effect_manager and effect_manager.is_busy:
			_queue_deferred_life_check(side, life_card)
		_refresh_life_ui()
	deck._update_deck_ui()
	return not deck.deck.is_empty()


func _refresh_life_ui() -> void:
	if phase_manager and phase_manager.has_method("_update_life_ui"):
		phase_manager._update_life_ui()


func _refresh_line_power_ui() -> void:
	if phase_manager and phase_manager.has_method("_update_line_power_labels"):
		phase_manager._update_line_power_labels()


func _queue_deferred_life_check(side: GameConstants.Side, card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if not card.card_data:
		return
	for bundle in card.card_data.effects:
		if bundle.trigger == "LIFE":
			_deferred_life_queue.append({"side": side, "card": card})
			return


func flush_deferred_life_checks() -> void:
	if effect_manager == null:
		_deferred_life_queue.clear()
		return
	var queue := _deferred_life_queue.duplicate()
	_deferred_life_queue.clear()
	for entry in queue:
		var card: Node = entry.get("card")
		var side: GameConstants.Side = entry.get("side")
		if is_instance_valid(card):
			await effect_manager.run_life_check(side, card)


func clear_graveyard_nodes(side: GameConstants.Side) -> void:
	for card in graveyard_nodes[side].duplicate():
		if is_instance_valid(card):
			card.queue_free()
	graveyard_nodes[side].clear()
	_emit_graveyard_changed(side)


func clear_banishzone_nodes(side: GameConstants.Side) -> void:
	for card in banishzone_nodes[side].duplicate():
		if is_instance_valid(card):
			card.queue_free()
	banishzone_nodes[side].clear()


func move_to_graveyard(
	card: Node,
	side: GameConstants.Side,
	suppress_trash: bool,
	record_destroy_op: bool = true,
	play_move_fx: bool = true
) -> void:
	if card == null or not is_instance_valid(card):
		return
	_clear_card_manager_hover(card)
	if _vanish_token_if_needed(card):
		return
	if card.get("stack_cards") and card.stack_cards.size() > 0 and not is_clean_phase:
		await _cascade_host_stacks_to_graveyard(card, suppress_trash)
	if card.stack_host != null and is_instance_valid(card.stack_host):
		detach_from_stack(card)

	var from_pos := Vector2.ZERO
	var animate := false
	if card is Node2D and is_instance_valid(card):
		var n2 := card as Node2D
		from_pos = n2.global_position
		animate = (
			play_move_fx
			and MatchVfx.is_active()
			and n2.visible
			and n2.is_inside_tree()
		)

	_remove_card_from_zones(card)
	_reset_card_stats_leaving_field(card)
	card.set("zone", EffectTypes.Location.GRAVE)
	CardHelpers.disable_interaction(card)

	if animate:
		var n2 := card as Node2D
		n2.visible = true
		var params := apply_move_vfx(MatchVfx.default_grave_params())
		params["from"] = from_pos
		params["to"] = graveyard_world_pos(side)
		params["face"] = MatchVfx.FACE_UP
		await MatchVfx.await_card_move(n2, params)

	card.visible = false
	if card not in graveyard_nodes[side]:
		graveyard_nodes[side].append(card)
	get_deck(side).send_card_to_graveyard(
		_card_catalog_id(card),
		int(card.get("network_uuid")),
		int(card.get("instance_rarity") if card.get("instance_rarity") != null else CardRarity.Tier.N)
	)
	if _should_record() and record_destroy_op:
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_destroy(
			int(card.network_uuid), String(card.card_name), net_side, suppress_trash,
			_card_catalog_id(card)
		)
	_emit_graveyard_changed(side)
	if not suppress_trash and not is_clean_phase and not is_life_check:
		if effect_manager and effect_manager.has_method("is_presenter_only") and effect_manager.is_presenter_only():
			pass
		else:
			enqueue_trash_candidate(card)
	if effect_manager and effect_manager.has_method("on_card_destroyed"):
		effect_manager.on_card_destroyed(card, suppress_trash)


## 해당 사이드 묘지 존의 월드 좌표 (이동 연출 도착점).
func graveyard_world_pos(side: GameConstants.Side) -> Vector2:
	var path := (
		"PlayerGraveyard" if side == GameConstants.Side.PLAYER else "OpponentGraveyard"
	)
	var from: Node = phase_manager if phase_manager else field_manager
	var node := FieldBoardBuilder.find_under_field(from, path) as Node2D
	if node != null:
		return node.global_position
	return Vector2.ZERO


## 해당 사이드 바인드/제외 존의 월드 좌표.
func banish_world_pos(side: GameConstants.Side) -> Vector2:
	var path := (
		"PlayerBanishZone" if side == GameConstants.Side.PLAYER else "OpponentBanishZone"
	)
	var from: Node = phase_manager if phase_manager else field_manager
	var node := FieldBoardBuilder.find_under_field(from, path) as Node2D
	if node != null:
		return node.global_position
	return Vector2.ZERO


func move_to_banishzone(
	card: Node,
	side: GameConstants.Side,
	record_move_op: bool = true,
	play_move_fx: bool = true
) -> void:
	if card == null or not is_instance_valid(card):
		return
	_clear_card_manager_hover(card)

	var from_pos := Vector2.ZERO
	var animate := false
	if card is Node2D and is_instance_valid(card):
		var n2 := card as Node2D
		from_pos = n2.global_position
		animate = (
			play_move_fx
			and MatchVfx.is_active()
			and n2.visible
			and n2.is_inside_tree()
		)

	_remove_card_from_zones(card)
	_reset_card_stats_leaving_field(card)
	card.set("zone", EffectTypes.Location.BANISH)
	CardHelpers.disable_interaction(card)

	if animate:
		var n2 := card as Node2D
		n2.visible = true
		var params := apply_move_vfx(MatchVfx.default_banish_params())
		params["from"] = from_pos
		params["to"] = banish_world_pos(side)
		params["face"] = MatchVfx.FACE_UP
		await MatchVfx.await_card_move(n2, params)

	card.visible = false
	if card not in banishzone_nodes[side]:
		banishzone_nodes[side].append(card)
	get_deck(side).send_card_to_banishzone(
		_card_catalog_id(card),
		int(card.get("network_uuid")),
		int(card.get("instance_rarity") if card.get("instance_rarity") != null else CardRarity.Tier.N)
	)
	if _should_record() and record_move_op:
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			int(card.network_uuid), String(card.card_name), "unknown", "banishzone", net_side,
			false, -1, -1, _card_rarity(card), _card_catalog_id(card)
		)
	_enqueue_bind_trigger_if_needed(card)


func bind_to_banishzone(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if _vanish_token_if_needed(card):
		return
	var side: GameConstants.Side = card.owner_side
	var deck := get_deck(side)
	var uuid := int(card.get("network_uuid"))
	var from_zone := "unknown"

	var from_pos := Vector2.ZERO
	var animate := false
	if card is Node2D and is_instance_valid(card):
		var n2 := card as Node2D
		from_pos = n2.global_position
		animate = MatchVfx.is_active() and n2.visible and n2.is_inside_tree()

	# 런타임 zone 기준으로 원본 목록 정리
	var zone: int = int(card.get("zone")) if card.get("zone") != null else -1
	if zone == EffectTypes.Location.HAND:
		from_zone = "hand"
		var hand := get_hand(side)
		if hand and hand.has_method("remove_card_from_hand"):
			hand.remove_card_from_hand(card)
	elif zone == EffectTypes.Location.FIELD:
		from_zone = "field"
		field_manager.remove_card_from_slot(card)
		_reset_card_stats_leaving_field(card)
	elif zone == EffectTypes.Location.GRAVE:
		from_zone = "grave"
		remove_from_trash_queue(card)
		remove_from_bind_queue(card)
		graveyard_nodes[side].erase(card)
		if uuid > 0:
			deck.remove_from_graveyard_by_uuid(uuid)
		else:
			var _cid := _card_catalog_id(card)
			var _gidx := deck.graveyard.find(_cid)
			if _gidx >= 0:
				deck.graveyard.remove_at(_gidx)
				if _gidx < deck._graveyard_uuids.size():
					deck._graveyard_uuids.remove_at(_gidx)
				if _gidx < deck._graveyard_rarities.size():
					deck._graveyard_rarities.remove_at(_gidx)
		_emit_graveyard_changed(side)
		# 묘지 노드는 보통 숨김 — 공개 이동 연출을 위해 묘지 앵커에서 시작
		from_pos = graveyard_world_pos(side)
		animate = MatchVfx.is_active()
	elif zone == EffectTypes.Location.BANISH:
		# 이미 banishzone이면 no-op
		return

	card.set("zone", EffectTypes.Location.BANISH)
	CardHelpers.disable_interaction(card)

	if animate and card is Node2D:
		var n2 := card as Node2D
		n2.visible = true
		var params := apply_move_vfx(MatchVfx.default_banish_params())
		params["from"] = from_pos
		params["to"] = banish_world_pos(side)
		params["face"] = MatchVfx.FACE_UP
		await MatchVfx.await_card_move(n2, params)

	# banishzone로 이동(노드/리스트 추가)
	card.visible = false
	if card not in banishzone_nodes[side]:
		banishzone_nodes[side].append(card)
	deck.send_card_to_banishzone(
		_card_catalog_id(card),
		uuid,
		int(card.get("instance_rarity") if card.get("instance_rarity") != null else CardRarity.Tier.N)
	)

	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			uuid, String(card.card_name), from_zone, "banishzone", net_side, false,
			-1, -1, _card_rarity(card), _card_catalog_id(card)
		)

	_enqueue_bind_trigger_if_needed(card)
	schedule_passive_refresh()


func bind_from_deck_top(side: GameConstants.Side, count: int) -> Array:
	var deck := get_deck(side)
	if deck == null:
		return []
	var moved: Array = []
	for _i in range(count):
		if not _prepare_next_deck_card(side):
			break
		var drawn := deck._draw_single_card_name()
		var drawn_id := int(drawn.get("cardId", 0))
		var drawn_rarity := int(drawn.get("rarity", CardRarity.Tier.N))
		var card := deck.spawn_card_by_id(drawn_id, false, int(drawn.get("uuid", 0)), drawn_rarity)
		if card == null:
			continue
		# deck 리스트에는 이미 빠진 상태. 노드를 banishzone로만 넣는다.
		card.set("zone", EffectTypes.Location.DECK)
		if card is Node2D:
			deck._place_card_at_deck_for_draw_fx(card as Node2D)
		await move_to_banishzone(card, side, false)
		moved.append(card)
		if _should_record():
			var net_side := GameSession.get_active().local_side_to_network(side)
			recorder.record_move(
				int(drawn.get("uuid", 0)), String(drawn.get("name", "")),
				"deck", "banishzone", net_side, false, -1, -1, drawn_rarity, drawn_id
			)
	deck._update_deck_ui()
	return moved


func stack_from_deck_top(host: Node, count: int) -> Array:
	if host == null or not is_instance_valid(host):
		return []
	if host.card_slot_card_is_in == null:
		return []
	var side: GameConstants.Side = host.owner_side
	var deck := get_deck(side)
	if deck == null:
		return []
	var moved: Array = []
	for _i in range(count):
		if not _prepare_next_deck_card(side):
			break
		var drawn := deck._draw_single_card_name()
		var drawn_id := int(drawn.get("cardId", 0))
		var drawn_rarity := int(drawn.get("rarity", CardRarity.Tier.N))
		var card := deck.spawn_card_by_id(drawn_id, false, int(drawn.get("uuid", 0)), drawn_rarity)
		if card == null:
			continue
		card.set("zone", EffectTypes.Location.DECK)
		if card is Node2D:
			deck._place_card_at_deck_for_draw_fx(card as Node2D)
		await attach_to_stack(card, host, "deck", false, false)
		moved.append(card)
		if _should_record():
			var net_side := GameSession.get_active().local_side_to_network(side)
			recorder.record_stack_attach(
				int(drawn.get("uuid", 0)),
				int(host.network_uuid),
				"deck",
				net_side,
				String(drawn.get("name", "")),
				drawn_rarity,
				drawn_id
			)
	deck._update_deck_ui()
	if not moved.is_empty():
		schedule_passive_refresh()
	return moved


func attach_to_stack(
	attached: Node,
	host: Node,
	from_zone: String = "",
	record_move_op: bool = true,
	refresh_passive: bool = true
) -> bool:
	if attached == null or not is_instance_valid(attached):
		return false
	if host == null or not is_instance_valid(host):
		return false
	if host.card_slot_card_is_in == null:
		return false
	if attached == host:
		return false
	if _vanish_token_if_needed(attached):
		return false

	var resolved_from := from_zone
	if resolved_from.is_empty():
		resolved_from = _zone_name_for_card(attached)

	var from_pos := Vector2.ZERO
	var source_stack_host: Node = null
	if attached is Node2D:
		source_stack_host = attached.get("stack_host")
		if source_stack_host != null and is_instance_valid(source_stack_host):
			if source_stack_host is Node2D:
				from_pos = (source_stack_host as Node2D).global_position
		else:
			from_pos = (attached as Node2D).global_position

	_detach_card_from_current_zone(attached, resolved_from)

	if attached is Node2D:
		var n2d := attached as Node2D
		n2d.visible = true
		# 항상 CardManager 하위 — orphan이면 Tween이 snap만 됨.
		_ensure_card_under_manager(n2d)
		if source_stack_host != null or resolved_from == "stack":
			n2d.global_position = from_pos
			n2d.scale = Vector2(0.4, 0.4)
			n2d.rotation = 0.0
	if MatchVfx.is_active() and attached is Node2D and host is Node2D:
		var params := apply_move_vfx(MatchVfx.default_field_params(MatchVfx.FACE_UP))
		params["from"] = from_pos
		params["to"] = (host as Node2D).global_position
		await MatchVfx.await_card_move(attached as Node2D, params)

	attached.set("zone", EffectTypes.Location.STACK)
	attached.set("reveal_state", GameConstants.RevealState.REVEALED)
	CardHelpers.disable_interaction(attached as Node2D)
	if host.has_method("add_stack_card"):
		host.add_stack_card(attached)
	else:
		host.stack_cards.append(attached)
		attached.stack_host = host

	if _should_record() and record_move_op:
		var net_side := GameSession.get_active().local_side_to_network(host.owner_side)
		recorder.record_stack_attach(
			int(attached.network_uuid),
			int(host.network_uuid),
			resolved_from,
			net_side,
			String(attached.card_name)
		)
	if refresh_passive:
		schedule_passive_refresh()
	return true


func detach_from_stack(attached: Node) -> void:
	if attached == null or not is_instance_valid(attached):
		return
	var host: Node = attached.stack_host
	if host == null or not is_instance_valid(host):
		attached.stack_host = null
		return
	if host.has_method("remove_stack_card"):
		host.remove_stack_card(attached)
	else:
		host.stack_cards.erase(attached)
		attached.stack_host = null
	if attached.get_parent() == host:
		host.remove_child(attached)


func find_stack_host_for_card(card: Node) -> Node:
	if card == null or not is_instance_valid(card):
		return null
	if card.stack_host != null and is_instance_valid(card.stack_host):
		return card.stack_host
	return null


func get_stack_cards_on_host(host: Node) -> Array:
	if host == null or not is_instance_valid(host):
		return []
	if not host.get("stack_cards"):
		return []
	return host.stack_cards.duplicate()


func count_stacks_on_field(side: GameConstants.Side, units_only: bool = false) -> int:
	var total := 0
	for card in get_field_cards(side, false):
		if not is_instance_valid(card):
			continue
		if units_only and not CardDisplayHelpers.is_unit_card(card):
			continue
		if card.get("stack_cards"):
			total += card.stack_cards.size()
	return total


func count_ally_stacks(
	source: Node,
	line_scope: EffectTypes.LineScope = EffectTypes.LineScope.ALL_LINES,
	units_only: bool = true
) -> int:
	if source == null:
		return 0
	var side: GameConstants.Side = source.owner_side
	var source_line := line_of_card(source)
	var total := 0
	for card in get_field_cards(side, false):
		if not is_instance_valid(card):
			continue
		if units_only and not CardDisplayHelpers.is_unit_card(card):
			continue
		if line_scope == EffectTypes.LineScope.SAME_AS_SOURCE:
			var card_line := line_of_card(card)
			if source_line >= 0 and card_line >= 0 and card_line != source_line:
				continue
		if not card.get("stack_cards"):
			continue
		total += card.stack_cards.size()
	return total


func field_has_any_stacked_ally(source: Node) -> bool:
	return count_ally_stacks(source, EffectTypes.LineScope.ALL_LINES, true) > 0


func stack_to_hand(attached: Node) -> void:
	if attached == null or not is_instance_valid(attached):
		return
	var side: GameConstants.Side = attached.owner_side
	var host_pos := Vector2.ZERO
	var host: Node = attached.stack_host
	if host is Node2D and is_instance_valid(host):
		host_pos = (host as Node2D).global_position
	detach_from_stack(attached)
	_reset_card_stats_leaving_field(attached)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			int(attached.network_uuid),
			String(attached.card_name),
			"stack",
			"hand",
			net_side,
			side == GameConstants.Side.PLAYER,
			-1,
			-1,
			_card_rarity(attached)
		)
	var hand := get_hand(side)
	if hand and hand.has_method("add_card_to_hand"):
		attached.visible = true
		attached.set("zone", EffectTypes.Location.HAND)
		CardHelpers.prepare_for_hand(attached as Node2D, side)
		if attached is Node2D and host_pos != Vector2.ZERO:
			(attached as Node2D).global_position = host_pos
		hand.add_card_to_hand(attached, DeckZone.CARD_DRAW_SPEED)
	schedule_passive_refresh()


func trash_stack_cards(cards: Array) -> Array:
	var trashed: Array = []
	for card in cards:
		if not is_instance_valid(card):
			continue
		detach_from_stack(card)
		await move_to_graveyard(card, card.owner_side, false)
		trashed.append(card)
	if not trashed.is_empty():
		schedule_passive_refresh()
	return trashed


func gather_all_ally_stacks_to_host(host: Node) -> Array:
	if host == null or not is_instance_valid(host):
		return []
	var side: GameConstants.Side = host.owner_side
	var moved: Array = []
	for unit in get_field_cards(side, false):
		if not is_instance_valid(unit) or unit == host:
			continue
		if not CardDisplayHelpers.is_unit_card(unit):
			continue
		if not unit.get("stack_cards") or unit.stack_cards.is_empty():
			continue
		var stacked_batch: Array = unit.stack_cards.duplicate()
		for attached in stacked_batch:
			if not is_instance_valid(attached):
				continue
			# detach는 attach_to_stack 내부에서 — 선행 detach하면 orphan이라 VFX snap만 됨.
			if await attach_to_stack(attached, host, "stack", true, false):
				moved.append(attached)
	if not moved.is_empty():
		schedule_passive_refresh()
	return moved


func _zone_name_for_card(card: Node) -> String:
	var zone: int = int(card.get("zone")) if card.get("zone") != null else -1
	match zone:
		EffectTypes.Location.HAND:
			return "hand"
		EffectTypes.Location.FIELD:
			return "field"
		EffectTypes.Location.GRAVE:
			return "grave"
		EffectTypes.Location.BANISH:
			return "banishzone"
		EffectTypes.Location.DECK:
			return "deck"
		EffectTypes.Location.STACK:
			return "stack"
	return "unknown"


## 이동 VFX용 CardManager 자식 보장 (스택 detach 후 orphan).
func _ensure_card_under_manager(card: Node2D) -> void:
	if card_manager == null or not is_instance_valid(card_manager):
		return
	if card.get_parent() == card_manager:
		return
	if card.get_parent():
		card.get_parent().remove_child(card)
	card_manager.add_child(card)


## 토큰 필드 도착: VFX 활성=instant reveal+팝인 · 비활성=기존 card_flip.
func _play_token_field_arrival_vfx(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	if not MatchVfx.is_active():
		card.reveal()
		return
	CardHelpers.reveal_card_instant(card)
	var target_scale := card.scale
	card.scale = Vector2.ZERO
	await MatchVfx.await_token_spawn_pop_in(card, target_scale)
	RareRevealFx.play(card)


func _detach_card_from_current_zone(card: Node, from_zone: String) -> void:
	if card.stack_host != null and is_instance_valid(card.stack_host):
		detach_from_stack(card)
	field_manager.remove_card_from_slot(card)
	var side: GameConstants.Side = card.owner_side
	var hand := get_hand(side)
	if hand and hand.has_method("remove_card_from_hand"):
		hand.remove_card_from_hand(card)
	if graveyard_nodes[side].has(card):
		graveyard_nodes[side].erase(card)
		_emit_graveyard_changed(side)
	if banishzone_nodes[side].has(card):
		banishzone_nodes[side].erase(card)
	var deck := get_deck(side)
	var uuid := int(card.get("network_uuid"))
	match from_zone:
		"grave":
			if uuid > 0:
				deck.remove_from_graveyard_by_uuid(uuid)
			else:
				var _cid := _card_catalog_id(card)
				var _gidx := deck.graveyard.find(_cid)
				if _gidx >= 0:
					deck.graveyard.remove_at(_gidx)
					if _gidx < deck._graveyard_uuids.size():
						deck._graveyard_uuids.remove_at(_gidx)
					if _gidx < deck._graveyard_rarities.size():
						deck._graveyard_rarities.remove_at(_gidx)
			_emit_graveyard_changed(side)
		"banishzone":
			if uuid > 0:
				deck.remove_from_banishzone_by_uuid(uuid)
			else:
				var _cid := _card_catalog_id(card)
				var _bidx := deck.banishzone.find(_cid)
				if _bidx >= 0:
					deck.banishzone.remove_at(_bidx)
					if _bidx < deck._banish_uuids.size():
						deck._banish_uuids.remove_at(_bidx)
					if _bidx < deck._banish_rarities.size():
						deck._banish_rarities.remove_at(_bidx)


func _cascade_host_stacks_to_graveyard(host: Node, suppress_trash: bool) -> void:
	if host == null or not host.get("stack_cards"):
		return
	var stacked: Array = host.stack_cards.duplicate()
	for attached in stacked:
		if not is_instance_valid(attached):
			continue
		detach_from_stack(attached)
		await move_to_graveyard(attached, host.owner_side, suppress_trash, true)


func clean_phase_return_stacks_to_deck_bottom(side: GameConstants.Side) -> void:
	var stacked_cards: Array = []
	for unit in get_field_cards(side, false):
		if not is_instance_valid(unit) or not unit.get("stack_cards"):
			continue
		for attached in unit.stack_cards.duplicate():
			if is_instance_valid(attached):
				stacked_cards.append(attached)
	if stacked_cards.is_empty():
		return
	stacked_cards.shuffle()
	for attached in stacked_cards:
		_return_stacked_card_to_deck_bottom(attached, side)
	schedule_passive_refresh()


func _return_stacked_card_to_deck_bottom(card: Node, side: GameConstants.Side) -> void:
	if card == null or not is_instance_valid(card):
		return
	if _vanish_token_if_needed(card):
		return
	if card.stack_host != null and is_instance_valid(card.stack_host):
		detach_from_stack(card)
	_remove_card_from_zones(card)
	card.visible = false
	card.set("zone", EffectTypes.Location.DECK)
	var card_id := _card_catalog_id(card)
	var card_name := String(card.card_name)
	var uuid := int(card.get("network_uuid"))
	var rarity := _card_rarity(card)
	get_deck(side).send_card_to_deck_bottom(card_id, uuid, rarity)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(uuid, card_name, "stack", "deck", net_side, false, -1, -1, rarity, card_id)
	card.queue_free()


func destroy_card(card: Node, suppress_trash: bool = false, play_move_fx: bool = true) -> void:
	if card == null or not is_instance_valid(card):
		return
	var was_on_field := card.card_slot_card_is_in != null
	await move_to_graveyard(card, card.owner_side, suppress_trash, true, play_move_fx)
	if was_on_field:
		_refresh_line_power_ui()


func salvage_to_hand(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if _vanish_token_if_needed(card):
		return
	var side: GameConstants.Side = card.owner_side
	remove_from_trash_queue(card)
	graveyard_nodes[side].erase(card)
	var deck := get_deck(side)
	var card_uuid := int(card.get("network_uuid"))
	if card_uuid > 0:
		deck.remove_from_graveyard_by_uuid(card_uuid)
	else:
		var _cid := _card_catalog_id(card)
		var _gidx := deck.graveyard.find(_cid)
		if _gidx >= 0:
			deck.graveyard.remove_at(_gidx)
			if _gidx < deck._graveyard_uuids.size():
				deck._graveyard_uuids.remove_at(_gidx)
			if _gidx < deck._graveyard_rarities.size():
				deck._graveyard_rarities.remove_at(_gidx)
	_emit_graveyard_changed(side)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			int(card.network_uuid), String(card.card_name), "grave", "hand", net_side,
			side == GameConstants.Side.PLAYER, -1, -1, _card_rarity(card)
		)
	if card is Node2D:
		var n2 := card as Node2D
		n2.visible = true
		n2.global_position = graveyard_world_pos(side)
	CardHelpers.prepare_for_hand(card as Node2D, side)
	get_hand(side).add_card_to_hand(card, DeckZone.CARD_DRAW_SPEED)


func hand_to_deck_bottom(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if _vanish_token_if_needed(card):
		return
	var side: GameConstants.Side = card.owner_side
	var hand := get_hand(side)
	var from_pos := Vector2.ZERO
	if card is Node2D:
		from_pos = (card as Node2D).global_position
	if hand and hand.has_method("remove_card_from_hand"):
		hand.remove_card_from_hand(card)
	var card_id := _card_catalog_id(card)
	var card_name := String(card.card_name)
	var uuid := int(card.get("network_uuid"))
	var rarity := _card_rarity(card)
	var deck := get_deck(side)
	if card is Node2D and MatchVfx.is_active():
		var n2 := card as Node2D
		n2.visible = true
		var params := apply_move_vfx(MatchVfx.default_field_params(MatchVfx.face_for_hand_side(side)))
		params["from"] = from_pos
		params["to"] = deck.global_position
		await MatchVfx.await_card_move(n2, params)
	card.visible = false
	card.set("zone", EffectTypes.Location.DECK)
	deck.send_card_to_deck_bottom(card_id, uuid, rarity)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			uuid, card_name, "hand", "deck", net_side, side == GameConstants.Side.PLAYER,
			-1, -1, rarity, card_id
		)
	card.queue_free()


func field_to_hand(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if _vanish_token_if_needed(card):
		return
	var side: GameConstants.Side = card.owner_side
	var from_pos := Vector2.ZERO
	if card is Node2D:
		from_pos = (card as Node2D).global_position
	if card.stack_host != null and is_instance_valid(card.stack_host):
		detach_from_stack(card)
	field_manager.remove_card_from_slot(card)
	_reset_card_stats_leaving_field(card)
	var hand := get_hand(side)
	if hand == null or not hand.has_method("add_card_to_hand"):
		return
	card.visible = true
	card.set("zone", EffectTypes.Location.HAND)
	CardHelpers.prepare_for_hand(card as Node2D, side)
	if card is Node2D:
		(card as Node2D).global_position = from_pos
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			int(card.network_uuid),
			String(card.card_name),
			"field",
			"hand",
			net_side,
			side == GameConstants.Side.PLAYER,
			-1,
			-1,
			_card_rarity(card)
		)
	hand.add_card_to_hand(card, DeckZone.CARD_DRAW_SPEED)
	schedule_passive_refresh()


## 슬롯 점유 후 from→slot 연출. face 기본 KEEP.
func place_on_slot_with_fx(card: Node, slot: CardSlot, face: String = MatchVfx.FACE_KEEP) -> void:
	if card == null or not is_instance_valid(card) or slot == null:
		return
	var n2 := card as Node2D
	var from := n2.global_position
	field_manager.place_card_on_slot(n2, slot)
	MatchVfx.play_slot_land(slot.global_position, "place")
	if MatchVfx.is_active():
		n2.global_position = from
		var params := apply_move_vfx(MatchVfx.default_field_params(face))
		params["from"] = from
		params["to"] = slot.global_position
		await MatchVfx.await_card_move(n2, params)


func relocate_field_to_slot(card: Node, slot: CardSlot) -> void:
	if card == null or not is_instance_valid(card) or slot == null or not slot.is_empty():
		return
	# 이동 전 PASSIVE clear — 축이 바뀌기 전에 보너스를 되돌려 B2(음수 축 destroy) 방지
	if card.has_method("clear_passive_field_modifiers"):
		card.clear_passive_field_modifiers()
	field_manager.remove_card_from_slot(card)
	if _should_record():
		_record_field_relocate(card, slot)
	mark_open_relocated(card)
	await place_on_slot_with_fx(card, slot, MatchVfx.FACE_KEEP)
	card.is_locked = true
	if card.has_method("update_on_field_power"):
		card.update_on_field_power()
	schedule_passive_refresh()


func _reset_card_stats_leaving_field(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	if card.has_method("reset_runtime_stats_from_card_data"):
		card.reset_runtime_stats_from_card_data()
	elif card.has_method("clear_passive_field_modifiers"):
		card.clear_passive_field_modifiers()

func swap_field_control(card_a: Node, card_b: Node) -> void:
	if card_a == null or card_b == null or not is_instance_valid(card_a) or not is_instance_valid(card_b):
		return
	var slot_a: CardSlot = card_a.card_slot_card_is_in
	var slot_b: CardSlot = card_b.card_slot_card_is_in
	if slot_a == null or slot_b == null:
		return
	var from_a := (card_a as Node2D).global_position
	var from_b := (card_b as Node2D).global_position
	if card_a.has_method("clear_passive_field_modifiers"):
		card_a.clear_passive_field_modifiers()
	if card_b.has_method("clear_passive_field_modifiers"):
		card_b.clear_passive_field_modifiers()
	field_manager.remove_card_from_slot(card_a)
	field_manager.remove_card_from_slot(card_b)
	if _should_record():
		_record_swap_field_control(card_a, card_b, slot_b, slot_a)
	mark_open_relocated(card_a)
	mark_open_relocated(card_b)
	field_manager.place_card_on_slot(card_a as Node2D, slot_b)
	field_manager.place_card_on_slot(card_b as Node2D, slot_a)
	if MatchVfx.is_active():
		(card_a as Node2D).global_position = from_a
		(card_b as Node2D).global_position = from_b
		var pa := apply_move_vfx(MatchVfx.default_field_params(MatchVfx.FACE_KEEP))
		pa["from"] = from_a
		pa["to"] = slot_b.global_position
		var pb := apply_move_vfx(MatchVfx.default_field_params(MatchVfx.FACE_KEEP))
		pb["from"] = from_b
		pb["to"] = slot_a.global_position
		await MatchVfx.await_parallel_moves([
			{"card": card_a, "params": pa},
			{"card": card_b, "params": pb},
		])
	card_a.is_locked = true
	card_b.is_locked = true
	if card_a.has_method("update_on_field_power"):
		card_a.update_on_field_power()
	if card_b.has_method("update_on_field_power"):
		card_b.update_on_field_power()
	_refresh_line_power_ui()
	schedule_passive_refresh()

func apply_effect_set(card: Node) -> void:
	if card == null or not is_instance_valid(card):
		return
	CardHelpers.apply_effect_set(card)
	if _should_record():
		recorder.record_effect_set(int(card.network_uuid), true)
	_refresh_line_power_ui()


func _record_field_relocate(card: Node, slot: CardSlot) -> void:
	if card == null or slot == null:
		return
	var enc := _encode_field_slot_for_network(slot)
	recorder.record_move(
		int(card.network_uuid),
		String(card.card_name),
		"field",
		"field",
		int(enc.get("side", 0)),
		true,
		int(enc.get("line", 0)),
		int(enc.get("slotIndex", 0)),
		_card_rarity(card)
	)


func _record_swap_field_control(
	card_a: Node,
	card_b: Node,
	dest_slot_a: CardSlot,
	dest_slot_b: CardSlot
) -> void:
	if card_a == null or card_b == null or dest_slot_a == null or dest_slot_b == null:
		return
	recorder.record_swap_field(
		int(card_a.network_uuid),
		int(card_b.network_uuid),
		_encode_field_slot_for_network(dest_slot_a),
		_encode_field_slot_for_network(dest_slot_b)
	)


func _encode_field_slot_for_network(slot: CardSlot) -> Dictionary:
	if phase_manager and phase_manager.has_method("encode_field_slot_for_network"):
		return phase_manager.encode_field_slot_for_network(slot)
	var field_side: GameConstants.Side = slot.side
	var net_side := GameSession.get_active().local_side_to_network(field_side)
	var line_idx := int(slot.line)
	var slot_idx := field_manager.get_slot_index_for_slot(slot)
	if phase_manager and phase_manager.has_method("_line_for_network"):
		line_idx = phase_manager._line_for_network(field_side, slot.line)
		slot_idx = phase_manager._slot_index_for_network(
			field_side,
			slot.line,
			field_manager.get_slot_index_for_slot(slot)
		)
	return {"side": net_side, "line": line_idx, "slotIndex": slot_idx}


func reborn_to_field(card: Node, slot: CardSlot) -> void:
	if card == null or not is_instance_valid(card):
		return
	if slot == null or not slot.is_empty():
		return
	var side: GameConstants.Side = card.owner_side
	var from_zone := "unknown"
	var zone: int = int(card.get("zone")) if card.get("zone") != null else -1
	if zone == EffectTypes.Location.GRAVE:
		from_zone = "grave"
	elif zone == EffectTypes.Location.BANISH:
		from_zone = "banishzone"

	remove_from_trash_queue(card)
	remove_from_bind_queue(card)
	var deck := get_deck(side)
	var card_uuid := int(card.get("network_uuid"))

	# GRAVE에서 온 경우: 묘지 노드/리스트에서 제거
	if graveyard_nodes[side].has(card):
		graveyard_nodes[side].erase(card)
	if card_uuid > 0:
		deck.remove_from_graveyard_by_uuid(card_uuid)
	else:
		var _cid := _card_catalog_id(card)
		var _gidx := deck.graveyard.find(_cid)
		if _gidx >= 0:
			deck.graveyard.remove_at(_gidx)
			if _gidx < deck._graveyard_uuids.size():
				deck._graveyard_uuids.remove_at(_gidx)
			if _gidx < deck._graveyard_rarities.size():
				deck._graveyard_rarities.remove_at(_gidx)

	# BANISHZONE에서 온 경우: banish 노드/리스트에서 제거
	if banishzone_nodes[side].has(card):
		banishzone_nodes[side].erase(card)
	if card_uuid > 0:
		deck.remove_from_banishzone_by_uuid(card_uuid)
	else:
		var _cid2 := _card_catalog_id(card)
		var _bidx := deck.banishzone.find(_cid2)
		if _bidx >= 0:
			deck.banishzone.remove_at(_bidx)
			if _bidx < deck._banish_uuids.size():
				deck._banish_uuids.remove_at(_bidx)
			if _bidx < deck._banish_rarities.size():
				deck._banish_rarities.remove_at(_bidx)

	_emit_graveyard_changed(side)
	if _should_record():
		var field_side: GameConstants.Side = slot.side
		var net_side := GameSession.get_active().local_side_to_network(field_side)
		var line_idx := int(slot.line)
		var slot_idx := field_manager.get_slot_index_for_slot(slot)
		if phase_manager and phase_manager.has_method("_line_for_network"):
			line_idx = phase_manager._line_for_network(field_side, slot.line)
			slot_idx = phase_manager._slot_index_for_network(
				field_side,
				slot.line,
				field_manager.get_slot_index_for_slot(slot)
			)
		recorder.record_move(
			int(card.network_uuid),
			String(card.card_name),
			from_zone,
			"field",
			net_side,
			true,
			line_idx,
			slot_idx,
			_card_rarity(card)
		)
	card.visible = true
	card.set("zone", EffectTypes.Location.FIELD)
	CardHelpers.enable_interaction(card)
	if from_zone == "grave":
		(card as Node2D).global_position = graveyard_world_pos(side)
	elif from_zone == "banishzone":
		(card as Node2D).global_position = banish_world_pos(side)
	card.reveal()
	await place_on_slot_with_fx(card, slot, MatchVfx.FACE_KEEP)
	card.is_locked = true
	_refresh_line_power_ui()
	schedule_passive_refresh()


func spawn_token_to_field(
	token_name: String,
	slot: CardSlot,
	owner_side: GameConstants.Side,
	existing_card: Node = null
) -> Node:
	if token_name.is_empty() or slot == null or not slot.is_empty():
		return null
	var deck := get_deck(owner_side)
	var card: Node = existing_card
	var uuid := 0
	if card == null:
		uuid = _allocate_spawn_uuid(owner_side)
		card = deck.spawn_card_by_name(token_name, true, uuid)
	else:
		uuid = int(card.get("network_uuid"))
	if card == null:
		return null
	card.owner_side = owner_side
	card.visible = true
	card.set("zone", EffectTypes.Location.FIELD)
	card.reveal_state = GameConstants.RevealState.REVEALED
	CardHelpers.enable_interaction(card)
	deck.ensure_effect_click_connection(card)
	field_manager.place_card_on_slot(card, slot)
	await _play_token_field_arrival_vfx(card as Node2D)
	card.is_locked = true
	if _should_record():
		var field_side: GameConstants.Side = slot.side
		var net_side := GameSession.get_active().local_side_to_network(field_side)
		var line_idx := int(slot.line)
		var slot_idx := field_manager.get_slot_index_for_slot(slot)
		if phase_manager and phase_manager.has_method("_line_for_network"):
			line_idx = phase_manager._line_for_network(field_side, slot.line)
			slot_idx = phase_manager._slot_index_for_network(
				field_side,
				slot.line,
				field_manager.get_slot_index_for_slot(slot)
			)
		var token_cid := CardRegistry.name_to_id(token_name)
		recorder.record_spawn_to_field(uuid, token_name, net_side, line_idx, slot_idx, true, -1, token_cid)
	_refresh_line_power_ui()
	schedule_passive_refresh()
	return card


## spawn_token_to_field의 id 경로. token_id>0일 때 spawn_card_by_id를 사용한다.
func spawn_token_to_field_by_id(
	token_id: int,
	slot: CardSlot,
	owner_side: GameConstants.Side,
	existing_card: Node = null
) -> Node:
	if token_id <= 0 or slot == null or not slot.is_empty():
		return null
	var token_name := CardRegistry.id_to_name(token_id)
	var deck := get_deck(owner_side)
	var card: Node = existing_card
	var uuid := 0
	if card == null:
		uuid = _allocate_spawn_uuid(owner_side)
		card = deck.spawn_card_by_id(token_id, true, uuid)
	else:
		uuid = int(card.get("network_uuid"))
	if card == null:
		return null
	card.owner_side = owner_side
	card.visible = true
	card.set("zone", EffectTypes.Location.FIELD)
	card.reveal_state = GameConstants.RevealState.REVEALED
	CardHelpers.enable_interaction(card)
	deck.ensure_effect_click_connection(card)
	field_manager.place_card_on_slot(card, slot)
	await _play_token_field_arrival_vfx(card as Node2D)
	card.is_locked = true
	if _should_record():
		var field_side: GameConstants.Side = slot.side
		var net_side := GameSession.get_active().local_side_to_network(field_side)
		var line_idx := int(slot.line)
		var slot_idx := field_manager.get_slot_index_for_slot(slot)
		if phase_manager and phase_manager.has_method("_line_for_network"):
			line_idx = phase_manager._line_for_network(field_side, slot.line)
			slot_idx = phase_manager._slot_index_for_network(
				field_side,
				slot.line,
				field_manager.get_slot_index_for_slot(slot)
			)
		recorder.record_spawn_to_field(uuid, token_name, net_side, line_idx, slot_idx, true, -1, token_id)
	_refresh_line_power_ui()
	schedule_passive_refresh()
	return card


func _allocate_spawn_uuid(owner_side: GameConstants.Side) -> int:
	_next_spawn_uuid += 1
	var net_side := GameSession.get_active().local_side_to_network(owner_side)
	return ((int(net_side) + 1) * 10000) + 8000 + _next_spawn_uuid


func notify_passive_refresh() -> void:
	if effect_manager and effect_manager.has_method("schedule_passive_refresh"):
		effect_manager.schedule_passive_refresh()


func _vanish_token_if_needed(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if not CardDisplayHelpers.is_token_card(card):
		return false
	_vanish_token(card)
	return true


func _vanish_token(card: Node) -> void:
	var side: GameConstants.Side = card.owner_side
	var deck := get_deck(side)
	var uuid := int(card.get("network_uuid"))
	remove_from_trash_queue(card)
	remove_from_bind_queue(card)
	_remove_card_from_zones(card)
	graveyard_nodes[side].erase(card)
	banishzone_nodes[side].erase(card)
	if uuid > 0:
		deck.remove_from_graveyard_by_uuid(uuid)
		deck.remove_from_banishzone_by_uuid(uuid)
	else:
		var _cid := _card_catalog_id(card)
		var _gidx := deck.graveyard.find(_cid)
		if _gidx >= 0:
			deck.graveyard.remove_at(_gidx)
			if _gidx < deck._graveyard_uuids.size():
				deck._graveyard_uuids.remove_at(_gidx)
			if _gidx < deck._graveyard_rarities.size():
				deck._graveyard_rarities.remove_at(_gidx)
		var _bidx := deck.banishzone.find(_cid)
		if _bidx >= 0:
			deck.banishzone.remove_at(_bidx)
			if _bidx < deck._banish_uuids.size():
				deck._banish_uuids.remove_at(_bidx)
			if _bidx < deck._banish_rarities.size():
				deck._banish_rarities.remove_at(_bidx)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_destroy(uuid, String(card.card_name), net_side, true, _card_catalog_id(card))
	_emit_graveyard_changed(side)
	_refresh_line_power_ui()
	schedule_passive_refresh()
	card.queue_free()


func schedule_passive_refresh() -> void:
	if effect_manager and effect_manager.has_method("schedule_passive_refresh"):
		effect_manager.schedule_passive_refresh()


func _remove_card_from_zones(card: Node) -> void:
	if card.stack_host != null and is_instance_valid(card.stack_host):
		detach_from_stack(card)
	field_manager.remove_card_from_slot(card)
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		var hand := get_hand(side)
		if hand.has_method("remove_card_from_hand"):
			hand.remove_card_from_hand(card)
		if graveyard_nodes[side].has(card):
			graveyard_nodes[side].erase(card)
			_emit_graveyard_changed(side)
		if banishzone_nodes[side].has(card):
			banishzone_nodes[side].erase(card)


## 묘지/제외로 떠나기 전 호버 잔존 해제.
func _clear_card_manager_hover(card: Node) -> void:
	if card_manager and card_manager.has_method("clear_hover_state"):
		card_manager.clear_hover_state(card as Node2D)


func _emit_graveyard_changed(side: GameConstants.Side) -> void:
	if effect_manager and effect_manager.has_method("notify_graveyard_changed"):
		effect_manager.notify_graveyard_changed(side)


func apply_life_restore(side: GameConstants.Side) -> bool:
	var deck := get_deck(side)
	var opponent := GameConstants.opposite_side(side)
	if deck.deck.is_empty():
		return false
	deck.hand_limit -= 1
	var card_id: int = deck.deck[0]
	var card_name := CardRegistry.id_to_name(card_id)
	var card_uuid := 0
	var card_rarity := CardRarity.Tier.N
	if not deck._deck_uuids.is_empty():
		card_uuid = deck._deck_uuids[0]
		deck._deck_uuids.remove_at(0)
	if not deck._deck_rarities.is_empty():
		card_rarity = deck._deck_rarities[0]
		deck._deck_rarities.remove_at(0)
	deck.deck.remove_at(0)
	deck.push_card_to_life(card_id, card_uuid, card_rarity)
	if _should_record():
		var net_side := GameSession.get_active().local_side_to_network(side)
		recorder.record_move(
			card_uuid, card_name, "deck", "life", net_side, false, -1, -1, card_rarity, card_id
		)
		recorder.record({"op": "HAND_LIMIT", "side": net_side, "value": deck.hand_limit})
	deck._update_deck_ui()
	if phase_manager.has_method("_update_life_ui"):
		phase_manager._update_life_ui()
	return true


func ask_effect_confirm(card: Node) -> bool:
	if is_com_side(card.owner_side):
		return true
	if effect_manager and bool(effect_manager.get("_skip_effect_confirm")):
		return true
	if effect_manager and effect_manager.has_method("await_effect_confirm"):
		return await effect_manager.await_effect_confirm(card)
	if effect_manager and effect_manager.has_method("ask_effect_confirm"):
		return await effect_manager.ask_effect_confirm(card)
	return true


func ask_priority_popup(card: Node) -> bool:
	if is_com_side(card.owner_side):
		return true
	if effect_manager and effect_manager.has_method("await_priority_decision"):
		return await effect_manager.await_priority_decision(card, [card])
	if effect_manager and effect_manager.has_method("ask_priority_popup"):
		return await effect_manager.ask_priority_popup(card)
	return true


func select_card_from(
	candidates: Array,
	count: int,
	source: Node,
	variable_max_count: int = -1,
	selection_hint: Dictionary = {}
) -> Array:
	if effect_manager and effect_manager.has_method("select_cards"):
		var hint := selection_hint.duplicate()
		if variable_max_count >= 0:
			hint["variableMaxCount"] = variable_max_count
		return await effect_manager.select_cards(candidates, count, source, hint)
	return candidates.slice(0, count) if candidates.size() >= count else candidates


func show_graveyard_for_selection(display_cards: Array, selectable_cards: Array = []) -> void:
	if effect_manager and effect_manager.has_method("show_graveyard_selection"):
		effect_manager.show_graveyard_selection(display_cards, selectable_cards)


func hide_graveyard_panel() -> void:
	if effect_manager and effect_manager.has_method("hide_graveyard_panel"):
		effect_manager.hide_graveyard_panel()
