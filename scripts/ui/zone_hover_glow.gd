class_name ZoneHoverGlow
extends Sprite2D
## 존(묘지·제외) 호버용 radial 링 글로우 — 중앙 투명, 가장자리만 발광.


const GLOW_TEX_SIZE := 128
const BASE_SIZE := Vector2(158, 220)
const PEAK_SCALE := Vector2(1.06, 1.06)
const FADE_IN_SEC := 0.12
const FADE_OUT_SEC := 0.1
## 텍스처 프로필 변경 시 bump (캐시 무효화).
const _TEXTURE_GEN := 2
## normalized radius: 이보다 안쪽은 거의 투명(중앙 선명).
const RING_INNER_CLEAR := 0.3
## 링 peak 위치 · 두께.
const RING_PEAK_RADIUS := 0.7
const RING_PEAK_SIGMA := 0.1

static var _shared_texture: Texture2D
static var _shared_texture_gen: int = 0

var _highlighted: bool = false
var _tween: Tween
var _rest_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	texture = _get_shared_texture()
	centered = true
	z_index = -2
	_rest_scale = scale
	modulate = Color(0.364, 0.814, 1.0, 0.0)
	visible = true


## 호버 on/off. 부드럽게 fade·scale.
func set_highlighted(on: bool) -> void:
	if _highlighted == on:
		return
	_highlighted = on
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if on:
		_tween.tween_property(self, "modulate:a", 0.62, FADE_IN_SEC).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "scale", _peak_scale(), FADE_IN_SEC).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_IN)
		_tween.tween_property(self, "scale", _base_scale(), FADE_OUT_SEC).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_IN)


static func attach_to(parent: Node2D, size: Vector2 = BASE_SIZE) -> ZoneHoverGlow:
	var glow := ZoneHoverGlow.new()
	glow.name = "ZoneHoverGlow"
	parent.add_child(glow)
	glow._rest_scale = size / float(GLOW_TEX_SIZE)
	glow.scale = glow._rest_scale
	return glow


static func _get_shared_texture() -> Texture2D:
	if _shared_texture != null and _shared_texture_gen == _TEXTURE_GEN:
		return _shared_texture
	var img := Image.create(GLOW_TEX_SIZE, GLOW_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(GLOW_TEX_SIZE * 0.5, GLOW_TEX_SIZE * 0.5)
	var radius := GLOW_TEX_SIZE * 0.5
	for y in GLOW_TEX_SIZE:
		for x in GLOW_TEX_SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
			var a := 0.0
			if d >= RING_INNER_CLEAR:
				var ring := exp(-pow(d - RING_PEAK_RADIUS, 2) / (2.0 * RING_PEAK_SIGMA * RING_PEAK_SIGMA))
				var outer_fade := 1.0 - smoothstep(0.92, 1.0, d)
				a = ring * outer_fade * 0.98
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_shared_texture = ImageTexture.create_from_image(img)
	_shared_texture_gen = _TEXTURE_GEN
	return _shared_texture


func _base_scale() -> Vector2:
	return _rest_scale


func _peak_scale() -> Vector2:
	return _rest_scale * PEAK_SCALE
