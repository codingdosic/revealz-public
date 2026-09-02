extends EffectStepBase
class_name StepSelectTargets

## 대상 선택 — EffectBundle.targeter + targetNum 대응
@export_group("대상 진영 · 존")
@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OPPONENT
@export var zone: EffectTypes.EffectZone = EffectTypes.EffectZone.FIELD
@export var line_scope: EffectTypes.LineScope = EffectTypes.LineScope.SAME_AS_SOURCE
@export_group("선택")
## -1 이면 relative_side·zone·line_scope·필터 조건에 맞는 카드 전부(선택 UI 없음)
@export var count: int = 1
@export var count_key: String = ""
## count=-2 가변 선택 시 상한 (예: 루인 — 선택 가능 상대 수)
@export var max_count_key: String = ""
@export var units_only: bool = true
@export var selection_mode: EffectTypes.SelectionMode = EffectTypes.SelectionMode.PLAYER
@export_group("필터")
@export var exclude_source: bool = false
@export var exclude_name_substring: String = ""
@export var exclude_execution_pool: bool = false
@export var use_execution_pool_only: bool = false
@export var include_name_exact: String = ""
@export var require_token: bool = false
@export var include_types: PackedStringArray = PackedStringArray()
@export_group("체인 (선택)")
@export var store_key: String = "targets"


## 존·필터 조건에 맞는 후보 카드 수집. evaluate_preflight·run 공통.
func _gather_candidates(source: Node, run_ctx: EffectPipelineRunContext) -> Array:
	var candidates := EffectZoneQuery.get_cards_in_zone(
		run_ctx.game_context,
		source,
		relative_side,
		zone,
		line_scope,
		units_only,
		exclude_source,
		exclude_name_substring,
		exclude_execution_pool,
		use_execution_pool_only,
		run_ctx.execution_pool,
		include_name_exact,
		require_token,
		include_types,
		EffectZoneQuery.should_filter_skill_immune_targets(relative_side, zone)
	)
	if zone == EffectTypes.EffectZone.GRAVE:
		if use_execution_pool_only:
			candidates = run_ctx.game_context.filter_reborn_graveyard_cards(
				source,
				candidates,
				line_scope == EffectTypes.LineScope.SAME_AS_SOURCE
			)
			if units_only:
				candidates = candidates.filter(CardDisplayHelpers.is_unit_card)
		elif line_scope == EffectTypes.LineScope.SAME_AS_SOURCE:
			candidates = run_ctx.game_context.filter_reborn_graveyard_cards(
				source, candidates, true
			)
			if units_only:
				candidates = candidates.filter(CardDisplayHelpers.is_unit_card)
	return candidates


func _resolve_select_count(run_ctx: EffectPipelineRunContext) -> int:
	if not count_key.is_empty() and run_ctx.step_results.has(count_key):
		return maxi(0, int(run_ctx.step_results[count_key]))
	return count


func _resolve_max_select_count(run_ctx: EffectPipelineRunContext, candidate_count: int) -> int:
	var cap := candidate_count
	if not max_count_key.is_empty() and run_ctx.step_results.has(max_count_key):
		cap = mini(cap, maxi(0, int(run_ctx.step_results[max_count_key])))
	return cap


func _pick_targets(source: Node, candidates: Array, run_ctx: EffectPipelineRunContext) -> Array:
	if candidates.is_empty():
		return []
	var resolved_count := _resolve_select_count(run_ctx)
	if resolved_count == 0 and not count_key.is_empty():
		return []
	if resolved_count == -2:
		var max_cap := _resolve_max_select_count(run_ctx, candidates.size())
		var picked: Array = await run_ctx.game_context.select_card_from(
			candidates, -2, source, max_cap
		)
		if picked.size() > max_cap:
			return picked.slice(0, max_cap)
		return picked
	if resolved_count == -1:
		return candidates.duplicate()
	var needed := mini(resolved_count, candidates.size())
	if needed <= 0:
		return []
	match selection_mode:
		EffectTypes.SelectionMode.RANDOM:
			return EffectZoneQuery.pick_random(candidates, needed)
		EffectTypes.SelectionMode.AUTO:
			if run_ctx.game_context.is_com_side(source.owner_side):
				return EffectZoneQuery.pick_random(candidates, needed)
			return await run_ctx.game_context.select_card_from(candidates, needed, source)
		_:
			if zone == EffectTypes.EffectZone.GRAVE:
				var selectable := candidates.duplicate()
				if units_only:
					selectable = selectable.filter(CardDisplayHelpers.is_unit_card)
				run_ctx.game_context.show_graveyard_for_selection(candidates, selectable)
				var picked: Array = await run_ctx.game_context.select_card_from(
					selectable, needed, source
				)
				run_ctx.game_context.hide_graveyard_panel()
				return picked
			return await run_ctx.game_context.select_card_from(candidates, needed, source)


func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	# Pool is filled by prior mill/move steps — empty at gate time is expected.
	if use_execution_pool_only:
		return true
	var candidates := _gather_candidates(source, run_ctx)
	var resolved_count := _resolve_select_count(run_ctx)
	if resolved_count < 0:
		return true
	if resolved_count == 0:
		return true
	if candidates.is_empty():
		return not abort_on_fail
	return true


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var resolved_count := _resolve_select_count(run_ctx)
	if resolved_count == 0 and not count_key.is_empty():
		if not store_key.is_empty():
			run_ctx.store(store_key, [])
		return
	var candidates := _gather_candidates(source, run_ctx)
	var targets := await _pick_targets(source, candidates, run_ctx)
	if targets.is_empty() and abort_on_fail:
		run_ctx.store("_abort", true)
		return
	run_ctx.current_targets = targets
	if not store_key.is_empty():
		run_ctx.store(store_key, targets)
