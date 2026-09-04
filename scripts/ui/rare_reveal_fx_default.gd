class_name RareRevealFxDefault
extends RefCounted
## 기본 D 연출: 등급 accent 플래시 + 스케일 펄스 + 프레임 글로우 버스트.
## 인게임 Node2D 카드용. 팩 칩은 DeckCardChip 쪽 로직 유지.


## card_flip 앞면 교체(CARD_FLIP_SWAP_SEC)에 맞춰 시작 — 종료까지 기다리면 한 박자 늦음.
const FLASH_SEC := 0.16
const PULSE_SEC := 0.12
const META_TWEEN := &"_rare_reveal_fx_tween"
const META_START := &"_rare_reveal_fx_start"
const META_FLASH := &"_rare_reveal_fx_flash"
const META_BASE_SCALE := &"_rare_reveal_fx_base_scale"
const FLASH_NAME := "RareRevealFlash"


## 앞면이 드러나는 시점에 D 연출. 애니 없거나 이미 지났으면 즉시.
func play_on_card(card: Node2D, tier: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	_kill_start(card)
	if CardHoverTilt.is_flipping(card):
		var delay: float = CardHoverTilt.flip_sec_until_swap(card)
		if delay > 0.001:
			var starter := card.create_tween()
			card.set_meta(META_START, starter)
			starter.tween_interval(delay)
			starter.tween_callback(func() -> void:
				if card.has_meta(META_START):
					card.remove_meta(META_START)
				if is_instance_valid(card):
					_play_d(card, tier)
			)
			return
	_play_d(card, tier)


## 플래시·펄스·글로우를 재생한다.
func _play_d(card: Node2D, tier: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	_kill_tween(card)
	var accent := CardRarity.accent_of(tier)
	var is_ur := tier >= CardRarity.Tier.UR
	var flash_a := 0.55 if is_ur else 0.38
	var glow_boost := 18 if is_ur else 14

	if card.has_method("refresh_rarity_visual"):
		card.refresh_rarity_visual()

	var frame := card.get_node_or_null("RarityFrame") as Panel
	if frame != null and frame.visible:
		var boosted := CardRarity.make_frame_style(tier, 3.5)
		boosted.shadow_size = glow_boost
		boosted.shadow_color = Color(accent.r, accent.g, accent.b, 0.55 if is_ur else 0.42)
		frame.add_theme_stylebox_override("panel", boosted)

	var flash := _ensure_flash(card)
	flash.color = Color(accent.r, accent.g, accent.b, flash_a)
	flash.visible = true
	flash.modulate = Color(1, 1, 1, 1)

	var pulse := 1.1 if is_ur else 1.06
	var base_scale := card.scale
	if base_scale.x < 0.01 or base_scale.y < 0.01:
		base_scale = Vector2.ONE
	card.set_meta(META_BASE_SCALE, base_scale)
	var tween := card.create_tween()
	card.set_meta(META_TWEEN, tween)
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, FLASH_SEC).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		card, "scale", base_scale * pulse, PULSE_SEC * 0.4
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain()
	tween.set_parallel(false)
	tween.tween_property(card, "scale", base_scale, PULSE_SEC * 0.6).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_finish.bind(card, tier))


## 연출 종료: 플래시 숨김 · 스케일·프레임 복원.
func _finish(card: Node2D, tier: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	var flash: Variant = card.get_meta(META_FLASH, null)
	if flash is CanvasItem and is_instance_valid(flash):
		(flash as CanvasItem).visible = false
		(flash as CanvasItem).modulate = Color(1, 1, 1, 1)
	if card.has_meta(META_BASE_SCALE):
		card.scale = card.get_meta(META_BASE_SCALE) as Vector2
		card.remove_meta(META_BASE_SCALE)
	if card.has_method("refresh_rarity_visual"):
		card.refresh_rarity_visual()
	elif CardRarity.shows_frame(tier):
		var frame := card.get_node_or_null("RarityFrame") as Panel
		if frame != null and frame.visible:
			frame.add_theme_stylebox_override("panel", CardRarity.make_frame_style(tier, 3.0))
	if card.has_meta(META_TWEEN):
		card.remove_meta(META_TWEEN)


## 카드 위에 등급색 플래시 ColorRect를 보장한다.
func _ensure_flash(card: Node2D) -> ColorRect:
	var existing: Variant = card.get_meta(META_FLASH, null)
	if existing is ColorRect and is_instance_valid(existing):
		return existing as ColorRect
	var named := card.get_node_or_null(FLASH_NAME) as ColorRect
	if named != null:
		card.set_meta(META_FLASH, named)
		return named
	var flash := ColorRect.new()
	flash.name = FLASH_NAME
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 20
	flash.position = Vector2(-79.0, -110.0)
	flash.size = Vector2(158.0, 220.0)
	flash.visible = false
	card.add_child(flash)
	card.set_meta(META_FLASH, flash)
	return flash


## 대기 중 시작 트윈을 끊는다.
func _kill_start(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	if card.has_meta(META_START):
		var s: Variant = card.get_meta(META_START)
		if s is Tween and (s as Tween).is_valid():
			(s as Tween).kill()
		card.remove_meta(META_START)


## 진행 중 트윈을 끊고 스케일을 되돌린다.
func _kill_tween(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	_kill_start(card)
	if card.has_meta(META_TWEEN):
		var t: Variant = card.get_meta(META_TWEEN)
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
		card.remove_meta(META_TWEEN)
	if card.has_meta(META_BASE_SCALE):
		card.scale = card.get_meta(META_BASE_SCALE) as Vector2
		card.remove_meta(META_BASE_SCALE)
	var flash: Variant = card.get_meta(META_FLASH, null)
	if flash is CanvasItem and is_instance_valid(flash):
		(flash as CanvasItem).visible = false
