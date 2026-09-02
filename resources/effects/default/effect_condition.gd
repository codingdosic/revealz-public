## 레거시 EffectBundle 조건 베이스. EM이 ctx를 주입한다 (S3 DI).
extends Resource
class_name EffectCondition

## 조건 충족 여부. EM can_trigger / _trigger_card_effects가 호출.
func isMet(_source: Node, _phase: GameConstants.Phase, cost: int = 0, _ctx: EffectContext = null) -> bool:
	return true
