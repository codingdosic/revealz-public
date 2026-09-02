extends EffectAction
class_name ChangeAllStats

## 대상 카드의 모든 스탯을 변경한다.
func execute(_source: Node, _targets: Array, _value: int, ctx: EffectContext = null) -> void:
	for target in _targets:
		if is_instance_valid(target) and target.has_method("change_all_stats"):
			target.change_all_stats(_value)
			target.update_labels()
			if ctx:
				ctx.record_stat_change(target, _value)
