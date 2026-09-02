extends EffectAction
class_name ChangeStat

## 대상 카드의 스탯을 변경하고 UI를 갱신한다.
func execute(_source: Node, _targets: Array, _value: int, ctx: EffectContext = null) -> void:
	for target in _targets:
		if is_instance_valid(target) and target.has_method("change_stat_on_field_line"):
			target.change_stat_on_field_line(_value)
			if ctx:
				var line := ctx.line_of_card(target)
				ctx.record_stat_change(target, _value, line)
		elif is_instance_valid(target) and target.has_method("change_stat"):
			target.change_stat(_value)
			target.update_labels()
			if ctx:
				ctx.record_stat_change(target, _value)
	if ctx:
		ctx._refresh_line_power_ui()
