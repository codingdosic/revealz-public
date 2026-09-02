## 네트워크 EFFECT_RESULT 변경을 클라/프레젠터에 적용한다.
## EffectManager.setup이 EffectContext를 주입한다 (S3 DI). 기록(record)는 하지 않음.
class_name EffectChangeApplier
extends RefCounted

## EM.setup이 주입한 매치 EffectContext.
var _context: EffectContext
var _applied_keys: Dictionary = {}


## 매치 EffectContext를 연결한다. EM.setup (또는 lazy 생성 경로)이 호출.
func setup(context: EffectContext) -> void:
	_context = context


## 창 단위 적용 키 캐시를 비운다 (리매치·세션 리셋).
func reset_session() -> void:
	_applied_keys.clear()


## changes 배열을 순회 적용한 뒤 PASSIVE 재계산을 스케줄한다.
## 연속 STAT(동일 source·delta·fx)는 한 번에 EffectFx(병렬 투사체/라인웨이브).
func apply_changes(
	changes: Array,
	phase_manager: Node,
	window_id: int = 0
) -> void:
	if phase_manager == null:
		return
	var i := 0
	while i < changes.size():
		var change = changes[i]
		if change is Dictionary and String(change.get("op", "")) == "STAT":
			var batch := _collect_stat_batch(changes, i)
			await _apply_stat_batch(phase_manager, batch, window_id)
			i += batch.size()
		elif change is Dictionary:
			await _apply_one(change, phase_manager, window_id)
			i += 1
		else:
			i += 1
	# MOVE/SPAWN/STAT 배치 후 PASSIVE 재계산 — 토큰 소환 직후 이즈라엘 버프 등(B4)
	if _context:
		_context.schedule_passive_refresh()


## 연속 STAT를 같은 FX 배치로 묶는다 (sourceUuid·delta·fx 일치).
func _collect_stat_batch(changes: Array, start: int) -> Array:
	var first: Dictionary = changes[start]
	var batch: Array = [first]
	var key := _stat_batch_key(first)
	var j := start + 1
	while j < changes.size():
		var next = changes[j]
		if not (next is Dictionary) or String(next.get("op", "")) != "STAT":
			break
		if _stat_batch_key(next) != key:
			break
		batch.append(next)
		j += 1
	return batch


## STAT 배치 키. 동일하면 한 번 EffectFx.
func _stat_batch_key(change: Dictionary) -> String:
	var stats: Dictionary = change.get("stats", {})
	var delta := int(stats.get("delta", 0)) if stats.has("delta") else 0
	var source_uuid := int(change.get("sourceUuid", 0))
	var fx: Variant = change.get("fx", {})
	return "%d:%d:%s" % [source_uuid, delta, str(fx)]


## STAT 배치 — 스탯 적용은 apply_cb, 연출은 opts에 따라 1회.
func _apply_stat_batch(pm: Node, batch: Array, window_id: int) -> void:
	if batch.is_empty():
		return
	var cards: Array = []
	var first: Dictionary = batch[0]
	for change in batch:
		if not (change is Dictionary):
			continue
		var key := "%d:%s:%s" % [window_id, "STAT", str(change)]
		if _applied_keys.has(key):
			continue
		_applied_keys[key] = true
		var uuid := int(change.get("uuid", 0))
		var card := _find_card(pm, uuid)
		if card == null:
			continue
		cards.append({"card": card, "change": change})
	if cards.is_empty():
		return

	var stats0: Dictionary = first.get("stats", {})
	var delta := int(stats0.get("delta", 0)) if stats0.has("delta") else 0
	var source_uuid := int(first.get("sourceUuid", 0))
	var fx: Dictionary = {}
	var raw_fx: Variant = first.get("fx", {})
	if raw_fx is Dictionary:
		fx = (raw_fx as Dictionary).duplicate(true)

	var apply_cb := func() -> void:
		for item in cards:
			var card: Node = item["card"]
			var change: Dictionary = item["change"]
			if not is_instance_valid(card):
				continue
			var stats: Dictionary = change.get("stats", {})
			var has_abs := stats.has("l") or stats.has("c") or stats.has("r")
			if has_abs:
				if stats.has("l"):
					card.stat_l = int(stats["l"])
				if stats.has("c"):
					card.stat_c = int(stats["c"])
				if stats.has("r"):
					card.stat_r = int(stats["r"])
			elif stats.has("delta"):
				var d := int(stats.get("delta", 0))
				if stats.has("line"):
					if card.has_method("change_stat_on_field_line"):
						card.change_stat_on_field_line(d)
				elif card.has_method("change_stat"):
					card.change_stat(d)
			if card.has_method("update_labels"):
				card.update_labels()
		if pm.has_method("_update_line_power_labels"):
			pm._update_line_power_labels()

	if delta == 0 or source_uuid <= 0:
		apply_cb.call()
		return
	var source := _find_card(pm, source_uuid)
	var targets: Array = []
	for item in cards:
		targets.append(item["card"])
	if bool(fx.get("line_wave", false)):
		await EffectFx.await_line_wave(source, targets, delta, fx, apply_cb)
	elif bool(fx.get("aura_only", false)):
		await EffectFx.await_aura_batch(targets, delta, fx, apply_cb)
	else:
		await EffectFx.await_modify_stat(source, targets, delta, fx, apply_cb)


## op별 핸들러로 분기한다. window_id+op+payload로 중복 적용을 막는다.
func _apply_one(change: Dictionary, pm: Node, window_id: int) -> void:
	var op := String(change.get("op", ""))
	var key := "%d:%s:%s" % [window_id, op, str(change)]
	if _applied_keys.has(key):
		return
	_applied_keys[key] = true

	match op:
		"REVEAL":
			_apply_reveal(pm, int(change.get("uuid", 0)))
		"ACTIVATE":
			await _apply_activate(pm, change)
		"MOVE":
			await _apply_move(pm, change)
		"DESTROY":
			await _apply_destroy(pm, change)
		"STAT":
			await _apply_stat(pm, change)
		"SPAWN":
			await _apply_spawn(pm, change)
		"ZONE_SNAPSHOT":
			_apply_zone_snapshot(pm, change)
		"HAND_LIMIT":
			_apply_hand_limit(pm, change)
		"STACK_ATTACH":
			await _apply_stack_attach(pm, change)
		"EFFECT_SET":
			_apply_effect_set(pm, change)
		"SWAP_FIELD":
			await _apply_swap_field(pm, change)
		_:
			push_warning("EffectChangeApplier: unknown op %s" % op)


## PM._find_card_by_uuid로 필드/핸드 등에서 카드를 찾는다.
func _find_card(pm: Node, uuid: int) -> Node2D:
	if uuid <= 0:
		return null
	if pm.has_method("_find_card_by_uuid"):
		return pm._find_card_by_uuid(uuid)
	return null


## 묘지 presenter 노드에서 uuid로 카드를 찾는다.
func _find_graveyard_card(pm: Node, uuid: int, side: GameConstants.Side) -> Node:
	if _context == null:
		return null
	for card in _context.graveyard_nodes.get(side, []):
		if is_instance_valid(card) and int(card.network_uuid) == uuid:
			return card
	return null


## change dict에서 catalog id를 해석한다. cardId 우선, 없으면 name_to_id.
func _resolve_change_card_id(change: Dictionary) -> int:
	var cid := int(change.get("cardId", 0))
	if cid > 0:
		return cid
	return CardRegistry.name_to_id(String(change.get("name", "")))


## 필드/묘지에 없으면 덱에서 스폰해 노드를 확보한다 (프레젠터 lag 대비).
func _ensure_card_node(
	pm: Node,
	uuid: int,
	name: String,
	local_side: GameConstants.Side,
	rarity: int = CardRarity.Tier.N,
	card_id: int = 0
) -> Node2D:
	var card := _find_card(pm, uuid)
	if card:
		return card
	card = _find_graveyard_card(pm, uuid, local_side)
	if card:
		return card
	var deck := _deck_for_side(pm, local_side)
	var resolved_id := card_id if card_id > 0 else CardRegistry.name_to_id(name)
	if resolved_id > 0:
		return deck.spawn_card_by_id(resolved_id, false, uuid, rarity)
	if uuid <= 0 or name.is_empty():
		return null
	return deck.spawn_card_by_name(name, false, uuid, rarity)


## 네트워크 side/line/slotIndex를 로컬 CardSlot으로 해석한다.
func _resolve_field_slot(
	pm: Node,
	net_side: int,
	raw_line: int,
	raw_slot_index: int
) -> CardSlot:
	if pm.has_method("resolve_field_slot_from_network"):
		return pm.resolve_field_slot_from_network(net_side, raw_line, raw_slot_index)
	return null


## 네트워크 side를 로컬 Side로 변환한다.
func _local_side(pm: Node, net_side: int) -> GameConstants.Side:
	var session := GameSession.get_active()
	return session.network_side_to_local(net_side)


## 로컬 side에 해당하는 DeckZone을 반환한다.
func _deck_for_side(pm: Node, local_side: GameConstants.Side) -> DeckZone:
	return pm.player_deck if local_side == GameConstants.Side.PLAYER else pm.opponent_deck


## 로컬 side에 해당하는 핸드 매니저를 반환한다.
func _hand_for_side(pm: Node, local_side: GameConstants.Side) -> Node:
	return pm.player_hand if local_side == GameConstants.Side.PLAYER else pm.opponent_hand


## REVEAL op — 카드 공개 연출.
func _apply_reveal(pm: Node, uuid: int) -> void:
	var card := _find_card(pm, uuid)
	if card and card.has_method("reveal"):
		card.reveal()


## ACTIVATE op — 발동 확정 후 ActivationFx (필드 펄스 / 존 peek).
func _apply_activate(pm: Node, change: Dictionary) -> void:
	var card := _find_card(pm, int(change.get("uuid", 0)))
	if card == null:
		return
	await ActivationFx.await_play_for_source(card, String(change.get("trigger", "")))


## change.vfx를 context 이동 오버라이드로 켠다.
func _begin_change_vfx(change: Dictionary) -> void:
	if _context == null:
		return
	var vfx: Variant = change.get("vfx", {})
	if vfx is Dictionary and not (vfx as Dictionary).is_empty():
		_context.begin_move_vfx(vfx)


## 이동 오버라이드를 해제한다.
func _end_change_vfx() -> void:
	if _context:
		_context.end_move_vfx()


## 필드/핸드에 없으면 묘지 또는 덱 스폰으로 노드를 확보한다. spawned=덱에서 새로 만든 경우.
func _resolve_move_card(
	pm: Node,
	uuid: int,
	name: String,
	local_side: GameConstants.Side,
	rarity: int,
	card_id: int
) -> Dictionary:
	var card := _find_card(pm, uuid)
	if card:
		return {"card": card, "spawned": false}
	card = _find_graveyard_card(pm, uuid, local_side)
	if card:
		return {"card": card, "spawned": false}
	var deck := _deck_for_side(pm, local_side)
	var resolved_id := card_id if card_id > 0 else CardRegistry.name_to_id(name)
	if resolved_id > 0:
		card = deck.spawn_card_by_id(resolved_id, false, uuid, rarity)
	elif uuid > 0 and not name.is_empty():
		card = deck.spawn_card_by_name(name, false, uuid, rarity)
	return {"card": card, "spawned": card != null}


## 덱/라이프/묘지/제외에서 출발하는 연출 시작점을 로컬과 같게 맞춘다.
func _place_origin_for_from_zone(
	card: Node2D,
	from_zone: String,
	local_side: GameConstants.Side,
	deck: DeckZone,
	spawned: bool
) -> void:
	if card == null or not is_instance_valid(card):
		return
	match from_zone:
		"deck":
			if spawned:
				deck._place_card_at_deck_for_draw_fx(card)
				card.visible = true
				card.set("zone", EffectTypes.Location.DECK)
		"life":
			if spawned:
				deck._place_card_at_life_for_hand_fx(card)
				card.visible = true
		"grave":
			if _context:
				card.global_position = _context.graveyard_world_pos(local_side)
				card.visible = true
		"banishzone":
			if _context:
				card.global_position = _context.banish_world_pos(local_side)
				card.visible = true


## 라이프 존 도착 좌표. LifeContainer가 없으면 덱 더미.
func _life_arrive_pos(pm: Node, local_side: GameConstants.Side, deck: DeckZone) -> Vector2:
	var node_name := (
		"PlayerLifeContainer" if local_side == GameConstants.Side.PLAYER else "OpponentLifeContainer"
	)
	var display := FieldBoardBuilder.find_under_field(pm, node_name) as Node2D
	if display:
		return display.global_position
	return deck.global_position


## 실카드를 to까지 MatchVfx로 날린다. headless는 snap.
func _await_fly_card(card: Node2D, to: Vector2, local_side: GameConstants.Side) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.visible = true
	if not MatchVfx.is_active():
		card.global_position = to
		return
	var params := MatchVfx.default_field_params(MatchVfx.face_for_hand_side(local_side))
	if _context:
		params = _context.apply_move_vfx(params)
	params["from"] = card.global_position
	params["to"] = to
	await MatchVfx.await_card_move(card, params)


## 패/필드/스택에서 떼고 묘지·제외 목록에서도 뺀다 (덱·라이프 회수용).
func _detach_card_leaving_board(pm: Node, card: Node, ctx: EffectContext) -> void:
	if card == null or not is_instance_valid(card):
		return
	for h in [
		_hand_for_side(pm, GameConstants.Side.PLAYER),
		_hand_for_side(pm, GameConstants.Side.OPPONENT),
	]:
		if h and h.has_method("remove_card_from_hand"):
			h.remove_card_from_hand(card)
	if card.card_slot_card_is_in and pm.field_manager:
		pm.field_manager.remove_card_from_slot(card)
	if ctx:
		if card.stack_host != null:
			ctx.detach_from_stack(card)
		ctx.unregister_reveal_select_card(card)
		for s in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
			ctx.graveyard_nodes[s].erase(card)
			ctx.banishzone_nodes[s].erase(card)


## MOVE op — toZone별 존 이동을 context API로 재현한다 (record 없음).
func _apply_move(pm: Node, change: Dictionary) -> void:
	_begin_change_vfx(change)
	var uuid := int(change.get("uuid", 0))
	var name := String(change.get("name", ""))
	var from_zone := String(change.get("fromZone", ""))
	var to_zone := String(change.get("toZone", ""))
	var net_side := int(change.get("side", 0))
	var rarity := int(change.get("rarity", CardRarity.Tier.N))
	var card_id := _resolve_change_card_id(change)
	var local_side := _local_side(pm, net_side)
	var ctx := _context
	var deck := _deck_for_side(pm, local_side)
	var hand := _hand_for_side(pm, local_side)

	var resolved: Dictionary = _resolve_move_card(pm, uuid, name, local_side, rarity, card_id)
	var card: Node2D = resolved.get("card")
	var spawned := bool(resolved.get("spawned", false))

	match to_zone:
		"hand":
			if card and hand.has_method("add_card_to_hand"):
				var from_pos := card.global_position
				if from_zone == "stack" and card.stack_host is Node2D:
					from_pos = (card.stack_host as Node2D).global_position
				if card.card_slot_card_is_in:
					pm.field_manager.remove_card_from_slot(card)
					if card.has_method("reset_runtime_stats_from_card_data"):
						card.reset_runtime_stats_from_card_data()
				if ctx and from_zone == "stack":
					ctx.detach_from_stack(card)
				if ctx:
					ctx.unregister_reveal_select_card(card)
					for s in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
						ctx.graveyard_nodes[s].erase(card)
						ctx.banishzone_nodes[s].erase(card)
				_place_origin_for_from_zone(card, from_zone, local_side, deck, spawned)
				card.visible = true
				card.set("zone", EffectTypes.Location.HAND)
				CardHelpers.prepare_for_hand(card, local_side)
				if from_zone == "field" or from_zone == "stack":
					card.global_position = from_pos
				hand.add_card_to_hand(card, DeckZone.CARD_DRAW_SPEED)
		"grave":
			if card:
				_place_origin_for_from_zone(card, from_zone, local_side, deck, spawned)
			if card and ctx:
				await ctx.move_to_graveyard(card, local_side, bool(change.get("suppressTrash", false)))
		"banishzone":
			if card:
				_place_origin_for_from_zone(card, from_zone, local_side, deck, spawned)
			if card and ctx:
				await ctx.move_to_banishzone(card, local_side, false)
		"field":
			if card:
				_place_origin_for_from_zone(card, from_zone, local_side, deck, spawned)
			var line := int(change.get("line", 0))
			var slot_index := int(change.get("slotIndex", 0))
			var slot: CardSlot = _resolve_field_slot(pm, net_side, line, slot_index)
			if card and slot and ctx:
				if from_zone == "field" and card.card_slot_card_is_in:
					await ctx.relocate_field_to_slot(card, slot)
				else:
					await ctx.reborn_to_field(card, slot)
				if pm.has_method("_update_line_power_labels"):
					pm._update_line_power_labels()
		"life":
			var life_id := card_id
			if life_id <= 0 and card and is_instance_valid(card):
				var _cd = card.get("card_data")
				if _cd != null and int(_cd.get("id", 0)) > 0:
					life_id = int(_cd.get("id"))
				else:
					life_id = CardRegistry.name_to_id(name)
			if card and is_instance_valid(card):
				_detach_card_leaving_board(pm, card, ctx)
				await _await_fly_card(card, _life_arrive_pos(pm, local_side, deck), local_side)
				card.visible = false
				card.queue_free()
			if life_id > 0:
				deck.push_card_to_life(life_id, uuid, rarity)
			if pm.has_method("_update_life_ui"):
				pm._update_life_ui()
		"deck":
			var deck_name := name
			var deck_rarity := rarity
			if card and is_instance_valid(card):
				if deck_name.is_empty():
					deck_name = String(card.card_name)
				if not change.has("rarity"):
					deck_rarity = int(
						card.get("instance_rarity")
						if card.get("instance_rarity") != null
						else CardRarity.Tier.N
					)
				# 패에서 제거하지 않으면 queue_free 유령 슬롯으로 빈 자리(지도 교수)가 남음
				_detach_card_leaving_board(pm, card, ctx)
				await _await_fly_card(card, deck.global_position, local_side)
				card.visible = false
				card.set("zone", EffectTypes.Location.DECK)
			var deck_id := card_id
			if deck_id <= 0 and not deck_name.is_empty():
				deck_id = CardRegistry.name_to_id(deck_name)
			if deck_id > 0:
				deck.send_card_to_deck_bottom(deck_id, uuid, deck_rarity)
			if card and is_instance_valid(card):
				card.queue_free()
		_:
			push_warning("EffectChangeApplier: unknown toZone %s" % to_zone)
	_end_change_vfx()


## DESTROY op — 묘지로 이동 (suppressTrash 플래그 유지).
func _apply_destroy(pm: Node, change: Dictionary) -> void:
	_begin_change_vfx(change)
	var uuid := int(change.get("uuid", 0))
	var local_side := _local_side(pm, int(change.get("side", 0)))
	var card := _find_card(pm, uuid)
	if card == null:
		card = _find_graveyard_card(pm, uuid, local_side)
	if card and _context:
		await _context.move_to_graveyard(
			card,
			local_side,
			bool(change.get("suppressTrash", false))
		)
	_end_change_vfx()


## STAT op — 단건. apply_changes 배치 경로 밖 호출용.
func _apply_stat(pm: Node, change: Dictionary) -> void:
	await _apply_stat_batch(pm, [change], 0)

## SPAWN op — 핸드 스폰 또는 필드 토큰 스폰.
func _apply_spawn(pm: Node, change: Dictionary) -> void:
	var uuid := int(change.get("uuid", 0))
	if _find_card(pm, uuid):
		return
	var name := String(change.get("name", ""))
	var zone := String(change.get("zone", "hand"))
	var net_side := int(change.get("side", 0))
	var local_side := _local_side(pm, net_side)
	var reveal := bool(change.get("reveal", false))
	var rarity := int(change.get("rarity", CardRarity.Tier.N))
	var card_id := _resolve_change_card_id(change)
	var deck := _deck_for_side(pm, local_side)
	if zone == "hand":
		var card: Node2D = null
		if card_id > 0:
			card = deck.spawn_card_by_id(card_id, reveal, uuid, rarity)
		elif name != "":
			card = deck.spawn_card_by_name(name, reveal, uuid, rarity)
		if card:
			deck._place_card_at_deck_for_draw_fx(card)
			card.visible = true
			_hand_for_side(pm, local_side).add_card_to_hand(card, DeckZone.CARD_DRAW_SPEED)
		return
	if zone == "field":
		var line := int(change.get("line", 0))
		var slot_index := int(change.get("slotIndex", 0))
		var slot: CardSlot = _resolve_field_slot(pm, net_side, line, slot_index)
		if slot and _context:
			var card := _ensure_card_node(pm, uuid, name, local_side, rarity, card_id)
			if card:
				if card_id > 0:
					await _context.spawn_token_to_field_by_id(card_id, slot, local_side, card)
				else:
					await _context.spawn_token_to_field(name, slot, local_side, card)
		return


## ZONE_SNAPSHOT op — 덱/묘지/밴시/라이프 리스트를 권위 스냅샷으로 맞춘다.
func _apply_zone_snapshot(pm: Node, change: Dictionary) -> void:
	var local_side := _local_side(pm, int(change.get("side", 0)))
	var deck := _deck_for_side(pm, local_side)
	if change.has("handLimit"):
		deck.hand_limit = int(change.get("handLimit", deck.hand_limit))
	if change.has("deckRemaining"):
		deck._apply_deck_remaining(change.get("deckRemaining", []))
	if change.has("graveyardRemaining"):
		deck._apply_graveyard_remaining(change.get("graveyard_remaining", change.get("graveyardRemaining", [])))
		deck.ensure_graveyard_presenter_nodes()
	if change.has("banishRemaining"):
		deck._apply_banishzone_remaining(change.get("banish_remaining", change.get("banishRemaining", [])))
		deck.ensure_banishzone_presenter_nodes()
	if change.has("lifeRemaining"):
		deck._apply_life_remaining(change.get("life_remaining", change.get("lifeRemaining", [])))
	deck._update_deck_ui()
	if pm.has_method("_update_life_ui"):
		pm._update_life_ui()


## HAND_LIMIT op — 핸드 상한을 갱신한다.
func _apply_hand_limit(pm: Node, change: Dictionary) -> void:
	var local_side := _local_side(pm, int(change.get("side", 0)))
	var deck := _deck_for_side(pm, local_side)
	deck.hand_limit = int(change.get("value", deck.hand_limit))
	if pm.has_method("_update_life_ui"):
		pm._update_life_ui()


## STACK_ATTACH op — 스택 부착을 context로 재현한다 (record 억제).
func _apply_stack_attach(pm: Node, change: Dictionary) -> void:
	_begin_change_vfx(change)
	var attached_uuid := int(change.get("attachedUuid", 0))
	var host_uuid := int(change.get("hostUuid", 0))
	var from_zone := String(change.get("fromZone", "unknown"))
	if _context == null:
		_end_change_vfx()
		return
	var host := _find_card(pm, host_uuid)
	if host == null:
		_end_change_vfx()
		return
	var attached := _find_card(pm, attached_uuid)
	var local_side := _local_side(pm, int(change.get("side", 0)))
	var name := String(change.get("name", ""))
	var rarity := int(change.get("rarity", CardRarity.Tier.N))
	var card_id := _resolve_change_card_id(change)
	if attached == null and from_zone == "deck":
		var deck := _deck_for_side(pm, local_side)
		if card_id > 0:
			attached = deck.spawn_card_by_id(card_id, false, attached_uuid, rarity)
		elif name != "":
			attached = deck.spawn_card_by_name(name, false, attached_uuid, rarity)
		if attached:
			deck._place_card_at_deck_for_draw_fx(attached)
			attached.visible = true
			attached.set("zone", EffectTypes.Location.DECK)
	if attached == null:
		_end_change_vfx()
		return
	await _context.attach_to_stack(attached, host, from_zone, false)
	_end_change_vfx()


## SWAP_FIELD op — 두 필드 유닛의 슬롯을 교환하고 PASSIVE를 스케줄한다.
func _apply_swap_field(pm: Node, change: Dictionary) -> void:
	_begin_change_vfx(change)
	var uuid_a := int(change.get("uuidA", 0))
	var uuid_b := int(change.get("uuidB", 0))
	var card_a := _find_card(pm, uuid_a)
	var card_b := _find_card(pm, uuid_b)
	if card_a == null or card_b == null:
		_end_change_vfx()
		return
	var dest_a: Dictionary = change.get("destA", {})
	var dest_b: Dictionary = change.get("destB", {})
	var slot_a: CardSlot = _resolve_field_slot(
		pm,
		int(dest_a.get("side", 0)),
		int(dest_a.get("line", 0)),
		int(dest_a.get("slotIndex", 0))
	)
	var slot_b: CardSlot = _resolve_field_slot(
		pm,
		int(dest_b.get("side", 0)),
		int(dest_b.get("line", 0)),
		int(dest_b.get("slotIndex", 0))
	)
	if slot_a == null or slot_b == null:
		_end_change_vfx()
		return
	var fm = pm.field_manager
	if fm == null:
		_end_change_vfx()
		return
	var from_a: Vector2 = card_a.global_position
	var from_b: Vector2 = card_b.global_position
	if card_a.has_method("clear_passive_field_modifiers"):
		card_a.clear_passive_field_modifiers()
	if card_b.has_method("clear_passive_field_modifiers"):
		card_b.clear_passive_field_modifiers()
	fm.remove_card_from_slot(card_a)
	fm.remove_card_from_slot(card_b)
	fm.place_card_on_slot(card_a, slot_a)
	fm.place_card_on_slot(card_b, slot_b)
	if MatchVfx.is_active():
		card_a.global_position = from_a
		card_b.global_position = from_b
		var pa := MatchVfx.default_field_params(MatchVfx.FACE_KEEP)
		var pb := MatchVfx.default_field_params(MatchVfx.FACE_KEEP)
		if _context:
			pa = _context.apply_move_vfx(pa)
			pb = _context.apply_move_vfx(pb)
		pa["from"] = from_a
		pa["to"] = slot_a.global_position
		pb["from"] = from_b
		pb["to"] = slot_b.global_position
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
	if _context:
		_context.schedule_passive_refresh()
	_end_change_vfx()


## EFFECT_SET op — 세트/해제 비주얼을 적용한다.
func _apply_effect_set(pm: Node, change: Dictionary) -> void:
	var uuid := int(change.get("uuid", 0))
	var card := _find_card(pm, uuid)
	if card == null:
		return
	if bool(change.get("value", true)):
		CardHelpers.apply_effect_set(card)
	else:
		CardHelpers.clear_effect_set(card)
	if pm.has_method("_update_line_power_labels"):
		pm._update_line_power_labels()
