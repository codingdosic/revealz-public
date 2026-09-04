class_name DeckCardChip
extends PanelContainer
## 카드 칩 UI (`scenes/ui/card_chip.tscn`). 일러스트·보유 배지·흑백·팩 개봉 플립.
## 덱에디터: 드래그/우클릭 가감. 팩개봉: face-down → Y축 tilt 플립(+lift).


signal info_requested(card_name: String, rarity: int)
signal add_requested(card_name: String, rarity: int)
signal remove_requested(slot_index: int)
## 앞면으로 뒤집히기 시작(또는 완료 직전 커밋) 시.
signal revealed(card_name: String)

const SCENE_PATH := "res://scenes/ui/card_chip.tscn"
const CARD_BACK_PATH := "res://assets_lite/ShopAsset/card_back.png"
const CARD_ASPECT := 158.0 / 220.0
## SR+ 공개 연출.
const REVEAL_FX_FLASH_SEC := 0.28
const REVEAL_FX_PULSE_SEC := 0.22
## 뒷면 미리보기 글로우(R+ · 50%).
const BACK_GLOW_HINT_CHANCE := 0.5
const BACK_GLOW_PULSE_SEC := 1.1
## 팩 개봉 앞면 칩 호버 틸트 (줌 오버레이와 동일 셰이더).
const CHIP_TILT_MAX_DEG := 12.0
const CHIP_TILT_FOLLOW := 28.0
const CHIP_TILT_SETTLE := 0.04
const _GRAY_SHADER := """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g), c.a);
}
"""

var card_name: String = ""
var is_deck_slot: bool = false
var slot_index: int = -1
## 이 칩이 나타내는 카피 등급 (CardData.rarity와 무관).
var instance_rarity: int = CardRarity.Tier.N

var _layer: Control
var _art: TextureRect
var _empty_label: Label
var _count_badge: Panel
var _count_label: Label
var _rarity_frame: Panel
var _rarity_badge: Panel
var _rarity_label: Label
var _front_texture: Texture2D
var _rarity_tier: int = CardRarity.Tier.N
var _face_up: bool = true
var _pack_reveal: bool = false
var _flipping: bool = false
## 검색 미소지 흑백. true면 foil 대신 grayscale material.
var _grayscale: bool = false
## true면 우상단 레어도 배지를 강제로 숨김 (존 peek 등).
var _rarity_badge_forced_hidden: bool = false
## 팩 뒷면에서 SR+ 등급색 글로우를 미리 보여줄지 (50%).
var _back_glow_hint: bool = false
var _flip_tween: Tween
var _reveal_fx_tween: Tween
var _back_glow_tween: Tween
var _reveal_flash: ColorRect
var _tilt_hovering: bool = false
var _tilt_x: float = 0.0
var _tilt_y: float = 0.0
var _tilt_signals_connected: bool = false
static var _gray_material: ShaderMaterial
static var _badge_style: StyleBoxFlat
static var _scene: PackedScene
static var _card_back: Texture2D


## 씬 인스턴스를 만든다 (코드 `new()` 대신 사용). 스크립트↔씬 순환 preload 회피.
static func instantiate_chip() -> DeckCardChip:
	if _scene == null:
		_scene = load(SCENE_PATH) as PackedScene
	return _scene.instantiate() as DeckCardChip


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bind_nodes()


func _process(delta: float) -> void:
	if not _pack_reveal or not _face_up or _flipping or _art == null:
		_snap_chip_tilt_flat()
		return
	var target_x := 0.0
	var target_y := 0.0
	if _tilt_hovering:
		var sz := size
		if sz.x > 1.0 and sz.y > 1.0:
			var local := get_local_mouse_position()
			var nx := clampf(local.x / (sz.x * 0.5) - 1.0, -1.0, 1.0)
			var ny := clampf(local.y / (sz.y * 0.5) - 1.0, -1.0, 1.0)
			target_y = nx * CHIP_TILT_MAX_DEG
			target_x = -ny * CHIP_TILT_MAX_DEG
	var t := 1.0 - exp(-CHIP_TILT_FOLLOW * delta)
	_tilt_x = lerpf(_tilt_x, target_x, t)
	_tilt_y = lerpf(_tilt_y, target_y, t)
	CardRarityFoil.set_tilt(_art, _tilt_x, _tilt_y)
	if not _tilt_hovering and absf(_tilt_x) < CHIP_TILT_SETTLE and absf(_tilt_y) < CHIP_TILT_SETTLE:
		_snap_chip_tilt_flat()


func _on_chip_mouse_entered() -> void:
	if not _pack_reveal or not _face_up or _flipping:
		return
	_tilt_hovering = true
	set_process(true)


func _on_chip_mouse_exited() -> void:
	_tilt_hovering = false


func _snap_chip_tilt_flat() -> void:
	_tilt_hovering = false
	_tilt_x = 0.0
	_tilt_y = 0.0
	if _art:
		CardRarityFoil.set_tilt(_art, 0.0, 0.0)
	set_process(false)


## 공유 카드 뒷면 텍스처.
static func _get_card_back() -> Texture2D:
	if _card_back == null:
		_card_back = load(CARD_BACK_PATH) as Texture2D
	return _card_back


## 칩을 카드 이름·슬롯 역할·크기·카피 등급으로 설정한다. 기본은 앞면.
func setup(
	p_name: String,
	p_is_deck_slot: bool,
	p_slot_index: int = -1,
	chip_size: Vector2 = Vector2(72, 100),
	p_rarity: int = CardRarity.Tier.N
) -> void:
	card_name = p_name
	is_deck_slot = p_is_deck_slot
	slot_index = p_slot_index
	instance_rarity = clampi(p_rarity, CardRarity.Tier.N, CardRarity.Tier.UR)
	_pack_reveal = false
	_face_up = true
	_flipping = false
	_rarity_badge_forced_hidden = false
	_rarity_tier = instance_rarity
	_bind_nodes()
	_reset_layer_scale()
	set_chip_size(chip_size)
	_apply_art()
	set_grayscale(false)
	set_owned_count(-1)


## 카피 등급을 바꾸고 프레임/배지를 갱신한다.
func set_instance_rarity(tier: int) -> void:
	instance_rarity = clampi(tier, CardRarity.Tier.N, CardRarity.Tier.UR)
	_rarity_tier = instance_rarity
	_apply_rarity_visual()


## 우상단 레어도 배지 표시 강제 on/off (존 peek 연출용).
func set_rarity_badge_visible(visible: bool) -> void:
	_rarity_badge_forced_hidden = not visible
	_apply_rarity_visual()


## 팩 개봉용: 뒷면으로 두고 클릭 시 플립한다.
## back_glow_hint가 null이면 R+ 50% 롤, bool이면 그 값(R+만 유효).
func enable_pack_reveal(back_glow_hint: Variant = null) -> void:
	_pack_reveal = true
	_face_up = false
	_flipping = false
	if back_glow_hint == null:
		_back_glow_hint = (
			CardRarity.shows_display(instance_rarity)
			and randf() < BACK_GLOW_HINT_CHANCE
		)
	else:
		_back_glow_hint = (
			CardRarity.shows_display(instance_rarity)
			and bool(back_glow_hint)
		)
	_kill_reveal_fx_tween()
	_kill_back_glow_tween()
	_reset_layer_scale()
	_apply_face_visual()


## 앞면이면 true (플립 커밋 후 포함).
func is_face_up() -> bool:
	return _face_up


## 플립 애니 중이면 true.
func is_flipping() -> bool:
	return _flipping


## 뒷면이면 앞면 플립을 시작한다. 이미 앞면/플립 중이면 무시.
func flip_to_front() -> void:
	if not _pack_reveal or _face_up or _flipping or card_name.is_empty():
		return
	_play_flip_to_front()


## 애니 없이 즉시 앞면 (Skip용). SR+ 연출·뒷면 힌트 펄스는 생략.
func reveal_instant() -> void:
	if _face_up and not _flipping:
		return
	_kill_flip_tween()
	_kill_reveal_fx_tween()
	_kill_back_glow_tween()
	_back_glow_hint = false
	_flipping = false
	_face_up = true
	_reset_layer_scale()
	_snap_chip_tilt_flat()
	_apply_face_visual()
	revealed.emit(card_name)


## 칩 표시 크기를 바꾼다 (중앙 6×5 맞춤용).
func set_chip_size(chip_size: Vector2) -> void:
	custom_minimum_size = chip_size
	size = chip_size


## 검색 결과 미소지용 흑백. 덱 슬롯·팩 칩은 호출하지 않음. 흑백이면 foil 없음.
func set_grayscale(enabled: bool) -> void:
	_grayscale = enabled
	_refresh_art_material()


## 검색 결과 우하단 보유 장수. count < 0 이면 숨김 (덱 슬롯).
func set_owned_count(count: int) -> void:
	_bind_nodes()
	if _count_badge == null:
		return
	if count < 0 or card_name.is_empty():
		_count_badge.visible = false
		return
	_count_badge.visible = true
	_count_label.text = str(count)


## 좌클릭 → 팩 뒷면=플립 · 앞면/일반=정보. 우클릭 → 덱 가감(팩 개봉 중엔 무시).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _pack_reveal and not _face_up:
				flip_to_front()
			elif not card_name.is_empty():
				info_requested.emit(card_name, instance_rarity)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _pack_reveal:
				accept_event()
				return
			if is_deck_slot:
				remove_requested.emit(slot_index)
			elif not card_name.is_empty():
				add_requested.emit(card_name, instance_rarity)
			accept_event()


## 검색·덱 슬롯 드래그. 팩 개봉·빈 슬롯은 불가. 데이터={card_name, rarity, slot_index, is_deck_slot}.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _pack_reveal or card_name.is_empty():
		return null
	_bind_nodes()
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(64, 64 / CARD_ASPECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if _art and _art.texture:
		preview.texture = _art.texture
		preview.material = _art.material
	set_drag_preview(preview)
	return {
		"card_name": card_name,
		"rarity": instance_rarity,
		"slot_index": slot_index,
		"is_deck_slot": is_deck_slot,
	}


## 씬 자식 노드를 캐시하고 배지 스타일을 입힌다. instantiate 직후·트리 진입 전에도 안전.
func _bind_nodes() -> void:
	if _layer == null:
		_layer = get_node_or_null("Layer") as Control
		_art = get_node_or_null("Layer/Art") as TextureRect
		_empty_label = get_node_or_null("Layer/EmptyLabel") as Label
		_count_badge = get_node_or_null("Layer/OwnedBadge") as Panel
		_count_label = get_node_or_null("Layer/OwnedBadge/Label") as Label
		_rarity_frame = get_node_or_null("Layer/RarityFrame") as Panel
		_rarity_badge = get_node_or_null("Layer/RarityBadge") as Panel
		_rarity_label = get_node_or_null("Layer/RarityBadge/Label") as Label
		if _count_badge:
			_count_badge.add_theme_stylebox_override("panel", _get_badge_style())
	_ensure_tilt_signals()


## 팩 칩 호버 틸트 시그널 (한 번만).
func _ensure_tilt_signals() -> void:
	if _tilt_signals_connected:
		return
	if not is_inside_tree():
		return
	mouse_entered.connect(_on_chip_mouse_entered)
	mouse_exited.connect(_on_chip_mouse_exited)
	_tilt_signals_connected = true
	set_process(false)


## 앞면 텍스처를 캐시하고 현재 face 상태에 맞게 그린다. 등급은 instance_rarity 유지.
func _apply_art() -> void:
	_bind_nodes()
	if _art == null or _empty_label == null:
		return
	_front_texture = null
	_rarity_tier = instance_rarity
	if card_name.is_empty():
		_art.texture = null
		_art.visible = false
		_empty_label.visible = true
		_apply_rarity_visual()
		return
	_empty_label.visible = false
	_art.visible = true
	var data := CardRegistry.get_by_name(card_name)
	if data != null and data.illustration:
		_front_texture = data.illustration
	if _front_texture == null:
		var path := "res://assets/Black/%s.png" % card_name
		if ResourceLoader.exists(path):
			_front_texture = load(path) as Texture2D
	_apply_face_visual()


## 앞/뒷면 텍스처를 Art에 반영한다.
func _apply_face_visual() -> void:
	_bind_nodes()
	if _art == null or _empty_label == null:
		return
	if card_name.is_empty():
		_art.texture = null
		_art.visible = false
		_empty_label.visible = true
		_apply_rarity_visual()
		return
	_empty_label.visible = false
	_art.visible = true
	if _face_up:
		_art.texture = _front_texture
	else:
		_art.texture = _get_card_back()
	_apply_rarity_visual()


## 앞면: N+ 배지, R+ 아웃라인. 뒷면: R+ 힌트 시 아웃라인(배지 없음).
## StyleBox 프레임은 CardRarity.ENABLE_STYLEBOX_FRAME 게이트.
## 미소지 흑백이면 아웃라인 material 없음.
func _apply_rarity_visual() -> void:
	_bind_nodes()
	var show_badge := (
		_face_up
		and not _grayscale
		and not _rarity_badge_forced_hidden
		and CardRarity.shows_badge(_rarity_tier)
	)
	var show_front_frame := _face_up and not _grayscale and CardRarity.shows_frame(_rarity_tier)
	var show_back_hint := (
		not _face_up
		and _pack_reveal
		and _back_glow_hint
		and CardRarity.shows_display(_rarity_tier)
	)
	if _rarity_frame:
		_rarity_frame.visible = show_front_frame
		if show_front_frame:
			_rarity_frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(_rarity_tier, 2.0))
	if _rarity_badge:
		_rarity_badge.visible = show_badge
		if show_badge:
			_rarity_badge.add_theme_stylebox_override("panel", CardRarity.make_badge_style(_rarity_tier))
	if _rarity_label and show_badge:
		_rarity_label.text = CardRarity.label_of(_rarity_tier)
	_refresh_art_material()
	if show_back_hint:
		_start_back_glow_pulse()
	else:
		_kill_back_glow_tween()


## Art material: 미소지 흑백 > 앞면 R+ foil+아웃라인 > 뒷면 힌트 아웃라인 > 없음.
func _refresh_art_material() -> void:
	_bind_nodes()
	if _art == null:
		return
	if _grayscale:
		_art.material = _get_gray_material()
		return
	if _face_up and _pack_reveal:
		CardRarityFoil.apply_or_tilt(_art, _rarity_tier, false)
		return
	if _face_up and CardRarity.shows_display(_rarity_tier):
		CardRarityFoil.apply(_art, _rarity_tier, false)
		return
	if (
		not _face_up
		and _pack_reveal
		and _back_glow_hint
		and CardRarity.shows_display(_rarity_tier)
	):
		CardRarityFoil.apply(_art, _rarity_tier, true)
		return
	CardRarityFoil.clear(_art)


## 뒷면 힌트용 프레임 — 등급 accent 글로우만 (면은 투명).
func _make_back_hint_frame_style(tier: int) -> StyleBoxFlat:
	var accent := CardRarity.accent_of(tier)
	var is_ur := tier >= CardRarity.Tier.UR
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.draw_center = false
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85 if is_ur else 0.7)
	style.set_border_width_all(2)
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.5 if is_ur else 0.38)
	style.shadow_size = 16 if is_ur else 12
	style.shadow_offset = Vector2.ZERO
	return style


## 뒷면 힌트 글로우를 약하게 숨쉬게 한다 (아웃라인 위 modulate).
func _start_back_glow_pulse() -> void:
	_bind_nodes()
	if _art == null:
		return
	_kill_back_glow_tween()
	_art.modulate = Color(1, 1, 1, 0.88)
	_back_glow_tween = create_tween()
	_back_glow_tween.set_loops()
	_back_glow_tween.tween_property(
		_art, "modulate:a", 1.0, BACK_GLOW_PULSE_SEC * 0.5
	).set_ease(Tween.EASE_IN_OUT)
	_back_glow_tween.tween_property(
		_art, "modulate:a", 0.82, BACK_GLOW_PULSE_SEC * 0.5
	).set_ease(Tween.EASE_IN_OUT)


## 인게임과 동일: Y축 tilt 플립 (팩은 lift/slam 없이 제자리).
func _play_flip_to_front() -> void:
	_bind_nodes()
	_snap_chip_tilt_flat()
	_kill_back_glow_tween()
	if _rarity_frame:
		_rarity_frame.modulate = Color(1, 1, 1, 1)
	if _art == null:
		_face_up = true
		_back_glow_hint = false
		_apply_face_visual()
		revealed.emit(card_name)
		return
	_kill_flip_tween()
	_flipping = true
	_tilt_hovering = false
	set_process(false)
	# 뒷면에도 tilt material 필요 (힌트 없는 N 포함).
	CardRarityFoil.apply_or_tilt(_art, 0, false)
	if _art:
		_art.modulate = Color(1, 1, 1, 1)

	var flip_sec := GameConstants.CARD_FLIP_TOTAL_SEC
	var half := GameConstants.CARD_FLIP_SWAP_SEC
	var second := maxf(0.01, flip_sec - half)
	var edge := GameConstants.CARD_FLIP_EDGE_DEG
	var pitch := GameConstants.CARD_FLIP_PITCH_DEG

	_flip_tween = create_tween()
	_flip_tween.set_parallel(false)
	_flip_tween.tween_method(
		func(y: float) -> void: _sample_pack_flip_tilt(y, edge, pitch),
		0.0, edge, half
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(func() -> void: _on_pack_flip_edge_swap(edge, pitch))
	_flip_tween.tween_method(
		func(y: float) -> void: _sample_pack_flip_tilt(y, edge, pitch),
		-edge, 0.0, second
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_callback(_on_flip_finished)


## 플립 각도 샘플 — CardHoverTilt._flip_tilt_sample 과 동일.
func _sample_pack_flip_tilt(tilt_y: float, edge: float, pitch: float) -> void:
	var t := clampf(absf(tilt_y) / maxf(edge, 0.001), 0.0, 1.0)
	_tilt_x = pitch * t
	_tilt_y = tilt_y
	if _art:
		CardRarityFoil.set_tilt(_art, _tilt_x, _tilt_y)


## 옆면 시점: 앞면 커밋 후 -edge에서 펼침 시작.
func _on_pack_flip_edge_swap(edge: float, pitch: float) -> void:
	_commit_front_face()
	_sample_pack_flip_tilt(-edge, edge, pitch)


## 플립 중간: 앞면 텍스처로 바꾸고 revealed.
func _commit_front_face() -> void:
	_face_up = true
	_back_glow_hint = false
	_apply_face_visual()
	revealed.emit(card_name)


## 플립 트윈 종료. SR+면 등급색 연출.
func _on_flip_finished() -> void:
	_flipping = false
	_reset_layer_scale()
	_snap_chip_tilt_flat()
	if CardRarity.plays_reveal_fx(instance_rarity):
		_play_rare_reveal_fx()


## SR/UR 공개: 등급 accent 플래시 + 짧은 펄스. Skip(reveal_instant)에서는 호출하지 않음.
func _play_rare_reveal_fx() -> void:
	_bind_nodes()
	if _layer == null:
		return
	_kill_reveal_fx_tween()
	var accent := CardRarity.accent_of(instance_rarity)
	var is_ur := instance_rarity >= CardRarity.Tier.UR
	var flash_a := 0.55 if is_ur else 0.38
	var pulse := 1.1 if is_ur else 1.06
	var glow_boost := 18 if is_ur else 14

	var flash := _ensure_reveal_flash()
	flash.color = Color(accent.r, accent.g, accent.b, flash_a)
	flash.visible = true
	flash.modulate = Color(1, 1, 1, 1)

	if _rarity_frame and _rarity_frame.visible:
		var boosted := CardRarity.make_frame_style(instance_rarity, 2.5)
		boosted.shadow_size = glow_boost
		boosted.shadow_color = Color(accent.r, accent.g, accent.b, 0.55 if is_ur else 0.42)
		_rarity_frame.add_theme_stylebox_override("panel", boosted)

	var pivot_size := _layer.size
	if pivot_size.x < 1.0 or pivot_size.y < 1.0:
		pivot_size = size
	_layer.pivot_offset = pivot_size * 0.5
	_layer.scale = Vector2.ONE

	_reveal_fx_tween = create_tween()
	_reveal_fx_tween.set_parallel(true)
	_reveal_fx_tween.tween_property(flash, "modulate:a", 0.0, REVEAL_FX_FLASH_SEC).set_ease(Tween.EASE_OUT)
	_reveal_fx_tween.tween_property(_layer, "scale", Vector2(pulse, pulse), REVEAL_FX_PULSE_SEC * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_fx_tween.chain()
	_reveal_fx_tween.set_parallel(false)
	_reveal_fx_tween.tween_property(_layer, "scale", Vector2.ONE, REVEAL_FX_PULSE_SEC * 0.6).set_ease(Tween.EASE_IN_OUT)
	_reveal_fx_tween.tween_callback(_on_rare_reveal_fx_finished)


## 연출 종료: 플래시 숨김 · 프레임 스타일 복원.
func _on_rare_reveal_fx_finished() -> void:
	if _reveal_flash:
		_reveal_flash.visible = false
		_reveal_flash.modulate = Color(1, 1, 1, 1)
	if _rarity_frame and _face_up and CardRarity.shows_frame(_rarity_tier):
		_rarity_frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(_rarity_tier, 2.0))
	_reset_layer_scale()


## 등급색 플래시 ColorRect를 Layer 위에 만든다.
func _ensure_reveal_flash() -> ColorRect:
	_bind_nodes()
	if _reveal_flash != null and is_instance_valid(_reveal_flash):
		return _reveal_flash
	_reveal_flash = ColorRect.new()
	_reveal_flash.name = "RevealFlash"
	_reveal_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_flash.z_index = 20
	_reveal_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_flash.visible = false
	if _layer:
		_layer.add_child(_reveal_flash)
	else:
		add_child(_reveal_flash)
	return _reveal_flash


## 진행 중 플립 트윈을 중단한다.
func _kill_flip_tween() -> void:
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip_tween = null
	_snap_chip_tilt_flat()


## SR+ 공개 연출 트윈을 중단한다.
func _kill_reveal_fx_tween() -> void:
	if _reveal_fx_tween != null and _reveal_fx_tween.is_valid():
		_reveal_fx_tween.kill()
	_reveal_fx_tween = null
	if _reveal_flash:
		_reveal_flash.visible = false


## 뒷면 힌트 펄스 트윈을 중단한다.
func _kill_back_glow_tween() -> void:
	if _back_glow_tween != null and _back_glow_tween.is_valid():
		_back_glow_tween.kill()
	_back_glow_tween = null
	if _rarity_frame:
		_rarity_frame.modulate = Color(1, 1, 1, 1)
	if _art:
		_art.modulate = Color(1, 1, 1, 1)


## Layer scale을 기본값으로 돌린다.
func _reset_layer_scale() -> void:
	_bind_nodes()
	if _layer == null:
		return
	_layer.scale = Vector2.ONE
	_layer.pivot_offset = _layer.size * 0.5


## 공유 흑백 ShaderMaterial.
static func _get_gray_material() -> ShaderMaterial:
	if _gray_material == null:
		var shader := Shader.new()
		shader.code = _GRAY_SHADER
		_gray_material = ShaderMaterial.new()
		_gray_material.shader = shader
	return _gray_material


## OnFieldPower와 비슷한 반투명 검정 배지 스타일.
static func _get_badge_style() -> StyleBoxFlat:
	if _badge_style == null:
		_badge_style = StyleBoxFlat.new()
		_badge_style.bg_color = Color(0, 0, 0, 0.75)
		_badge_style.content_margin_left = 2.0
		_badge_style.content_margin_right = 2.0
		_badge_style.content_margin_top = 0.0
		_badge_style.content_margin_bottom = 0.0
	return _badge_style
