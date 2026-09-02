## CardData.pipelines 실행기. EffectManager가 소유한 EffectContext를 DI로 받는다.
## preflight·스텝 순회·PASSIVE/STACK 로컬 재계산. MP 프로토콜/intent는 다루지 않음.
## S4: 변이 스텝은 `EffectManager.run_recorded_action` 공개 API만 사용 (private `_record_*` 금지).
class_name EffectPipelineRunner
extends RefCounted

var _effect_manager: Node
## EM.setup이 주입한 매치 EffectContext (static instance 대체).
var _context: EffectContext


## EffectManager와 매치 context를 연결한다. EM.setup이 호출.
func setup(effect_manager: Node, context: EffectContext) -> void:
	_effect_manager = effect_manager
	_context = context


## 카드가 pipelines 리소스를 쓰는지 판별한다 (레거시 bundle 경로와 분기).
func card_uses_pipelines(card: Node) -> bool:
	var data: CardData = _card_data(card)
	return data != null and not data.pipelines.is_empty()


## 지정 trigger의 pipeline이 있는지 검사한다.
func has_trigger_pipeline(card: Node, trigger: String) -> bool:
	var data: CardData = _card_data(card)
	if data == null:
		return false
	for pipeline in data.pipelines:
		if pipeline.trigger == trigger:
			return true
	return false


## preflight를 통과하면 발동 가능. OPEN+effect_set이면 불가.
func can_trigger(card: Node, trigger: String) -> bool:
	if trigger == "OPEN" and card != null and bool(card.get("effect_set")):
		return false
	var data: CardData = _card_data(card)
	if data == null:
		return false
	if not has_trigger_pipeline(card, trigger):
		return false
	var pipeline := _find_pipeline(data, trigger)
	if pipeline == null:
		return false
	var run_ctx := _make_run_ctx()
	for step in pipeline.steps:
		if not _step_passes_preflight(step, card, run_ctx):
			return false
	return true


## 확인 UI·기록 블록을 포함해 pipeline 전체를 실행한다. EM._trigger_card_effects가 호출.
## skip_confirm=true: sheet 발동 확정 후 이중 confirm 방지.
func run_card(card: Node, trigger: String, skip_confirm: bool = false) -> void:
	if trigger == "OPEN" and card != null and bool(card.get("effect_set")):
		return
	var data: CardData = _card_data(card)
	if data == null:
		return
	var pipeline := _find_pipeline(data, trigger)
	if pipeline == null:
		return
	var ctx := _context
	if ctx == null:
		return
	var run_ctx := _make_run_ctx()
	run_ctx.reset()
	ctx.reset_pipeline_state()
	run_ctx.execution_pool = ctx.execution_pool
	ctx.current_effect_trigger = trigger
	if not await _run_preflight(card, pipeline, run_ctx):
		return
	if skip_confirm:
		pass
	elif not await ctx.ask_effect_confirm(card):
		return
	# 발동 연출: confirm(또는 sheet skip) 직후 · 스텝 전 (필드 실카드 / 존 칩 peek).
	if _effect_manager and _effect_manager.has_method("broadcast_activation_fx"):
		_effect_manager.broadcast_activation_fx(card, trigger)
	await ActivationFx.await_play_for_source(card, trigger)
	if data.oncePerTurn:
		ctx.turn_effect_history[card.owner_side][data.id] = true
	await _run_steps(card, pipeline, run_ctx, trigger)
	if trigger == "OPEN":
		ctx.schedule_passive_refresh()


## check_at_preflight=false면 게이트를 건너뛴다. 왜: 기존 카드 기본값 true 유지.
func _step_passes_preflight(
	step: EffectStepBase,
	card: Node,
	run_ctx: EffectPipelineRunContext
) -> bool:
	if step == null:
		return true
	# Only explicit false skips; missing/true keep gate behavior for all existing cards.
	if step.get("check_at_preflight") == false:
		return true
	if step.has_method("evaluate_preflight"):
		return step.evaluate_preflight(card, run_ctx)
	return true


## pipeline 전 스텝 preflight를 순회한다. 하나라도 실패하면 false.
func _run_preflight(card: Node, pipeline: EffectPipeline, run_ctx: EffectPipelineRunContext) -> bool:
	for step in pipeline.steps:
		if not _step_passes_preflight(step, card, run_ctx):
			return false
	return true


## 스텝을 순서대로 실행한다. PASSIVE/STACK은 record 바깥(로컬 재계산).
func _run_steps(
	card: Node,
	pipeline: EffectPipeline,
	run_ctx: EffectPipelineRunContext,
	trigger: String
) -> void:
	var ctx := _context
	if ctx == null:
		return
	for step in pipeline.steps:
		if run_ctx.step_results.get("_abort", false):
			return
		if step == null:
			push_warning("EffectPipelineRunner: null step in pipeline — skipped")
			continue
		if step is StepMinCount or step is StepCompareCount or step is StepCheckSourceLine or step is StepCompareLineUnitCounts or step is StepCheckLineAllTokens or step is StepCheckNoAllyStacks:
			if not step.evaluate_preflight(card, run_ctx):
				return
			continue
		if step is StepMoveCards and not step.evaluate_preflight(card, run_ctx):
			return
		ctx.current_effect_all_line = _infer_all_line(step)
		# PASSIVE/STACK은 양측이 로컬로 재계산 — EFFECT_RESULT에 STAT 등을 실어 이중 적용하지 않음
		if trigger in ["PASSIVE", "STACK"]:
			ctx.current_effect_trigger = trigger
			await step.run(card, run_ctx)
		else:
			await _effect_manager.run_recorded_action(func() -> void:
				ctx.current_effect_trigger = trigger
				await step.run(card, run_ctx)
			)
		if run_ctx.step_results.get("_abort", false):
			return
		var milled: Array = ctx.take_milled_cards()
		for milled_card in milled:
			if milled_card not in run_ctx.execution_pool:
				run_ctx.execution_pool.append(milled_card)


## 선택 스텝의 line_scope로 current_effect_all_line을 추론한다.
func _infer_all_line(step: EffectStepBase) -> bool:
	if step is StepSelectTargets:
		return step.line_scope != EffectTypes.LineScope.SAME_AS_SOURCE
	if step is StepSelectSlot or step is StepSelectSlots:
		return step.line_scope != EffectTypes.LineScope.SAME_AS_SOURCE
	return true


## 필드 PASSIVE 파이프라인을 실행한다. EM 패시브 갱신이 호출.
func run_passive_for_card(card: Node) -> void:
	var data: CardData = _card_data(card)
	if data == null:
		return
	var pipeline := _find_pipeline(data, "PASSIVE")
	if pipeline == null:
		return
	var ctx := _context
	if ctx == null:
		return
	var run_ctx := _make_run_ctx()
	run_ctx.reset()
	ctx.reset_pipeline_state()
	run_ctx.execution_pool = ctx.execution_pool
	ctx.current_effect_trigger = "PASSIVE"
	await _run_steps(card, pipeline, run_ctx, "PASSIVE")


## 스택 카드 STACK 파이프라인을 호스트 기준으로 실행한다.
func run_stack_for_host(host: Node, stacked: Node) -> void:
	if host == null or stacked == null or not is_instance_valid(host) or not is_instance_valid(stacked):
		return
	var data: CardData = _card_data(stacked)
	if data == null:
		return
	var pipeline := _find_pipeline(data, "STACK")
	if pipeline == null:
		return
	var ctx := _context
	if ctx == null:
		return
	var run_ctx := _make_run_ctx()
	run_ctx.reset()
	ctx.reset_pipeline_state()
	run_ctx.execution_pool = ctx.execution_pool
	ctx.current_effect_trigger = "STACK"
	await _run_steps(host, pipeline, run_ctx, "STACK")


## CardData에서 trigger에 맞는 첫 pipeline을 찾는다.
func _find_pipeline(data: CardData, trigger: String) -> EffectPipeline:
	for pipeline in data.pipelines:
		if pipeline.trigger == trigger:
			return pipeline
	return null


## 카드의 CardData를 안전하게 꺼낸다.
func _card_data(card: Node) -> CardData:
	if card == null or not card.card_data:
		return null
	return card.card_data


## EM·주입된 context로 1회용 EffectPipelineRunContext를 만든다.
func _make_run_ctx() -> EffectPipelineRunContext:
	return EffectPipelineRunContext.new(_effect_manager, _context)
