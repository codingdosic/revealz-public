extends EffectAction
class_name TrashOpponentDeck

## 상대 덱에서 카드를 묘지로 보낸다.
func execute(_source: Node, _targets: Array, _value: int, ctx: EffectContext = null) -> void:
	var opp := GameConstants.opposite_side(_source.owner_side)
	ctx.mill_deck_to_graveyard(opp, _value)
