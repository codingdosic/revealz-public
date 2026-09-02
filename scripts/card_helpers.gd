class_name CardHelpers
extends RefCounted

const PREVIEW_ALPHA := 0.5
const META_FLIP_SWAP := &"_flip_swap_tween"


static func setup_card_data(card: Node2D, card_name: String, owner_side: GameConstants.Side) -> void:
	card.set("card_name", card_name)
	card.set("owner_side", owner_side)
	card.set("reveal_state", GameConstants.RevealState.HAND)
	card.set("is_locked", false)


static func apply_hand_visual(card: Node2D) -> void:
	_abort_flip_visuals(card)
	_set_card_root_alpha(card, 1.0)
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 1)
		img.visible = true
		img.z_index = 0
	if card.has_node("CardBackImage"):
		card.get_node("CardBackImage").visible = false
		card.get_node("CardBackImage").z_index = -1
	_set_label_alpha(card, 1.0)
	card.set("reveal_state", GameConstants.RevealState.HAND)
	_refresh_on_field_power(card)


static func apply_hand_hidden(card: Node2D) -> void:
	_abort_flip_visuals(card)
	_set_card_root_alpha(card, 1.0)
	var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer")
	if anim:
		anim.stop()
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 1)
		img.visible = true
		img.z_index = -1
	if card.has_node("CardBackImage"):
		card.get_node("CardBackImage").visible = true
		card.get_node("CardBackImage").z_index = 0
	_apply_opponent_back_v_flip(card)
	_set_label_alpha(card, 0.0)
	card.set("reveal_state", GameConstants.RevealState.HAND)
	_refresh_on_field_power(card)


static func apply_setting_preview(card: Node2D) -> void:
	_abort_flip_visuals(card)
	var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer")
	if anim and anim.has_animation("RESET"):
		anim.play("RESET")
	# Root alpha fades foil + RarityFrame + OnFieldPower together.
	_set_card_root_alpha(card, PREVIEW_ALPHA)
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 1)
		img.visible = true
		img.z_index = 0
	if card.has_node("CardBackImage"):
		card.get_node("CardBackImage").visible = false
	_set_label_alpha(card, 0.0)
	card.set("reveal_state", GameConstants.RevealState.SETTING_PREVIEW)
	_refresh_on_field_power(card)


static func apply_setting_hidden(card: Node2D, play_flip: bool = true) -> void:
	if _try_start_setting_hidden_flip(card, play_flip):
		return
	_apply_setting_hidden_instant(card)


## SETTING_PREVIEW → 뒷면. 플립 재생 시 animation_finished 까지 await.
static func await_setting_hidden(card: Node2D, play_flip: bool = true) -> void:
	if not _try_start_setting_hidden_flip(card, play_flip):
		_apply_setting_hidden_instant(card)
		return
	var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null:
		_apply_setting_hidden_instant(card)
		return
	await anim.animation_finished
	_apply_setting_hidden_instant(card)


## 여러 카드 확정 시 card_flip_back 병렬 대기.
static func await_setting_hidden_all(cards: Array, play_flip: bool = true) -> void:
	var waiting: Array[AnimationPlayer] = []
	for card in cards:
		if card == null or not is_instance_valid(card):
			continue
		if _try_start_setting_hidden_flip(card, play_flip):
			var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if anim != null:
				waiting.append(anim)
		else:
			_apply_setting_hidden_instant(card)
	if waiting.is_empty():
		return
	var box := {"n": waiting.size()}
	for anim in waiting:
		anim.animation_finished.connect(_on_setting_hidden_flip_finished.bind(box), CONNECT_ONE_SHOT)
	var tree := _scene_tree_from_cards(cards)
	if tree == null:
		for card in cards:
			if card != null and is_instance_valid(card):
				_apply_setting_hidden_instant(card)
		return
	var frames := 0
	while int(box["n"]) > 0 and frames < 900:
		frames += 1
		await tree.process_frame
	for card in cards:
		if card != null and is_instance_valid(card):
			_apply_setting_hidden_instant(card)


static func _on_setting_hidden_flip_finished(box: Dictionary) -> void:
	box["n"] = int(box["n"]) - 1


static func _scene_tree_from_cards(cards: Array) -> SceneTree:
	for card in cards:
		if card != null and is_instance_valid(card) and card.is_inside_tree():
			return card.get_tree()
	return Engine.get_main_loop() as SceneTree


static func _try_start_setting_hidden_flip(card: Node2D, play_flip: bool) -> bool:
	if not play_flip:
		return false
	if card.get("reveal_state") != GameConstants.RevealState.SETTING_PREVIEW:
		return false
	var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null or not anim.has_animation("card_flip_back"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	_abort_flip_visuals(card)
	_prepare_for_flip_back(card)
	card.set("reveal_state", GameConstants.RevealState.SETTING_HIDDEN)
	anim.play("card_flip_back")
	_schedule_flip_back_face_swap(card)
	return true


static func _apply_setting_hidden_instant(card: Node2D) -> void:
	_abort_flip_visuals(card)
	_set_card_root_alpha(card, 1.0)
	var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.stop()
	if anim and anim.has_animation("RESET"):
		anim.play("RESET")
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 0)
		img.visible = true
		img.z_index = -1
	if card.has_node("CardBackImage"):
		card.get_node("CardBackImage").visible = true
		card.get_node("CardBackImage").z_index = 0
	_apply_opponent_back_v_flip(card)
	_set_label_alpha(card, 0.0)
	card.set("reveal_state", GameConstants.RevealState.SETTING_HIDDEN)
	_refresh_on_field_power(card)


## 확정 플립 시작: 앞면(프리뷰) → 옆면. card_flip_back 0초 상태.
static func _prepare_for_flip_back(card: Node2D) -> void:
	_set_card_root_alpha(card, 1.0)
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 1)
		img.visible = true
		img.z_index = 0
	if card.has_node("CardBackImage"):
		var back: CanvasItem = card.get_node("CardBackImage")
		back.visible = false
		back.z_index = -1
	_set_label_alpha(card, 0.0)
	var panel := card.get_node_or_null("OnFieldPower") as CanvasItem
	if panel:
		panel.visible = false


## card_flip_back 옆면 시점: 뒷면 고정(card_flip face_swap 대칭).
static func _schedule_flip_back_face_swap(card: Node2D) -> void:
	var swap := card.create_tween()
	card.set_meta(META_FLIP_SWAP, swap)
	swap.tween_interval(GameConstants.CARD_FLIP_SWAP_SEC)
	swap.tween_callback(func() -> void:
		if not is_instance_valid(card):
			return
		if card.has_meta(META_FLIP_SWAP):
			card.remove_meta(META_FLIP_SWAP)
		if card.has_node("CardImage"):
			var img: CanvasItem = card.get_node("CardImage")
			img.modulate = Color(1, 1, 1, 0)
			img.visible = true
			img.z_index = -1
		if card.has_node("CardBackImage"):
			var back: CanvasItem = card.get_node("CardBackImage")
			back.visible = true
			back.z_index = 0
		_apply_opponent_back_v_flip(card)
	)


static func apply_effect_set(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.set("effect_set", true)
	_abort_flip_visuals(card)
	_set_card_root_alpha(card, 1.0)
	var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer")
	if anim:
		anim.stop()
	if anim and anim.has_animation("RESET"):
		anim.play("RESET")
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 0)
		img.visible = true
		img.z_index = -1
	if card.has_node("CardBackImage"):
		card.get_node("CardBackImage").visible = true
		card.get_node("CardBackImage").z_index = 0
	_apply_opponent_back_v_flip(card)
	_set_label_alpha(card, 0.0)
	_refresh_on_field_power(card)


static func clear_effect_set(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.set("effect_set", false)


static func contributes_field_power(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	return not bool(card.get("effect_set"))


static func reveal_card(card: Node2D, play_flip: bool = true) -> void:
	if bool(card.get("effect_set")):
		return
	_abort_flip_visuals(card)
	_set_card_root_alpha(card, 1.0)
	if card.has_node("CardImage"):
		card.get_node("CardImage").modulate = Color(1, 1, 1, 1)
	var anim: AnimationPlayer = card.get_node_or_null("AnimationPlayer")
	if anim:
		anim.stop()
	var do_flip := (
		play_flip
		and anim != null
		and anim.has_animation("card_flip")
		and DisplayServer.get_name() != "headless"
	)
	# 공개 상태는 즉시. 플립 연출만 뒷면→옆면 교체→앞면.
	card.set("reveal_state", GameConstants.RevealState.REVEALED)
	if do_flip:
		_prepare_for_flip(card)
		anim.play("card_flip")
		_schedule_flip_face_swap(card)
	else:
		_apply_revealed_front(card)
		_refresh_on_field_power(card)
		if play_flip:
			RareRevealFx.play(card)


## card_flip 없이 앞면·공개 상태만 즉시 적용. 토큰 팝인 등 연출용.
static func reveal_card_instant(card: Node2D) -> void:
	reveal_card(card, false)


## 플립 시작: 뒷면이 앞에, 앞면은 숨김. 파워/레어도는 교체 시점까지 숨김.
static func _prepare_for_flip(card: Node2D) -> void:
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 1)
		img.visible = false
		img.z_index = -1
	if card.has_node("CardBackImage"):
		var back: CanvasItem = card.get_node("CardBackImage")
		back.visible = true
		back.z_index = 0
	_apply_opponent_back_v_flip(card)
	var panel := card.get_node_or_null("OnFieldPower") as CanvasItem
	if panel:
		panel.visible = false


## 옆면 정점에서 앞면 고정 + 레어도 테두리. 숨긴 채로 두면 테두리가 영구 비표시.
static func _schedule_flip_face_swap(card: Node2D) -> void:
	var swap := card.create_tween()
	card.set_meta(META_FLIP_SWAP, swap)
	swap.tween_interval(GameConstants.CARD_FLIP_SWAP_SEC)
	swap.tween_callback(func() -> void:
		if not is_instance_valid(card):
			return
		if card.has_meta(META_FLIP_SWAP):
			card.remove_meta(META_FLIP_SWAP)
		_apply_revealed_front(card)
		_refresh_on_field_power(card)
		RareRevealFx.play(card)
	)


## 진행 중 면 교체 트윈을 끊는다.
static func _abort_flip_visuals(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	if card.has_meta(META_FLIP_SWAP):
		var swap: Variant = card.get_meta(META_FLIP_SWAP)
		if swap is Tween and (swap as Tween).is_valid():
			(swap as Tween).kill()
		card.remove_meta(META_FLIP_SWAP)


## CardImage 앞면·CardBack 숨김. AnimationPlayer는 호출 전 stop 가정.
static func _apply_revealed_front(card: Node2D) -> void:
	_set_card_root_alpha(card, 1.0)
	if card.has_node("CardImage"):
		var img: CanvasItem = card.get_node("CardImage")
		img.modulate = Color(1, 1, 1, 1)
		img.visible = true
		img.z_index = 0
	if card.has_node("CardBackImage"):
		var back: CanvasItem = card.get_node("CardBackImage")
		back.visible = false
		back.z_index = -1


## Setting-preview ghost: root modulate fades foil, frame, and power together.
static func _set_card_root_alpha(card: Node2D, alpha: float) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.modulate = Color(1, 1, 1, alpha)


static func disable_interaction(card: Node2D) -> void:
	card.set("is_interactive", false)
	var area: Area2D = card.get_node_or_null("Area2D")
	if area:
		# 드래그는 막되, 필드 카드 정보 사이드바용 레이캐스트는 유지
		area.input_pickable = true
		area.collision_layer = GameConstants.COLLISION_LAYER_CARD
		area.collision_mask = 0
		area.monitorable = true
		area.monitoring = false


static func enable_interaction(card: Node2D) -> void:
	card.set("is_interactive", true)
	var area: Area2D = card.get_node_or_null("Area2D")
	if area:
		area.input_pickable = true
		area.collision_layer = GameConstants.COLLISION_LAYER_CARD
		area.collision_mask = GameConstants.COLLISION_LAYER_CARD
		area.monitorable = true
		area.monitoring = true


## MatchVfx 출발 회전. prepare_for_hand가 rotation을 0으로 돌린 뒤 패 트윈 직전에 복구한다.
static func restore_vfx_from_rotation(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	if not card.has_meta("vfx_from_rotation"):
		return
	card.rotation = float(card.get_meta("vfx_from_rotation"))
	card.remove_meta("vfx_from_rotation")


## 손패 진입 공통 상태(회전 0·스케일·존). 라이프 출발 회전은 restore_vfx_from_rotation이 되돌린다.
static func prepare_for_hand(card: Node2D, side: GameConstants.Side) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.visible = true
	card.rotation = 0.0
	card.scale = Vector2(0.4, 0.4)
	card.z_index = 1
	card.set("is_locked", false)
	card.set("is_selectable", false)
	if card.has_method("toggle_selection_rect"):
		card.toggle_selection_rect(false)
	enable_interaction(card)
	if side == GameConstants.Side.OPPONENT:
		apply_hand_hidden(card)
	else:
		apply_hand_visual(card)
	if card.get("zone") != null:
		card.set("zone", EffectTypes.Location.HAND)
	_refresh_on_field_power(card)


static func _set_label_alpha(card: Node2D, alpha: float) -> void:
	for label_name in ["LeftAtkLabel", "CenterAtkLabel", "RightTextLabel"]:
		if card.has_node(label_name):
			var label: CanvasItem = card.get_node(label_name)
			label.modulate = Color(1, 1, 1, alpha)


## 상대 뒷면은 카드 로컬 상하 반전 (보드 180° 대칭 시 안착 맞춤).
static func _apply_opponent_back_v_flip(card: Node) -> void:
	var back := card.get_node_or_null("CardBackImage") as Sprite2D
	if back == null:
		return
	back.flip_v = card.get("owner_side") == GameConstants.Side.OPPONENT


static func _refresh_on_field_power(card: Node2D) -> void:
	if card.has_method("update_on_field_power"):
		card.update_on_field_power()
	if card.has_method("refresh_stack_display"):
		card.refresh_stack_display()
	if card.has_method("refresh_rarity_visual"):
		card.refresh_rarity_visual()
