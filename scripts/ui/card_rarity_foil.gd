class_name CardRarityFoil
extends RefCounted
## UI 일러스트(칩·팩 힌트·사이드바 등)용 레어 material.
## 앞면: foil 쉬인 + 아웃라인. 힌트(as_hint): 아웃라인 글로우만. tilt_x/y 기본 0.
## Control은 card_half_size=size*0.5 필수 — 미설정 시 UV가 찌그러질 수 있음.


const SHADER_PATH := "res://shaders/card_rigid_tilt.gdshader"
const HOLO_RAINBOW := preload("res://resources/ui/holo_rainbow.tres")
const HOLO_DISTORT := preload("res://resources/ui/holo_distort.tres")
const META_RESIZE_CB := &"_card_rarity_foil_resized_cb"

static var _shader: Shader


## R+면 아웃라인 material을 붙이고, N이면 material을 제거한다.
## as_hint=true → 팩/칩 레어도 힌트용 넓은 글로우·펄스.
static func apply(item: CanvasItem, tier: int, as_hint: bool = false) -> void:
	if item == null or not is_instance_valid(item):
		return
	var t := clampi(tier, CardRarity.Tier.N, CardRarity.Tier.UR)
	if not CardRarity.shows_display(t):
		clear(item)
		return
	var shader := _get_shader()
	if shader == null:
		return
	var mat := item.material as ShaderMaterial
	if mat == null or mat.shader != shader:
		mat = ShaderMaterial.new()
		mat.shader = shader
		item.material = mat
	mat.set_shader_parameter("tilt_x_deg", 0.0)
	mat.set_shader_parameter("tilt_y_deg", 0.0)
	mat.set_shader_parameter("corner_origin", 1.0)
	mat.set_shader_parameter("rarity_tier", float(t))
	mat.set_shader_parameter("rarity_hint", 1.0 if as_hint else 0.0)
	bind_holo_maps(mat)
	var accent := CardRarity.accent_of(t)
	mat.set_shader_parameter("rarity_accent", Vector4(accent.r, accent.g, accent.b, accent.a))
	_sync_half_size(item)
	_ensure_resize_hook(item)
	# 레이아웃 전 size=0이면 한 프레임 뒤 재동기화
	if item is Control and (item as Control).size.x < 1.0:
		Callable(CardRarityFoil, "_sync_half_size").call_deferred(item)


## N은 tilt만(rarity_tier=0), R+는 foil+아웃라인. 팩 칩 앞면용.
static func apply_or_tilt(item: CanvasItem, tier: int, as_hint: bool = false) -> void:
	if item == null or not is_instance_valid(item):
		return
	var t := clampi(tier, CardRarity.Tier.N, CardRarity.Tier.UR)
	if CardRarity.shows_display(t):
		apply(item, t, as_hint)
		return
	var shader := _get_shader()
	if shader == null:
		return
	var mat := item.material as ShaderMaterial
	if mat == null or mat.shader != shader:
		mat = ShaderMaterial.new()
		mat.shader = shader
		item.material = mat
	mat.set_shader_parameter("tilt_x_deg", 0.0)
	mat.set_shader_parameter("tilt_y_deg", 0.0)
	mat.set_shader_parameter("corner_origin", 1.0)
	mat.set_shader_parameter("rarity_tier", 0.0)
	mat.set_shader_parameter("rarity_hint", 0.0)
	bind_holo_maps(mat)
	_sync_half_size(item)
	_ensure_resize_hook(item)
	if item is Control and (item as Control).size.x < 1.0:
		Callable(CardRarityFoil, "_sync_half_size").call_deferred(item)


## ShaderMaterial tilt 각도. foil shader가 아니면 무시.
static func set_tilt(item: CanvasItem, tilt_x: float, tilt_y: float) -> void:
	if item == null or not is_instance_valid(item):
		return
	var mat := item.material as ShaderMaterial
	if mat == null or mat.shader != _get_shader():
		return
	mat.set_shader_parameter("tilt_x_deg", tilt_x)
	mat.set_shader_parameter("tilt_y_deg", tilt_y)


## SR 홀로포일용 레인보우·왜곡 텍스처.
static func bind_holo_maps(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("holo_rainbow", HOLO_RAINBOW)
	mat.set_shader_parameter("holo_distort", HOLO_DISTORT)


## foil/기타 material을 제거한다.
static func clear(item: CanvasItem) -> void:
	if item == null or not is_instance_valid(item):
		return
	_clear_resize_hook(item)
	item.material = null


static func _sync_half_size(item: CanvasItem) -> void:
	var mat := item.material as ShaderMaterial
	if mat == null or mat.shader != _get_shader():
		return
	if item is Control:
		mat.set_shader_parameter("card_half_size", (item as Control).size * 0.5)
	else:
		mat.set_shader_parameter("card_half_size", Vector2.ZERO)


static func _ensure_resize_hook(item: CanvasItem) -> void:
	if not item is Control:
		return
	var ctrl := item as Control
	if ctrl.has_meta(META_RESIZE_CB):
		return
	var cb := _on_control_resized.bind(ctrl)
	ctrl.set_meta(META_RESIZE_CB, cb)
	ctrl.resized.connect(cb)


static func _clear_resize_hook(item: CanvasItem) -> void:
	if not item is Control:
		return
	var ctrl := item as Control
	if not ctrl.has_meta(META_RESIZE_CB):
		return
	var cb: Callable = ctrl.get_meta(META_RESIZE_CB)
	if ctrl.resized.is_connected(cb):
		ctrl.resized.disconnect(cb)
	ctrl.remove_meta(META_RESIZE_CB)


static func _on_control_resized(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	_sync_half_size(ctrl)


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
		if _shader == null:
			push_error("CardRarityFoil: failed to load %s" % SHADER_PATH)
	return _shader
