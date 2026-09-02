extends EffectTarget
class_name SelectOneGraveyard

@export var targetRange: int = 0


func getAllEffectTargets(
	_source: Node,
	target: EffectTypes.Target,
	_targetLocation: EffectTypes.Location,
	ctx: EffectContext = null
) -> Array:
	return ctx.get_cards_in_location(
		_source.owner_side,
		EffectTypes.Location.GRAVE,
		target,
		_source,
		"TRASH"
	)


func getTarget(
	_source: Node,
	_phase: GameConstants.Phase,
	targetNum: int,
	target: EffectTypes.Target,
	targetLocation: EffectTypes.Location,
	_cost: int = 0,
	executionContext: Array = [],
	ctx: EffectContext = null
) -> Array:
	var display_array := getAllEffectTargets(_source, target, targetLocation, ctx)
	var use_pool := _should_use_execution_pool(ctx, executionContext)

	if use_pool:
		display_array = _filter_cards_in_context(display_array, executionContext)
	elif executionContext:
		display_array = display_array.filter(
			func(card: Node) -> bool: return not _card_in_array(card, executionContext)
		)

	if targetRange > 0 and not use_pool:
		display_array = _apply_target_range(display_array, target, targetRange)

	if ctx.current_effect_action is Reborn:
		display_array = ctx.filter_reborn_graveyard_cards(_source, display_array, ctx.current_effect_all_line)

	var selectable_array := display_array.duplicate()
	if ctx.current_effect_action is Reborn:
		selectable_array = selectable_array.filter(CardDisplayHelpers.is_unit_card)

	ctx.show_graveyard_for_selection(display_array, selectable_array)
	var result: Array = await ctx.select_card_from(selectable_array, targetNum, _source)
	ctx.hide_graveyard_panel()
	return result


func _should_use_execution_pool(ctx: EffectContext, executionContext: Array) -> bool:
	if executionContext.is_empty():
		return false
	if not (ctx.current_effect_action is Reborn):
		return false
	for card in executionContext:
		if not is_instance_valid(card):
			return false
		if card.zone != EffectTypes.Location.GRAVE:
			return false
	return true


func _filter_cards_in_context(cards: Array, executionContext: Array) -> Array:
	var filtered: Array = []
	for card in cards:
		if _card_in_array(card, executionContext):
			filtered.append(card)
	return filtered


func _apply_target_range(cards: Array, target: EffectTypes.Target, range_count: int) -> Array:
	if range_count <= 0:
		return cards
	var by_side: Dictionary = {
		GameConstants.Side.PLAYER: [],
		GameConstants.Side.OPPONENT: [],
	}
	for card in cards:
		if not is_instance_valid(card):
			continue
		var side: GameConstants.Side = card.owner_side
		if by_side.has(side):
			by_side[side].append(card)

	var result: Array = []
	var sides: Array = []
	match target:
		EffectTypes.Target.ALLY:
			sides = [GameConstants.Side.PLAYER]
		EffectTypes.Target.OPPONENT:
			sides = [GameConstants.Side.OPPONENT]
		EffectTypes.Target.BOTH:
			sides = [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]

	for side in sides:
		var side_cards: Array = by_side.get(side, [])
		if side_cards.is_empty():
			continue
		var start := maxi(0, side_cards.size() - range_count)
		for i in range(start, side_cards.size()):
			result.append(side_cards[i])
	return result


func _card_in_array(card: Node, arr: Array) -> bool:
	for candidate in arr:
		if candidate == card:
			return true
		if (
			is_instance_valid(candidate)
			and is_instance_valid(card)
			and candidate.get("instance_id") != null
			and card.get("instance_id") != null
			and candidate.instance_id == card.instance_id
		):
			return true
	return false
