extends EffectCondition
class_name CardOnOpponentGraveyard

func isMet(_source: Node, _phase: GameConstants.Phase, cost: int = 0, ctx: EffectContext = null) -> bool:
	if ctx == null:
		return false
	var side := GameConstants.opposite_side(_source.owner_side)
	return ctx.grave_count(side) >= cost
