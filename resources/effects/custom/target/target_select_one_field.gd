extends EffectTarget
class_name SelectOneField

func getAllEffectTargets(
	_source: Node,
	target: EffectTypes.Target,
	targetLocation: EffectTypes.Location,
	ctx: EffectContext = null
) -> Array:
	var trigger := ctx.current_effect_trigger
	if trigger == "" and _source.card_data and not _source.card_data.effects.is_empty():
		trigger = _source.card_data.effects[0].trigger
	var cards := ctx.get_cards_in_location(
		_source.owner_side, targetLocation, target, _source, trigger
	)
	return ctx.filter_field_cards_by_line(cards, _source, ctx.current_effect_all_line)


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
	var target_array := getAllEffectTargets(_source, target, targetLocation, ctx)
	var needed := mini(targetNum, target_array.size())
	if needed <= 0:
		return []
	return await ctx.select_card_from(target_array, needed, _source)
