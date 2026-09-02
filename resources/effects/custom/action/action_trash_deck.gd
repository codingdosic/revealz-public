extends EffectAction
class_name TrashDeck

## 소유자 덱에서 카드를 묘지로 보낸다.
func execute(_source: Node, _targets: Array, _value: int, ctx: EffectContext = null) -> void:
	ctx.mill_deck_to_graveyard(_source.owner_side, _value)
