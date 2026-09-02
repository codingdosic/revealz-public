extends EffectStepBase
class_name StepMoveCards

enum MoveKind {
	DRAW,
	MILL,
	DESTROY_TARGETS,
	SALVAGE_TARGETS,
	REBORN_TO_SLOT,
	RELOCATE_SELF_TO_SLOT,
	BIND_TARGETS,
	BIND_FROM_DECK_TOP,
	BIND_SELF,
	STACK_FROM_DECK_TOP,
	STACK_TARGETS,
	STACK_TRASH_TARGETS,
	STACK_TO_HAND,
	STACK_GATHER_ALL,
	HAND_TO_DECK_BOTTOM,
	FIELD_TO_HAND,
	RELOCATE_TARGETS_TO_SLOT,
}

@export var kind: MoveKind = MoveKind.DRAW
@export var relative_side: EffectTypes.RelativeSide = EffectTypes.RelativeSide.OWNER
@export var count: int = 1
@export var targets_key: String = "targets"
@export var slot_key: String = "slot"
@export var count_key: String = ""
@export var add_to_execution_pool: bool = false
@export var store_key: String = ""
@export var host_key: String = ""
@export_group("MatchVfx")
enum TrailMode { KEEP_DEFAULT, FORCE_ON, FORCE_OFF }
## KEEP=존 기본(묘지/바인드 on · 필드/패 off). ON=트레일 강제.
@export var fx_trail: TrailMode = TrailMode.KEEP_DEFAULT
## a=0이면 시전 카드 색 기본.
@export var fx_trail_color: Color = Color(0, 0, 0, 0)
@export var fx_trail_width: float = 0.0
@export var fx_move_sec: float = 0.0


## 드로·밀·바인드 등 이동 선행 조건(덱·호스트). can_trigger·파이프라인 게이트.
func evaluate_preflight(source: Node, run_ctx: EffectPipelineRunContext) -> bool:
	var ctx := run_ctx.game_context
	if ctx == null:
		return false
	var side := EffectZoneQuery.resolve_side(source, relative_side)
	var needed := _resolve_count(run_ctx)
	match kind:
		MoveKind.DRAW, MoveKind.MILL, MoveKind.BIND_FROM_DECK_TOP, MoveKind.STACK_FROM_DECK_TOP:
			return ctx.can_supply(side, needed)
		MoveKind.HAND_TO_DECK_BOTTOM:
			return true
		MoveKind.STACK_TARGETS:
			return _resolve_host(source, run_ctx) != null
	return true


func run(source: Node, run_ctx: EffectPipelineRunContext) -> void:
	var ctx := run_ctx.game_context
	if ctx == null:
		return
	var side := EffectZoneQuery.resolve_side(source, relative_side)
	ctx.begin_move_vfx(_build_move_fx_opts(), source)
	await _run_kind(source, run_ctx, ctx, side)
	ctx.end_move_vfx()
	ctx._refresh_line_power_ui()


## kind별 이동. begin/end_move_vfx는 run에서 감싼다.
func _run_kind(
	source: Node, run_ctx: EffectPipelineRunContext, ctx: EffectContext, side: GameConstants.Side
) -> void:
	match kind:
		MoveKind.DRAW:
			ctx.draw_cards(side, _resolve_count(run_ctx))
		MoveKind.MILL:
			await ctx.mill_deck_to_graveyard(side, count)
		MoveKind.DESTROY_TARGETS:
			var targets: Array = _resolve_targets(run_ctx)
			for card in targets:
				if is_instance_valid(card):
					await ctx.destroy_card(card, false)
					if add_to_execution_pool and card not in run_ctx.execution_pool:
						run_ctx.execution_pool.append(card)
		MoveKind.SALVAGE_TARGETS:
			for card in _resolve_targets(run_ctx):
				if is_instance_valid(card):
					await ctx.salvage_to_hand(card)
		MoveKind.REBORN_TO_SLOT:
			var targets: Array = _resolve_targets(run_ctx)
			var slot: CardSlot = run_ctx.get_stored(slot_key) as CardSlot
			if slot == null:
				if abort_on_fail:
					run_ctx.store("_abort", true)
				return
			for card in targets:
				if is_instance_valid(card):
					await ctx.reborn_to_field(card, slot)
		MoveKind.RELOCATE_SELF_TO_SLOT:
			var slot: CardSlot = run_ctx.get_stored(slot_key) as CardSlot
			if slot == null:
				if abort_on_fail:
					run_ctx.store("_abort", true)
				return
			await ctx.reborn_to_field(source, slot)
		MoveKind.BIND_TARGETS:
			var moved: Array = []
			for card in _resolve_targets(run_ctx):
				if is_instance_valid(card):
					await ctx.bind_to_banishzone(card)
					moved.append(card)
					if add_to_execution_pool and card not in run_ctx.execution_pool:
						run_ctx.execution_pool.append(card)
			if not store_key.is_empty():
				run_ctx.store(store_key, moved)
		MoveKind.BIND_FROM_DECK_TOP:
			var moved: Array = await ctx.bind_from_deck_top(side, count)
			if add_to_execution_pool:
				for card in moved:
					if card not in run_ctx.execution_pool:
						run_ctx.execution_pool.append(card)
			if not store_key.is_empty():
				run_ctx.store(store_key, moved)
		MoveKind.BIND_SELF:
			await ctx.bind_to_banishzone(source)
		MoveKind.STACK_FROM_DECK_TOP:
			var host := _resolve_host(source, run_ctx)
			if host == null:
				if abort_on_fail:
					run_ctx.store("_abort", true)
				return
			var moved: Array = await ctx.stack_from_deck_top(host, _resolve_count(run_ctx))
			if not store_key.is_empty():
				run_ctx.store(store_key, moved)
			if add_to_execution_pool:
				for card in moved:
					if card not in run_ctx.execution_pool:
						run_ctx.execution_pool.append(card)
		MoveKind.STACK_TARGETS:
			var host := _resolve_host(source, run_ctx)
			if host == null:
				if abort_on_fail:
					run_ctx.store("_abort", true)
				return
			var attached_list: Array = []
			for card in _resolve_targets(run_ctx):
				if not is_instance_valid(card):
					continue
				var attached_ok: bool = await ctx.attach_to_stack(card, host)
				if attached_ok:
					attached_list.append(card)
					if add_to_execution_pool and card not in run_ctx.execution_pool:
						run_ctx.execution_pool.append(card)
			if not store_key.is_empty():
				run_ctx.store(store_key, attached_list)
		MoveKind.STACK_TRASH_TARGETS:
			var trashed: Array = await ctx.trash_stack_cards(_resolve_targets(run_ctx))
			if not store_key.is_empty():
				run_ctx.store(store_key, trashed.size())
		MoveKind.STACK_TO_HAND:
			for card in _resolve_targets(run_ctx):
				if is_instance_valid(card):
					await ctx.stack_to_hand(card)
		MoveKind.STACK_GATHER_ALL:
			var gathered: Array = await ctx.gather_all_ally_stacks_to_host(source)
			if not store_key.is_empty():
				run_ctx.store(store_key, gathered)
		MoveKind.HAND_TO_DECK_BOTTOM:
			for card in _resolve_targets(run_ctx):
				if is_instance_valid(card):
					await ctx.hand_to_deck_bottom(card)
		MoveKind.FIELD_TO_HAND:
			for card in _resolve_targets(run_ctx):
				if is_instance_valid(card):
					await ctx.field_to_hand(card)
		MoveKind.RELOCATE_TARGETS_TO_SLOT:
			var dest_slot: CardSlot = run_ctx.get_stored(slot_key) as CardSlot
			if dest_slot == null or not dest_slot.is_empty():
				if abort_on_fail:
					run_ctx.store("_abort", true)
				return
			for card in _resolve_targets(run_ctx):
				if is_instance_valid(card):
					await ctx.relocate_field_to_slot(card, dest_slot)


func _resolve_targets(run_ctx: EffectPipelineRunContext) -> Array:
	if not targets_key.is_empty() and run_ctx.step_results.has(targets_key):
		var stored = run_ctx.step_results[targets_key]
		if stored is Array:
			return stored
	if not run_ctx.current_targets.is_empty():
		return run_ctx.current_targets
	return []


func _resolve_count(run_ctx: EffectPipelineRunContext) -> int:
	if not count_key.is_empty() and run_ctx.step_results.has(count_key):
		return maxi(0, int(run_ctx.step_results[count_key]))
	return count


func _resolve_host(source: Node, run_ctx: EffectPipelineRunContext) -> Node:
	if not host_key.is_empty() and run_ctx.step_results.has(host_key):
		var stored = run_ctx.step_results[host_key]
		if stored is Array and not stored.is_empty():
			return stored[0]
		if stored != null:
			return stored
	return source


## 인스펙터 오버라이드만 opts에 넣는다 (0/투명=기본).
func _build_move_fx_opts() -> Dictionary:
	var opts := {}
	match fx_trail:
		TrailMode.FORCE_ON:
			opts["trail"] = true
		TrailMode.FORCE_OFF:
			opts["trail"] = false
		_:
			pass
	if fx_trail_color.a > 0.001:
		opts["color"] = fx_trail_color
	if fx_trail_width > 0.0:
		opts["trail_width"] = fx_trail_width
	if fx_move_sec > 0.0:
		opts["duration"] = fx_move_sec
	return opts
