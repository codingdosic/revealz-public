extends EffectStepBase
class_name StepStoreCardStat

enum StatKind { SPD, STAT_L, STAT_C, STAT_R }

## 저장된 카드(Array)에서 첫 카드를 꺼내 스탯을 store_key로 저장.
@export_group("입력")
@export var cards_key: String = "bound_cards"
@export var stat: StatKind = StatKind.SPD
@export_group("출력")
@export var store_key: String = "value"


func run(_source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var cards: Array = []
	if run_ctx.step_results.has(cards_key):
		var stored = run_ctx.step_results[cards_key]
		if stored is Array:
			cards = stored
	if cards.is_empty():
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	# NOTE: cards[0] is Variant; don't use := inference here.
	var card = cards[0]
	if card == null or not is_instance_valid(card):
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return

	var v := 0
	match stat:
		StatKind.SPD:
			v = int(card.get("stat_spd")) if card.get("stat_spd") != null else int(card.stat_spd)
		StatKind.STAT_L:
			v = int(card.stat_l)
		StatKind.STAT_C:
			v = int(card.stat_c)
		StatKind.STAT_R:
			v = int(card.stat_r)
	if not store_key.is_empty():
		run_ctx.store(store_key, v)
