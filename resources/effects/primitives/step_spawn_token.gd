extends EffectStepBase
class_name StepSpawnToken

@export var token_card_name: String = "기사"
## IdKey A: >0이면 토큰 CardData.id 우선, 0이면 token_card_name 폴백.
@export var token_card_id: int = 0
@export var count: int = 1
@export var slot_key: String = "slot"
@export var slots_key: String = ""
@export var store_key: String = ""
@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER


## preflight: 슬롯 수 충분하거나 선행 SelectSlot 키가 있으면 통과.
func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var slots := _resolve_slots(run_ctx)
	if slots.size() >= count:
		return true
	# StepSelectSlot 등 선행 스텝이 run 시 slot_key를 채운다 — preflight 시점엔 비어 있음
	if not slot_key.is_empty() or not slots_key.is_empty():
		return true
	return not abort_on_fail


## 슬롯에 토큰을 스폰한다. token_card_id>0이면 id, 아니면 name.
func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	var side := EffectZoneQuery.resolve_side(source, relative_side)
	var slots := _resolve_slots(run_ctx)
	if slots.is_empty():
		if abort_on_fail:
			run_ctx.store("_abort", true)
		return
	var spawn_count := mini(count, slots.size())
	var spawned: Array = []
	for i in range(spawn_count):
		var slot: CardSlot = slots[i] as CardSlot
		if slot == null:
			continue
		var card: Node2D = null
		if token_card_id > 0:
			card = await ctx.spawn_token_to_field_by_id(token_card_id, slot, side)
		else:
			card = await ctx.spawn_token_to_field(token_card_name, slot, side)
		if card != null:
			spawned.append(card)
	if not store_key.is_empty():
		run_ctx.store(store_key, spawned)


## run_ctx에서 slots_key 배열 또는 slot_key 단일 슬롯을 꺼낸다.
func _resolve_slots(run_ctx: EffectPipelineRunContext) -> Array:
	if not slots_key.is_empty() and run_ctx.step_results.has(slots_key):
		var stored = run_ctx.step_results[slots_key]
		if stored is Array:
			return stored
	if not slot_key.is_empty():
		var slot: CardSlot = run_ctx.get_stored(slot_key) as CardSlot
		if slot:
			return [slot]
	return []
