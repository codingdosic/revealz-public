extends EffectCondition
class_name HandCount

func isMet(_source: Node, _phase: GameConstants.Phase, cost: int = 0, ctx: EffectContext = null) -> bool:
	if ctx == null:
		return false
	var side: GameConstants.Side = _source.owner_side
	return ctx.hand_count(side) >= cost
