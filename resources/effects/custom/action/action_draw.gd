extends EffectAction
class_name Draw

## 소유자 덱에서 카드를 뽑는다. EM이 ctx를 주입한다.
func execute(_source: Node, _targets: Array, _value: int, ctx: EffectContext = null) -> void:
	if ctx == null or _source == null:
		return
	var side: GameConstants.Side = _source.owner_side
	ctx.draw_cards(side, _value)
