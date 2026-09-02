extends EffectStepBase
class_name StepSkillImmune

## STACK 트리거 — 호스트가 상대 스킬 선택 대상에서 제외됨 (숲속의 요정)


func run(source: Node, _run_ctx: EffectPipelineRunContext) -> void:
	if source == null or not is_instance_valid(source):
		return
	if source.has_method("set_skill_immune_from_stack"):
		source.set_skill_immune_from_stack(true)
	else:
		source.set("skill_immune_from_stack", true)
