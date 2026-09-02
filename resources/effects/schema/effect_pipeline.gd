extends Resource
class_name EffectPipeline

## EffectBundle 대체 — trigger + steps[] 체인. 카드 .tres 안 서브리소스로 조립.
@export_group("트리거")
@export var trigger: String = "OPEN"
@export_group("스텝 체인 (위→아래 순서)")
## 각 원소에 StepMinCount / StepSelectTargets / StepModifyStat 등 primitive 스크립트를 지정.
@export var steps: Array[EffectStepBase] = []
