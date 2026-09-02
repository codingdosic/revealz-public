## 존·라인 카드 조회 정적 헬퍼. EffectContext는 호출부에서 ctx 인자로 주입한다(싱글톤 미사용).
class_name EffectZoneQuery
extends RefCounted


## 상대 진영(RelativeSide)을 GameConstants.Side로 변환. 파이프라인 스텝·존 쿼리에서 공통 사용.
## OWNER/OPPONENT의 “자신”은 컨트롤러 기준: 필드(또는 스택 호스트 필드)에 있으면 slot.side,
## 아니면 owner_side. 패·묘지 귀속(owner_side)과 분리 — 컨트롤 교환 후에도 존 카운트가 맞음.
static func resolve_side(source: Node, relative: EffectTypes.RelativeSide) -> GameConstants.Side:
	if source == null:
		return GameConstants.Side.PLAYER
	var self_side := controller_side(source)
	if relative == EffectTypes.RelativeSide.OWNER:
		return self_side
	return GameConstants.opposite_side(self_side)


## 필드 컨트롤러 진영. 슬롯/스택 호스트가 없으면 owner_side(소유).
static func controller_side(source: Node) -> GameConstants.Side:
	if source == null:
		return GameConstants.Side.PLAYER
	var slot = source.get("card_slot_card_is_in")
	if slot != null and is_instance_valid(slot):
		return slot.side
	var host = source.get("stack_host")
	if host != null and is_instance_valid(host):
		var host_slot = host.get("card_slot_card_is_in")
		if host_slot != null and is_instance_valid(host_slot):
			return host_slot.side
	return source.owner_side


## OPPONENT+FIELD 대상 선택·카운트 시 스킬 면역 호스트 제외 여부. StepSelectTargets·StepCompareCount 등.
static func should_filter_skill_immune_targets(
	relative_side: EffectTypes.RelativeSide,
	zone: EffectTypes.EffectZone
) -> bool:
	return zone == EffectTypes.EffectZone.FIELD and relative_side == EffectTypes.RelativeSide.OPPONENT


## 존 내 카드 수 반환. StepStoreCount·StepMinCount·StepCompareCount 등.
static func count_in_zone(
	ctx: EffectContext,
	source: Node,
	relative: EffectTypes.RelativeSide,
	zone: EffectTypes.EffectZone,
	line_scope: EffectTypes.LineScope = EffectTypes.LineScope.ANY,
	units_only: bool = false,
	exclude_source: bool = false,
	include_name_exact: String = "",
	require_token: bool = false,
	include_types: PackedStringArray = PackedStringArray(),
	filter_skill_immune: bool = false
) -> int:
	# 권속 등 무필터 BANISH 카운트는 deck.banishzone SSOT (nodes는 presenter 동기 전 공백일 수 있음)
	if (
		zone == EffectTypes.EffectZone.BANISH
		and line_scope == EffectTypes.LineScope.ANY
		and not units_only
		and not exclude_source
		and include_name_exact.is_empty()
		and not require_token
		and include_types.is_empty()
		and not filter_skill_immune
	):
		if ctx and source:
			var side := resolve_side(source, relative)
			var deck := ctx.get_deck(side)
			if deck:
				return deck.banishzone.size()
	return get_cards_in_zone(
		ctx,
		source,
		relative,
		zone,
		line_scope,
		units_only,
		exclude_source,
		"",
		false,
		false,
		[],
		include_name_exact,
		require_token,
		include_types,
		filter_skill_immune
	).size()


## 존·라인·필터 조건에 맞는 카드 배열 반환. StepSelectTargets·StepModifyAllInZone 등.
static func get_cards_in_zone(
	ctx: EffectContext,
	source: Node,
	relative: EffectTypes.RelativeSide,
	zone: EffectTypes.EffectZone,
	line_scope: EffectTypes.LineScope = EffectTypes.LineScope.ANY,
	units_only: bool = false,
	exclude_source: bool = false,
	exclude_name_substring: String = "",
	exclude_execution_pool: bool = false,
	use_execution_pool_only: bool = false,
	execution_pool: Array = [],
	include_name_exact: String = "",
	require_token: bool = false,
	include_types: PackedStringArray = PackedStringArray(),
	filter_skill_immune: bool = false
) -> Array:
	if ctx == null or source == null:
		return []
	var side := resolve_side(source, relative)
	var cards: Array = []
	match zone:
		EffectTypes.EffectZone.HAND:
			for c in ctx.get_hand(side).get_hand_cards():
				cards.append(c)
		EffectTypes.EffectZone.GRAVE:
			for c in ctx.graveyard_nodes.get(side, []):
				if is_instance_valid(c):
					cards.append(c)
		EffectTypes.EffectZone.BANISH:
			for c in ctx.banishzone_nodes.get(side, []):
				if is_instance_valid(c):
					cards.append(c)
		EffectTypes.EffectZone.DECK:
			return []
		EffectTypes.EffectZone.FIELD:
			var source_line := ctx.line_of_card(source)
			for slot in ctx.field_manager._slots_by_side.get(side, []):
				if not slot.card_in_slot:
					continue
				if not _line_matches_scope(slot.line, source_line, line_scope):
					continue
				cards.append(slot.card_in_slot)
		EffectTypes.EffectZone.STACK:
			var source_line := ctx.line_of_card(source)
			for slot in ctx.field_manager._slots_by_side.get(side, []):
				if not slot.card_in_slot:
					continue
				if not _line_matches_scope(slot.line, source_line, line_scope):
					continue
				var host = slot.card_in_slot
				if host.get("stack_cards"):
					for stacked in host.stack_cards:
						if is_instance_valid(stacked):
							cards.append(stacked)
	return _apply_card_filters(
		cards,
		source,
		units_only,
		exclude_source,
		exclude_name_substring,
		exclude_execution_pool,
		use_execution_pool_only,
		execution_pool,
		include_name_exact,
		require_token,
		include_types,
		filter_skill_immune,
		zone
	)


## 빈 필드 슬롯 목록 반환. StepSelectSlot·StepSelectSlots.
static func get_empty_slots(
	ctx: EffectContext,
	source: Node,
	relative: EffectTypes.RelativeSide,
	line_scope: EffectTypes.LineScope
) -> Array:
	if ctx == null or source == null:
		return []
	var side := resolve_side(source, relative)
	var source_line := ctx.line_of_card(source)
	var slots: Array = []
	for slot in ctx.field_manager._slots_by_side.get(side, []):
		if not slot.is_empty():
			continue
		if not _line_matches_scope(slot.line, source_line, line_scope):
			continue
		if line_scope == EffectTypes.LineScope.EMPTY_ALLY_LINE:
			if _line_has_ally_units(ctx, side, slot.line):
				continue
		slots.append(slot)
	return slots


## 지정 라인의 유닛(또는 카드) 수. compare_line_unit_counts 내부·라인 비교 스텝.
static func count_units_on_line(
	ctx: EffectContext,
	side: GameConstants.Side,
	line: int,
	units_only: bool = true
) -> int:
	if ctx == null:
		return 0
	var count := 0
	for slot in ctx.field_manager._slots_by_side.get(side, []):
		if slot.line != line or not slot.card_in_slot:
			continue
		if units_only and not CardDisplayHelpers.is_unit_card(slot.card_in_slot):
			continue
		count += 1
	return count


## 최소 유닛 수를 충족하는 라인 개수. StepStoreLinesMeetingCount.
static func count_lines_meeting_min_units(
	ctx: EffectContext,
	source: Node,
	relative: EffectTypes.RelativeSide,
	min_units: int,
	units_only: bool = true
) -> int:
	if ctx == null or source == null:
		return 0
	var side := resolve_side(source, relative)
	var matching_lines: Dictionary = {}
	for slot in ctx.field_manager._slots_by_side.get(side, []):
		if not slot.card_in_slot:
			continue
		if units_only and not CardDisplayHelpers.is_unit_card(slot.card_in_slot):
			continue
		matching_lines[slot.line] = matching_lines.get(slot.line, 0) + 1
	var result := 0
	for line in matching_lines:
		if int(matching_lines[line]) >= min_units:
			result += 1
	return result


## 소스와 동일 라인 아군(소스 제외 가능)이 모두 지정 토큰인지. StepCheckLineAllTokens.
static func line_other_allies_are_tokens(
	ctx: EffectContext,
	source: Node,
	token_name: String,
	exclude_source: bool = true
) -> bool:
	if ctx == null or source == null:
		return false
	var side: GameConstants.Side = source.owner_side
	var source_line := ctx.line_of_card(source)
	for slot in ctx.field_manager._slots_by_side.get(side, []):
		if slot.line != source_line or not slot.card_in_slot:
			continue
		var card = slot.card_in_slot
		if exclude_source and card == source:
			continue
		if not CardDisplayHelpers.is_token_card(card):
			return false
		if not token_name.is_empty() and String(card.card_name) != token_name:
			return false
	return true


## 동일 라인 아군·상대 유닛 수 비교. StepCompareLineUnitCounts.
static func compare_line_unit_counts(
	ctx: EffectContext,
	source: Node,
	compare_op: EffectTypes.CompareOp = EffectTypes.CompareOp.GT
) -> bool:
	if ctx == null or source == null:
		return false
	var line := ctx.line_of_card(source)
	if line < 0:
		return false
	var ally_count := count_units_on_line(ctx, source.owner_side, line, true)
	var opp_count := count_units_on_line(ctx, GameConstants.opposite_side(source.owner_side), line, true)
	return compare_int(ally_count, compare_op, opp_count)


## 상대 필드 라인 유닛 중 최대 배치 LP. StepStoreMaxOpponentLinePower.
static func max_opponent_field_line_power(
	ctx: EffectContext,
	source: Node,
	line_scope: EffectTypes.LineScope = EffectTypes.LineScope.SAME_AS_SOURCE,
	units_only: bool = true
) -> int:
	var opponents := get_cards_in_zone(
		ctx,
		source,
		EffectTypes.RelativeSide.OPPONENT,
		EffectTypes.EffectZone.FIELD,
		line_scope,
		units_only
	)
	var max_lp := 0
	for card in opponents:
		if not is_instance_valid(card):
			continue
		if card.has_method("get_current_field_line_power"):
			max_lp = maxi(max_lp, int(card.get_current_field_line_power()))
	return max_lp


## 라인 스코프(LineScope)에 라인이 맞는지. get_cards_in_zone·get_empty_slots 내부.
static func _line_matches_scope(line: int, source_line: int, line_scope: EffectTypes.LineScope) -> bool:
	match line_scope:
		EffectTypes.LineScope.SAME_AS_SOURCE:
			return source_line < 0 or line == source_line
		EffectTypes.LineScope.OTHER_THAN_SOURCE:
			return source_line < 0 or line != source_line
		_:
			return true


## 해당 라인에 아군 유닛이 있는지. EMPTY_ALLY_LINE 슬롯 필터 내부.
static func _line_has_ally_units(ctx: EffectContext, side: GameConstants.Side, line: int) -> bool:
	for slot in ctx.field_manager._slots_by_side.get(side, []):
		if slot.line == line and slot.card_in_slot:
			return true
	return false


## 카드 배열에 필터(유닛·토큰·면역·실행 풀 등) 적용. get_cards_in_zone 내부.
static func _apply_card_filters(
	cards: Array,
	source: Node,
	units_only: bool,
	exclude_source: bool,
	exclude_name_substring: String,
	exclude_execution_pool: bool,
	use_execution_pool_only: bool,
	execution_pool: Array,
	include_name_exact: String = "",
	require_token: bool = false,
	include_types: PackedStringArray = PackedStringArray(),
	filter_skill_immune: bool = false,
	zone: EffectTypes.EffectZone = EffectTypes.EffectZone.FIELD
) -> Array:
	var filtered: Array = []
	var skip_effect_set := (
		zone == EffectTypes.EffectZone.FIELD
		or zone == EffectTypes.EffectZone.STACK
	)
	for card in cards:
		if not is_instance_valid(card):
			continue
		if units_only and not CardDisplayHelpers.is_unit_card(card):
			continue
		if exclude_source and card == source:
			continue
		# effect_set는 필드 상태 — 묘지·밴시 카운트(권속)에서 제외하면 안 됨
		if skip_effect_set and bool(card.get("effect_set")):
			continue
		if filter_skill_immune and is_skill_immune_to_source(source, card):
			continue
		if not exclude_name_substring.is_empty():
			var name := String(card.card_name)
			if name.contains(exclude_name_substring):
				continue
		if not include_name_exact.is_empty() and String(card.card_name) != include_name_exact:
			continue
		if require_token and not CardDisplayHelpers.is_token_card(card):
			continue
		if not include_types.is_empty() and not CardDisplayHelpers.card_matches_any_type(card, include_types):
			continue
		if exclude_execution_pool and _card_in_array(card, execution_pool):
			continue
		if use_execution_pool_only and not _card_in_array(card, execution_pool):
			continue
		filtered.append(card)
	return filtered


## effect_set(뒷면·타겟 불가) 카드인지. EffectContext 대상 검증·필터.
static func is_effect_target_blocked(source: Node, candidate: Node) -> bool:
	if candidate == null:
		return false
	return bool(candidate.get("effect_set"))


## 상대 스택 스킬 면역(skill_immune_from_stack) 여부. EffectContext·필터.
static func is_skill_immune_to_source(source: Node, candidate: Node) -> bool:
	if source == null or candidate == null:
		return false
	if source.owner_side == candidate.owner_side:
		return false
	return bool(candidate.get("skill_immune_from_stack"))


## instance_id 기준 배열 포함 여부. 실행 풀 필터 내부.
static func _card_in_array(card: Node, arr: Array) -> bool:
	for candidate in arr:
		if candidate == card:
			return true
		if (
			is_instance_valid(candidate)
			and is_instance_valid(card)
			and candidate.get("instance_id") != null
			and card.get("instance_id") != null
			and candidate.instance_id == card.instance_id
		):
			return true
	return false


## 후보에서 무작위 N장 선택. StepSelectTargets(RANDOM/AUTO).
static func pick_random(candidates: Array, count: int) -> Array:
	if candidates.is_empty() or count <= 0:
		return []
	var pool := candidates.duplicate()
	var result: Array = []
	var picks: int = mini(count, pool.size())
	for _i in range(picks):
		var idx := randi() % pool.size()
		result.append(pool[idx])
		pool.remove_at(idx)
	return result


## 정수 비교 연산. StepCompareCount·compare_line_unit_counts.
static func compare_int(value: int, op: EffectTypes.CompareOp, threshold: int) -> bool:
	match op:
		EffectTypes.CompareOp.LT:
			return value < threshold
		EffectTypes.CompareOp.LE:
			return value <= threshold
		EffectTypes.CompareOp.EQ:
			return value == threshold
		EffectTypes.CompareOp.GE:
			return value >= threshold
		EffectTypes.CompareOp.GT:
			return value > threshold
	return false
