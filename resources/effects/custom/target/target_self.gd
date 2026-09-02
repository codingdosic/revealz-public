extends EffectTarget
class_name SelfTarget

func getTarget(
	_source: Node,
	_phase: GameConstants.Phase,
	_targetNum: int,
	_target: EffectTypes.Target,
	_targetLocation: EffectTypes.Location,
	_cost: int = 0,
	_executionContext: Array = [],
	_ctx: EffectContext = null
) -> Array:
	return [_source]
