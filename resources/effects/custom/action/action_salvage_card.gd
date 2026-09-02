extends EffectAction
class_name SalvageCard

## 대상 카드를 손으로 회수한다.
func execute(_source: Node, _targets: Array, _value: int, ctx: EffectContext = null) -> void:
	for card in _targets:
		if is_instance_valid(card):
			await ctx.salvage_to_hand(card)
