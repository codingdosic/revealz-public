class_name CardHoverTilt
extends RefCounted
## 인게임 카드: 강체 기울임 + 레어도 아웃라인.
## CardImage = tilt+outline / CardBackImage = tilt only (rarity_tier=0).


const SHADER_PATH := "res://shaders/card_rigid_tilt.gdshader"
## Area2D 충돌(158×220) 반사이즈 — 로컬 마우스를 -1..1로 정규화.
const HALF_EXTENTS := Vector2(79.0, 110.0)
const MAX_TILT_DEG := 20.0
## 지수 감쇠 — 낮으면 커서를 뒤따라 꿀렁, 높으면 면에 붙음.
const FOLLOW_STIFFNESS := 28.0
const SETTLE_EPS := 0.04

const META_HOVER := &"_card_tilt_hover"
const META_TX := &"_card_tilt_x"
const META_TY := &"_card_tilt_y"
const META_MAT_FRONT := &"_card_tilt_mat_front"
const META_MAT_BACK := &"_card_tilt_mat_back"

static var _shader: Shader


## 호버 기울임 on/off. off면 0으로 보간 후 process 정지.
static func set_hovering(card: Node2D, enabled: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	_ensure_materials(card)
	card.set_meta(META_HOVER, enabled)
	if enabled:
		card.set_process(true)
	elif not card.has_meta(META_TX):
		card.set_meta(META_TX, 0.0)
		card.set_meta(META_TY, 0.0)


## instance_rarity를 앞면 material에 반영. 호버 전에도 아웃라인이 보이도록 init에서 호출.
static func apply_rarity(card: Node2D, tier: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	_ensure_materials(card)
	var t := clampi(tier, CardRarity.Tier.N, CardRarity.Tier.UR)
	# 뒷면이 보이는 동안엔 아웃라인 끄기 (공유 방지 — front mat만 사용).
	var show_fx := CardRarity.shows_display(t)
	if card.has_method("_is_showing_card_back") and card._is_showing_card_back():
		show_fx = false
	var mat: Variant = card.get_meta(META_MAT_FRONT, null)
	if mat is ShaderMaterial and is_instance_valid(mat):
		var sm := mat as ShaderMaterial
		sm.set_shader_parameter("rarity_tier", float(t if show_fx else CardRarity.Tier.N))
		sm.set_shader_parameter("rarity_hint", 0.0)
		var accent := CardRarity.accent_of(t)
		sm.set_shader_parameter("rarity_accent", Vector4(accent.r, accent.g, accent.b, accent.a))
		CardRarityFoil.bind_holo_maps(sm)


## 매 프레임: 커서 쪽 모서리가 화면 안쪽(축소)으로 가도록 tilt 갱신.
static func process(card: Node2D, delta: float) -> void:
	if card == null or not is_instance_valid(card):
		return
	var hovering := bool(card.get_meta(META_HOVER, false))
	# Face/zone 무효면 호버 메타만 끈다 (스케일은 CardManager가 담당).
	if hovering and not _is_face_tilt_valid(card):
		card.set_meta(META_HOVER, false)
		hovering = false
	var target_x := 0.0
	var target_y := 0.0
	if hovering:
		var local := card.get_local_mouse_position()
		var nx := clampf(local.x / HALF_EXTENTS.x, -1.0, 1.0)
		var ny := clampf(local.y / HALF_EXTENTS.y, -1.0, 1.0)
		# 우측(+x) → tilt_y+ (우측 축소). 하단(+y) → tilt_x- (하단 축소).
		target_y = nx * MAX_TILT_DEG
		target_x = -ny * MAX_TILT_DEG

	var cur_x := float(card.get_meta(META_TX, 0.0))
	var cur_y := float(card.get_meta(META_TY, 0.0))
	var t := 1.0 - exp(-FOLLOW_STIFFNESS * delta)
	cur_x = lerpf(cur_x, target_x, t)
	cur_y = lerpf(cur_y, target_y, t)
	card.set_meta(META_TX, cur_x)
	card.set_meta(META_TY, cur_y)
	_apply_tilt(card, cur_x, cur_y)

	if not hovering and absf(cur_x) < SETTLE_EPS and absf(cur_y) < SETTLE_EPS:
		card.set_meta(META_TX, 0.0)
		card.set_meta(META_TY, 0.0)
		_apply_tilt(card, 0.0, 0.0)
		card.set_process(false)


## 앞면·허용 zone일 때만 tilt 유지.
static func _is_face_tilt_valid(card: Node2D) -> bool:
	if not card.visible:
		return false
	var zone: Variant = card.get("zone")
	if zone != null:
		var z := int(zone)
		if z == EffectTypes.Location.GRAVE \
			or z == EffectTypes.Location.BANISH \
			or z == EffectTypes.Location.DECK:
			return false
	if card.has_method("_is_showing_card_back") and card._is_showing_card_back():
		return false
	var rs: Variant = card.get("reveal_state")
	if rs == null:
		return true
	return rs in [
		GameConstants.RevealState.HAND,
		GameConstants.RevealState.SETTING_PREVIEW,
		GameConstants.RevealState.REVEALED,
	]


## 플립/드래그 등으로 즉시 평평하게.
static func snap_flat(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.set_meta(META_HOVER, false)
	card.set_meta(META_TX, 0.0)
	card.set_meta(META_TY, 0.0)
	_apply_tilt(card, 0.0, 0.0)
	card.set_process(false)


static func _ensure_materials(card: Node2D) -> void:
	var front_ok := card.has_meta(META_MAT_FRONT) \
		and card.get_meta(META_MAT_FRONT) is ShaderMaterial \
		and is_instance_valid(card.get_meta(META_MAT_FRONT))
	if front_ok:
		_sync_half_size_params(card)
		return
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	if _shader == null:
		push_error("CardHoverTilt: failed to load %s" % SHADER_PATH)
		return
	var front := ShaderMaterial.new()
	front.shader = _shader
	front.set_shader_parameter("card_half_size", HALF_EXTENTS)
	front.set_shader_parameter("corner_origin", 0.0)
	front.set_shader_parameter("rarity_hint", 0.0)
	CardRarityFoil.bind_holo_maps(front)
	var back := ShaderMaterial.new()
	back.shader = _shader
	back.set_shader_parameter("rarity_tier", 0.0)
	back.set_shader_parameter("rarity_hint", 0.0)
	back.set_shader_parameter("card_half_size", HALF_EXTENTS)
	back.set_shader_parameter("corner_origin", 0.0)
	card.set_meta(META_MAT_FRONT, front)
	card.set_meta(META_MAT_BACK, back)
	var img := card.get_node_or_null("CardImage") as CanvasItem
	if img:
		img.material = front
	var bk := card.get_node_or_null("CardBackImage") as CanvasItem
	if bk:
		bk.material = back


static func _sync_half_size_params(card: Node2D) -> void:
	for key in [META_MAT_FRONT, META_MAT_BACK]:
		var mat: Variant = card.get_meta(key, null)
		if mat is ShaderMaterial and is_instance_valid(mat):
			var sm := mat as ShaderMaterial
			sm.set_shader_parameter("card_half_size", HALF_EXTENTS)
			sm.set_shader_parameter("corner_origin", 0.0)


static func _apply_tilt(card: Node2D, tilt_x: float, tilt_y: float) -> void:
	for key in [META_MAT_FRONT, META_MAT_BACK]:
		var mat: Variant = card.get_meta(key, null)
		if mat is ShaderMaterial and is_instance_valid(mat):
			(mat as ShaderMaterial).set_shader_parameter("tilt_x_deg", tilt_x)
			(mat as ShaderMaterial).set_shader_parameter("tilt_y_deg", tilt_y)
