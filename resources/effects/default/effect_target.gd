extends Resource
class_name EffectTarget

## 대상 카드 배열을 반환한다. EM._trigger_card_effects가 context와 함께 호출.
func getTarget(
	_source: Node,
	_phase: GameConstants.Phase,
	targetNum: int,
	target: EffectTypes.Target,
	targetLocation: EffectTypes.Location,
	cost: int = 0,
	executionContext: Array = [],
	ctx: EffectContext = null
) -> Array:
	return []
