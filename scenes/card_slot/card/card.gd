extends Node2D

signal hovered
signal hovered_off
signal card_clicked(card)

var card_name: String = ""
var card_color: int
var card_data: CardData
var network_uuid: int = 0
var instance_id: String = ""
## 이 카피의 표시 등급 (덱/팩에서 부여. CardData.rarity와 무관).
var instance_rarity: int = CardRarity.Tier.N
var owner_side: GameConstants.Side = GameConstants.Side.PLAYER
var reveal_state: GameConstants.RevealState = GameConstants.RevealState.HAND
var zone: EffectTypes.Location = EffectTypes.Location.HAND
var is_locked: bool = false
var is_interactive: bool = true
var is_selectable: bool = false
var skill_immune_from_stack: bool = false
var effect_set: bool = false

var stat_l: int = 0
var stat_c: int = 0
var stat_r: int = 0
var stat_spd: int = 0

var starting_position
var card_slot_card_is_in

var stack_cards: Array = []
var stack_host: Node = null

var _selection_overlay: Panel
var _stack_badge: Panel
var _rarity_frame: Panel
var _rarity_tier: int = CardRarity.Tier.N
var _passive_line_bonus: int = 0
var _passive_line_absolute: int = -1
var _stat_before_passive_absolute: int = 0
## PASSIVE가 적용된 물리 축 (0=L, 1=C, 2=R). 라인 이동 후에도 clear가 올바른 축을 되돌린다.
var _passive_stat_axis: int = -1
## PASSIVE clear 중 일시 음수에서 destroy하지 않음 (refresh 종료 후 일괄 판정)
var _suppress_stat_destroy: bool = false


func _ready() -> void:
	_apply_card_sprite_scales()
	_sync_sprite_scale_animations()
	if get_parent() and get_parent().has_method("connect_card_signals"):
		get_parent().connect_card_signals(self)
	_ensure_selection_overlay()
	set_process(false)


## CardHoverTilt가 set_process(true)로 켠 동안만 기울임 보간.
func _process(delta: float) -> void:
	CardHoverTilt.process(self, delta)

## CardImage / CardBackImage 에 GameConstants.CARD_SPRITE_SCALE 적용.
func _apply_card_sprite_scales() -> void:
	var s := GameConstants.card_sprite_scale_vec()
	if has_node("CardImage"):
		(get_node("CardImage") as Node2D).scale = s
	if has_node("CardBackImage"):
		(get_node("CardBackImage") as Node2D).scale = s


## 플립/RESET 애니 scale 키를 상수에 맞춤 (인스턴스별 복제 후 패치).
func _sync_sprite_scale_animations() -> void:
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	var lib_name := StringName("")
	if not ap.has_animation_library(lib_name):
		return
	var lib: AnimationLibrary = ap.get_animation_library(lib_name)
	if lib == null:
		return
	var full := GameConstants.card_sprite_scale_vec()
	var edge := GameConstants.card_sprite_flip_edge_vec()
	var new_lib := AnimationLibrary.new()
	for anim_key in lib.get_animation_list():
		var src: Animation = lib.get_animation(anim_key)
		if src == null:
			continue
		var anim: Animation = src.duplicate(true) as Animation
		_patch_sprite_scale_tracks(anim, full, edge)
		new_lib.add_animation(anim_key, anim)
	ap.remove_animation_library(lib_name)
	ap.add_animation_library(lib_name, new_lib)


## CardImage/CardBackImage:scale 트랙 키를 full / (중간이면) edge 로 채운다.
func _patch_sprite_scale_tracks(anim: Animation, full: Vector2, edge: Vector2) -> void:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_VALUE:
			continue
		var path := String(anim.track_get_path(i))
		if not (path.ends_with("CardImage:scale") or path.ends_with("CardBackImage:scale")):
			continue
		var key_count := anim.track_get_key_count(i)
		for k in key_count:
			# 플립 3키: 풀 → 옆면 → 풀. RESET 1키: 풀.
			if key_count >= 3 and k == 1:
				anim.track_set_key_value(i, k, edge)
			else:
				anim.track_set_key_value(i, k, full)


## 카탈로그 CardData + 카피 등급(instance_rarity). rarity 생략 시 N.
func init_from_data(
	data: CardData,
	side: GameConstants.Side,
	inst_id: String = "",
	uuid: int = 0,
	p_rarity: int = CardRarity.Tier.N
) -> void:
	card_data = data
	card_name = data.card_name
	card_color = data.color
	owner_side = side
	network_uuid = uuid
	instance_id = inst_id if inst_id != "" else (
		str(uuid) if uuid > 0 else _new_instance_id_fallback()
	)
	instance_rarity = clampi(p_rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	stat_l = data.stat_l
	stat_c = data.stat_c
	stat_r = data.stat_r
	stat_spd = data.stat_spd
	update_labels()
	if data.illustration and has_node("CardImage"):
		get_node("CardImage").texture = data.illustration
	_apply_rarity_visual(instance_rarity)


func update_labels() -> void:
	if has_node("LeftAtkLabel"):
		get_node("LeftAtkLabel").text = str(stat_l)
	if has_node("CenterAtkLabel"):
		get_node("CenterAtkLabel").text = str(stat_c)
	if has_node("RightTextLabel"):
		get_node("RightTextLabel").text = str(stat_r)
	update_on_field_power()


func update_on_field_power() -> void:
	# 판넬 가져오기
	var panel: CanvasItem = get_node_or_null("OnFieldPower")
	if panel == null:
		return
	
	# 필드 여부에 따라 파워 라벨 표시
	var on_field := (
		not effect_set
		and (
			reveal_state == GameConstants.RevealState.SETTING_PREVIEW
			or reveal_state == GameConstants.RevealState.REVEALED
		)
	) and zone == EffectTypes.Location.FIELD and card_slot_card_is_in != null
	panel.visible = on_field
	
	if not on_field:
		refresh_stack_display()
		return
	
	var slot: CardSlot = card_slot_card_is_in
	var line: GameConstants.Line = slot.line
	var field_side: GameConstants.Side = slot.side
	var label: Label = panel.get_node_or_null("Label")
	if label:
		var current := get_power_for_line(line, field_side)
		label.text = str(current)
		# 인쇄 기본도 get_power_for_line과 같은 L/R 미러(상대 슬롯)로 비교한다.
		var base := _get_printed_power_for_line(line, field_side)
		if current > base:
			label.add_theme_color_override("font_color", GameConstants.POWER_UP_COLOR)
		elif current < base:
			label.add_theme_color_override("font_color", GameConstants.POWER_DOWN_COLOR)
		else:
			label.add_theme_color_override("font_color", GameConstants.NORM_COLOR)
	refresh_stack_display()


## 필드 라인·사이드에 대응하는 인쇄 기본 스탯 (get_power_for_line과 동일 L/R 규칙).
func _get_printed_power_for_line(line: GameConstants.Line, side: GameConstants.Side) -> int:
	if card_data == null:
		return 0
	match line:
		GameConstants.Line.LEFT:
			if side == GameConstants.Side.OPPONENT:
				return card_data.stat_r
			return card_data.stat_l
		GameConstants.Line.CENTER:
			return card_data.stat_c
		GameConstants.Line.RIGHT:
			if side == GameConstants.Side.OPPONENT:
				return card_data.stat_l
			return card_data.stat_r
	return 0


# 배치한 라인에 따라 맞는 스탯 반환
func get_power_for_line(line: GameConstants.Line, side: GameConstants.Side) -> int:
	match line:
		GameConstants.Line.LEFT:
			if side == GameConstants.Side.OPPONENT:
				return stat_r
			return stat_l
		GameConstants.Line.CENTER:
			return stat_c
		GameConstants.Line.RIGHT:
			if side == GameConstants.Side.OPPONENT:
				return stat_l
			return stat_r
	return 0


func get_current_field_line_power() -> int:
	var slot = card_slot_card_is_in
	if slot == null:
		return 0
	return get_power_for_line(slot.line, slot.side)


func get_stack_count() -> int:
	return stack_cards.size()


func add_stack_card(attached: Node) -> void:
	if attached == null or not is_instance_valid(attached):
		return
	if attached in stack_cards:
		return
	stack_cards.append(attached)
	attached.stack_host = self
	_hide_stacked_card(attached)
	refresh_stack_display()


func remove_stack_card(attached: Node) -> void:
	if attached == null:
		return
	stack_cards.erase(attached)
	if is_instance_valid(attached):
		attached.stack_host = null
	refresh_stack_display()


func refresh_stack_display() -> void:
	_ensure_stack_badge()
	if _stack_badge == null:
		return
	var on_field := (
		not effect_set
		and (
			reveal_state == GameConstants.RevealState.SETTING_PREVIEW
			or reveal_state == GameConstants.RevealState.REVEALED
		)
	) and zone == EffectTypes.Location.FIELD and card_slot_card_is_in != null
	var count := stack_cards.size()
	_stack_badge.visible = on_field and count > 0
	if _stack_badge.visible:
		var label: Label = _stack_badge.get_node_or_null("Label")
		if label:
			label.text = str(count)


func _hide_stacked_card(attached: Node) -> void:
	if attached == null or not is_instance_valid(attached):
		return
	if attached.get_parent() != self:
		if attached.get_parent():
			attached.get_parent().remove_child(attached)
		add_child(attached)
	attached.visible = false
	attached.position = Vector2.ZERO
	attached.scale = Vector2(0.4, 0.4)
	attached.z_index = 0
	CardHelpers.disable_interaction(attached)
	if attached.has_method("toggle_selection_rect"):
		attached.toggle_selection_rect(false)


func _ensure_stack_badge() -> void:
	if _stack_badge:
		return
	_stack_badge = get_node_or_null("StackBadge") as Panel
	if _stack_badge == null:
		push_warning("[Card] missing StackBadge scene child")
		return
	# 원형 배지 스타일은 런타임 적용 (위치·크기는 card.tscn에서 조정).
	const BADGE_SIZE := 40.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.45, 0.2, 0.9)
	style.corner_radius_top_left = int(BADGE_SIZE * 0.5)
	style.corner_radius_top_right = int(BADGE_SIZE * 0.5)
	style.corner_radius_bottom_left = int(BADGE_SIZE * 0.5)
	style.corner_radius_bottom_right = int(BADGE_SIZE * 0.5)
	_stack_badge.add_theme_stylebox_override("panel", style)


## R 이상 레어도 프레임 노드를 보장한다 (인게임은 테두리·글로우만, 배지 없음).
func _ensure_rarity_nodes() -> void:
	if _rarity_frame != null:
		return
	_rarity_frame = get_node_or_null("RarityFrame") as Panel
	if _rarity_frame == null:
		push_warning("[Card] missing RarityFrame scene child")


## 뒷면(CardBack)이 앞에 보이면 true. 상대 손패·세트 히든 등.
func _is_showing_card_back() -> bool:
	var back := get_node_or_null("CardBackImage") as CanvasItem
	if back == null or not back.visible:
		return false
	var front := get_node_or_null("CardImage") as CanvasItem
	if front == null:
		return true
	if front.modulate.a < 0.05:
		return true
	return int(back.z_index) >= int(front.z_index)


## 등급을 기억하고 현재 앞/뒷면에 맞게 프레임을 갱신한다.
func _apply_rarity_visual(tier: int) -> void:
	_rarity_tier = tier
	refresh_rarity_visual()


## 앞면·R+ 일 때만 테두리 표시. 뒷면이면 숨김 (CardHelpers 시각 갱신에서 호출).
func refresh_rarity_visual() -> void:
	_ensure_rarity_nodes()
	if _rarity_frame != null:
		var show := CardRarity.shows_frame(_rarity_tier) and not _is_showing_card_back()
		_rarity_frame.visible = show
		if show:
			_rarity_frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(_rarity_tier, 3.0))
	# 레어 face FX (틸트 쉐이더). 뒷면이면 tier 0으로 숨김.
	CardHoverTilt.apply_rarity(self, _rarity_tier)


func clear_passive_field_modifiers() -> void:
	# clear 중간(영구 데미지 후 보너스 제거)에 일시적으로 음수가 될 수 있음.
	# destroy는 PASSIVE refresh 전체(clear→재적용) 끝난 뒤에만 판정한다.
	var prev_suppress := _suppress_stat_destroy
	_suppress_stat_destroy = true
	if _passive_line_bonus != 0:
		_adjust_stat_axis(_passive_stat_axis, -_passive_line_bonus)
		_passive_line_bonus = 0
	if _passive_line_absolute >= 0:
		_set_stat_axis(_passive_stat_axis, _stat_before_passive_absolute)
		_passive_line_absolute = -1
	_passive_stat_axis = -1
	_suppress_stat_destroy = prev_suppress
	update_labels()


func clear_stack_effect_flags() -> void:
	skill_immune_from_stack = false


func set_skill_immune_from_stack(value: bool) -> void:
	skill_immune_from_stack = value


func apply_passive_line_bonus(delta: int) -> void:
	if delta == 0:
		return
	_ensure_passive_stat_axis()
	change_stat_on_field_line(delta)
	_passive_line_bonus += delta


func apply_passive_line_absolute(value: int) -> void:
	_ensure_passive_stat_axis()
	if _passive_line_absolute < 0:
		if _passive_stat_axis >= 0:
			_stat_before_passive_absolute = _get_stat_axis(_passive_stat_axis)
		else:
			_stat_before_passive_absolute = get_current_field_line_power()
	set_field_line_stat_absolute(value)
	_passive_line_absolute = value


## 필드 이탈(패/묘지/덱/밴시) 시 card_data 기본 스탯·PASSIVE·SET 플래그 복원. destroy 검사 없음.
func reset_runtime_stats_from_card_data() -> void:
	_passive_line_bonus = 0
	_passive_line_absolute = -1
	_stat_before_passive_absolute = 0
	_passive_stat_axis = -1
	skill_immune_from_stack = false
	effect_set = false
	if card_data == null:
		update_labels()
		return
	stat_l = card_data.stat_l
	stat_c = card_data.stat_c
	stat_r = card_data.stat_r
	update_labels()


func _ensure_passive_stat_axis() -> void:
	if _passive_stat_axis < 0:
		_passive_stat_axis = _resolve_field_stat_axis()


func _resolve_field_stat_axis() -> int:
	var slot = card_slot_card_is_in
	if slot == null:
		return -1
	var field_side: GameConstants.Side = slot.side
	match slot.line:
		GameConstants.Line.LEFT:
			return 0 if field_side == GameConstants.Side.PLAYER else 2
		GameConstants.Line.CENTER:
			return 1
		GameConstants.Line.RIGHT:
			return 2 if field_side == GameConstants.Side.PLAYER else 0
	return -1


func _get_stat_axis(axis: int) -> int:
	match axis:
		0:
			return stat_l
		1:
			return stat_c
		2:
			return stat_r
		_:
			return get_current_field_line_power()


func _set_stat_axis(axis: int, value: int) -> void:
	match axis:
		0:
			stat_l = value
		1:
			stat_c = value
		2:
			stat_r = value
		_:
			if card_slot_card_is_in != null:
				set_field_line_stat_absolute(value)
				return
	# set_field_line_stat_absolute가 destroy 검사하므로, 축 직접 설정 시에만 여기서 검사
	_check_destroy_from_stats()


func _adjust_stat_axis(axis: int, delta: int) -> void:
	if delta == 0:
		return
	match axis:
		0:
			stat_l += delta
		1:
			stat_c += delta
		2:
			stat_r += delta
		_:
			change_stat_on_field_line(delta)
			return
	_check_destroy_from_stats()


func change_stat(delta: int) -> void:
	stat_l += delta
	stat_c += delta
	stat_r += delta
	update_labels()
	_check_destroy_from_stats()


func set_field_line_stat_absolute(value: int) -> void:
	var slot = card_slot_card_is_in
	if slot == null:
		change_stat(value - stat_l)
		return
	var field_side: GameConstants.Side = slot.side
	match slot.line:
		GameConstants.Line.LEFT:
			if field_side == GameConstants.Side.PLAYER:
				stat_l = value
			else:
				stat_r = value
		GameConstants.Line.CENTER:
			stat_c = value
		GameConstants.Line.RIGHT:
			if field_side == GameConstants.Side.PLAYER:
				stat_r = value
			else:
				stat_l = value
	update_labels()
	_check_destroy_from_stats()


func reset_field_line_stat_from_data() -> void:
	if card_data == null:
		return
	var slot = card_slot_card_is_in
	if slot == null:
		stat_l = card_data.stat_l
		stat_c = card_data.stat_c
		stat_r = card_data.stat_r
		update_labels()
		return
	var field_side: GameConstants.Side = slot.side
	match slot.line:
		GameConstants.Line.LEFT:
			if field_side == GameConstants.Side.PLAYER:
				stat_l = card_data.stat_l
			else:
				stat_r = card_data.stat_l
		GameConstants.Line.CENTER:
			stat_c = card_data.stat_c
		GameConstants.Line.RIGHT:
			if field_side == GameConstants.Side.PLAYER:
				stat_r = card_data.stat_r
			else:
				stat_l = card_data.stat_r
	update_labels()
	_check_destroy_from_stats()


func change_stat_on_field_line(delta: int) -> void:
	var slot = card_slot_card_is_in
	if slot == null:
		change_stat(delta)
		return
	var field_side: GameConstants.Side = slot.side
	match slot.line:
		GameConstants.Line.LEFT:
			if field_side == GameConstants.Side.PLAYER:
				stat_l += delta
			else:
				stat_r += delta
		GameConstants.Line.CENTER:
			stat_c += delta
		GameConstants.Line.RIGHT:
			if field_side == GameConstants.Side.PLAYER:
				stat_r += delta
			else:
				stat_l += delta
	update_labels()
	_check_destroy_from_stats()


func change_all_stats(delta: int) -> void:
	change_stat(delta)


func _check_destroy_from_stats() -> void:
	if _suppress_stat_destroy:
		return
	if stat_l < 0 or stat_c < 0 or stat_r < 0:
		destroy_card(false)


## PASSIVE refresh 종료 후 등 — clear 억제 없이 음수 축 destroy 판정
func check_destroy_from_stats() -> void:
	_check_destroy_from_stats()


## 스탯 파괴·효과 킬 등에서 호출. EM.context.destroy_card로 위임 (S3 DI).
func destroy_card(suppress_trash: bool = false) -> void:
	var ctx := _effect_context()
	if ctx:
		ctx.destroy_card(self, suppress_trash)
	else:
		queue_free()


## 씬 트리의 EffectManager.context. 카드는 setup 주입을 받지 않아 조회한다.
func _effect_context() -> EffectContext:
	var tree := get_tree()
	if tree == null:
		return null
	var em := tree.get_first_node_in_group("effect_manager")
	if em == null:
		em = tree.current_scene.get_node_or_null("EffectManager") if tree.current_scene else null
	if em != null and em.get("context") != null:
		return em.context as EffectContext
	return null


## uuid/inst_id가 없을 때 context 발급 또는 randi 폴백.
func _new_instance_id_fallback() -> String:
	var ctx := _effect_context()
	if ctx:
		return ctx.new_instance_id()
	return str(randi())


func apply_hand_visual() -> void:
	CardHelpers.apply_hand_visual(self)
	zone = EffectTypes.Location.HAND


func apply_hand_hidden() -> void:
	CardHelpers.apply_hand_hidden(self)
	zone = EffectTypes.Location.HAND


func apply_setting_preview() -> void:
	CardHelpers.apply_setting_preview(self)
	zone = EffectTypes.Location.FIELD


func apply_setting_hidden(play_flip: bool = true) -> void:
	CardHelpers.apply_setting_hidden(self, play_flip)


func await_apply_setting_hidden(play_flip: bool = true) -> void:
	await CardHelpers.await_setting_hidden(self, play_flip)
	zone = EffectTypes.Location.FIELD


func reveal() -> void:
	CardHelpers.reveal_card(self)
	zone = EffectTypes.Location.FIELD

func toggle_selection_rect(enabled: bool) -> void:
	is_selectable = enabled
	_ensure_selection_overlay()
	_refresh_selection_overlay_size()
	if _selection_overlay == null:
		return
	_selection_overlay.visible = enabled
	if enabled:
		_selection_overlay.add_theme_stylebox_override(
			"panel",
			SelectionHighlight.make_candidate_stylebox()
		)
	var area: Area2D = get_node_or_null("Area2D")
	if area:
		area.input_pickable = enabled or is_interactive
		if enabled:
			area.collision_layer = GameConstants.COLLISION_LAYER_CARD
			area.monitorable = true
		elif not is_interactive:
			area.collision_layer = 0
			area.monitorable = false


func set_selection_chosen(chosen: bool) -> void:
	_ensure_selection_overlay()
	_refresh_selection_overlay_size()
	if _selection_overlay == null:
		return
	if chosen:
		_selection_overlay.visible = true
		_selection_overlay.add_theme_stylebox_override(
			"panel",
			SelectionHighlight.make_chosen_stylebox()
		)
	elif is_selectable:
		_selection_overlay.visible = true
		_selection_overlay.add_theme_stylebox_override(
			"panel",
			SelectionHighlight.make_candidate_stylebox()
		)
	else:
		_selection_overlay.visible = false


func _ensure_selection_overlay() -> void:
	if _selection_overlay:
		_refresh_selection_overlay_size()
		return
	_selection_overlay = get_node_or_null("SelectionOverlay") as Panel
	if _selection_overlay == null:
		# 씬 자식 누락 시 런타임 폴백 (슬롯 CandidateOverlay와 동일).
		_selection_overlay = Panel.new()
		_selection_overlay.name = "SelectionOverlay"
		_selection_overlay.visible = false
		_selection_overlay.z_index = 10
		_selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_selection_overlay)
	_selection_overlay.add_theme_stylebox_override("panel", SelectionHighlight.make_candidate_stylebox())
	_refresh_selection_overlay_size()


## 하이라이트를 CardImage(없으면 CardBack) 표시 크기에 맞춤.
func _refresh_selection_overlay_size() -> void:
	if _selection_overlay == null:
		return
	var img := get_node_or_null("CardImage") as Sprite2D
	if img == null or img.texture == null or not img.visible:
		img = get_node_or_null("CardBackImage") as Sprite2D
	SelectionHighlight.configure_world_overlay(
		_selection_overlay,
		SelectionHighlight.overlay_size_from_sprite(img)
	)


func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)


func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)


func _on_area_2d_input_event(viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_selectable or is_interactive:
			emit_signal("card_clicked", self)
			if is_selectable:
				viewport.set_input_as_handled()
