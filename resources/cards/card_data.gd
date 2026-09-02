extends Resource
class_name CardData

@export_group("Basic Info")
@export var card_name: String = "cardName"
@export var illustration: Texture2D
@export var illustration_back: Texture2D
@export var id: int
@export var uuid: int
@export_enum("Unit", "Spell") var card_type: String
## 색 플래그. CardRegistry 필터·mono 허용 판정 SSOT (폴더명과 무관).
@export_flags("BLACK", "WHITE", "GREEN", "RED", "BLUE", "COLORLESS") var color: int
@export_enum("Knight", "Magician", "Zombie", "Fiend", "Machine", "Giant", "Beast", "Dragon", "Fairy", "Priest", "Angel") var type: String
@export_flags("OPEN", "TRASH", "LIFE", "BIND", "STACK", "PASSIVE", "VANILLA", "TOKEN") var trigger_type: int
## 레어도. N=기본(무표시) · R/SR/UR만 프레임·배지.
@export_enum("N", "R", "SR", "UR") var rarity: int = 0
@export var effect_text: String

@export_group("Stats")
@export var setting_cost: int = 2
@export var stat_l: int = 0
@export var stat_c: int = 0
@export var stat_r: int = 0
@export var stat_spd: int = 0

@export_group("Effects")
@export var oncePerTurn: bool = false
@export_subgroup("Pipeline (신규 — 비어 있지 않으면 우선)")
## EffectPipeline + Step primitive 서브리소스. 카드 .tres 안에서 조립·수정.
@export var pipelines: Array[EffectPipeline] = []
@export_subgroup("EffectBundle (레거시)")
@export var effects: Array[EffectBundle] = []
