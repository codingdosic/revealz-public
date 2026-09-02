extends EffectCondition
class_name CardOnAllyField

func isMet(_source: Node, _phase: GameConstants.Phase, cost: int = 0, ctx: EffectContext = null) -> bool:
	if ctx == null:
		return false
	var side: GameConstants.Side = _source.owner_side
	var trigger := _get_trigger(_source)
	if trigger == "OPEN":
		var source_line := ctx.line_of_card(_source)
		if source_line < 0:
			return false
		var count := 0
		for slot in ctx.field_manager._slots_by_side.get(side, []):
			if slot.card_in_slot and slot.line == source_line:
				count += 1
		return count >= cost if cost > 0 else count > 0
	var count := 0
	for slot in ctx.field_manager._slots_by_side.get(side, []):
		if slot.card_in_slot:
			count += 1
	return count >= cost if cost > 0 else count > 0


func _get_trigger(source: Node) -> String:
	if source == null or not source.card_data or source.card_data.effects.is_empty():
		return "OPEN"
	return source.card_data.effects[0].trigger
