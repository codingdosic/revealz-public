extends Resource
class_name EffectBundle

@export var trigger: String = "OPEN"
@export var condition: EffectCondition
@export var cost: int = 0
@export var targeter: EffectTarget
@export var target: EffectTypes.Target
@export var targetLocation: EffectTypes.Location
@export var targetNum: int = 0
@export var action: EffectAction
@export var value: int = 0
@export var allLine: bool = true
