extends EffectAction
class_name KillCard

## 대상 카드를 파괴한다.
func execute(_source: Node, _targets: Array, _value: int, ctx: EffectContext = null) -> void:
	for card in _targets:
		if is_instance_valid(card):
			await ctx.destroy_card(card, false)
