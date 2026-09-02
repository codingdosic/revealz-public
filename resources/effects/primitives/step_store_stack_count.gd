extends EffectStepBase
class_name StepStoreStackCount

## 호스트 유닛의 stack_cards 수를 run_ctx에 저장한다.
@export_group("대상")
@export var use_self: bool = true
@export var targets_key: String = "targets"
@export_group("출력")
@export var store_key: String = "stack_count"


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var host: Node = source
	if not use_self:
		if run_ctx.step_results.has(targets_key):
			var stored = run_ctx.step_results[targets_key]
			if stored is Array and not stored.is_empty():
				host = stored[0]
			elif stored != null:
				host = stored
	var count := 0
	if host != null and is_instance_valid(host) and host.get("stack_cards"):
		count = host.stack_cards.size()
	if not store_key.is_empty():
		run_ctx.store(store_key, count)
