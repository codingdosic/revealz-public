extends EffectAction
class_name Reborn

## 대상 카드를 묘지에서 필드로 부활시킨다.
func execute(source: Node, targets: Array, _value: int, ctx: EffectContext = null) -> void:
	var all_line := ctx.current_effect_all_line
	for card in targets:
		if not is_instance_valid(card):
			continue
		var slot: CardSlot = await ctx.select_reborn_slot(source, card, all_line)
		if slot:
			await ctx.reborn_to_field(card, slot)
