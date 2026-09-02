## 레거시 EffectBundle 액션 베이스. EM이 ctx를 주입한다 (S3 DI).
extends Resource
class_name EffectAction

## 효과를 적용한다. EM._trigger_card_effects가 context와 함께 호출.
func execute(_source: Node, _targets: Array, _value: int, _ctx: EffectContext = null) -> void:
	pass
