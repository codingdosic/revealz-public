extends Resource
class_name EffectStepBase

@export_group("공통")
## 조건·쿼리 실패 시 파이프라인 중단 (런타임 run 기준)
@export var abort_on_fail: bool = true
## true: can_trigger / 진입 preflight에서 이 스텝 조건을 검사.
## false: 앞 스텝 사이드이펙트(밀·스폰·드로우 등)에 의존 — 런타임에만 검사.
## 기존 카드 기본 true 유지. 로스톰 슬롯·키르나쥬 묘지 픽 등이 false.
@export var check_at_preflight: bool = true


func evaluate_preflight(_source: Node, _run_ctx: EffectPipelineRunContext) -> bool:
	return true


func run(_source: Node, _run_ctx: EffectPipelineRunContext) -> void:
	pass
