class_name ActivationFx
extends RefCounted
## 효과 발동 시그니처 연출 진입점. MatchVfx(이동)와 분리.
## 필드: 실카드 scale 펄스 + 푸른 링.
## 존(TRASH/BIND·GRAVE/BANISH): 칩 0→1 → ActivationFx → 제거.
## Dedicated/headless no-op. 교체: set_presenter() · 수치 SSOT=ActivationFxDefault.


static var _presenter: RefCounted = null


## 연출 구현체를 교체한다. null이면 다음 play 때 Default로 되돌린다.
static func set_presenter(presenter: RefCounted) -> void:
	_presenter = presenter


## 현재 presenter. 없으면 ActivationFxDefault를 만든다.
static func get_presenter() -> RefCounted:
	if _presenter == null:
		_presenter = ActivationFxDefault.new()
	return _presenter


## headless·미표시면 연출 생략.
static func is_active() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return true


## 필드 소스면 true.
static func is_field_source(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if card.get("card_slot_card_is_in") != null:
		return true
	var zone: Variant = card.get("zone")
	if zone != null and int(zone) == int(EffectTypes.Location.FIELD):
		return true
	return false


## 트래시/바인드 존 소스면 true (zone 또는 trigger).
static func is_zone_peek_source(card: Node, trigger: String = "") -> bool:
	if trigger == "TRASH" or trigger == "BIND":
		return true
	if card == null or not is_instance_valid(card):
		return false
	var zone: Variant = card.get("zone")
	if zone == null:
		return false
	var z := int(zone)
	return z == int(EffectTypes.Location.GRAVE) or z == int(EffectTypes.Location.BANISH)


## confirm 직후용. trigger로 TRASH/BIND를 강제 인식한다.
static func await_play_for_source(card: Node, trigger: String = "") -> void:
	if not is_active():
		return
	if is_zone_peek_source(card, trigger):
		await await_zone_chip_peek(card, trigger)
		return
	if is_field_source(card):
		var node := card as Node2D
		if node != null:
			await await_play(node)
		return


## CanvasItem(카드 Node2D 또는 칩 Control)에 scale+링.
static func await_play(visual: CanvasItem) -> void:
	if not is_active():
		return
	if visual == null or not is_instance_valid(visual):
		return
	var presenter := get_presenter()
	if presenter == null or not presenter.has_method("await_play_on_visual"):
		return
	await presenter.await_play_on_visual(visual)


## 존 앵커에 칩 0→1 등장 → ActivationFx → 제거.
static func await_zone_chip_peek(card: Node, trigger: String = "") -> void:
	if not is_active():
		return
	if card == null or not is_instance_valid(card):
		return
	var parent := _resolve_chip_parent(card)
	if parent == null or not is_instance_valid(parent):
		return
	var at := zone_world_pos_for(card, trigger)
	var chip := _spawn_peek_chip(card, parent, at)
	if chip == null:
		return
	# Control 레이아웃·pivot 확정. 위치 보정(at - pivot)은 임시 비활성 — 좌상단=at.
	if chip.is_inside_tree():
		await chip.get_tree().process_frame
		if not is_instance_valid(chip):
			return
		chip.pivot_offset = chip.size * 0.5
		chip.global_position = at
	var presenter := get_presenter()
	if presenter != null and presenter.has_method("await_pop_in"):
		await presenter.await_pop_in(chip)
	elif is_instance_valid(chip):
		chip.scale = Vector2.ONE
	await await_play(chip)
	if is_instance_valid(chip):
		chip.queue_free()


## 월드 좌표에서 펄스만 재생.
static func await_play_at(at: Vector2, parent: Node = null, opts: Dictionary = {}) -> void:
	if not is_active():
		return
	var presenter := get_presenter()
	if presenter == null or not presenter.has_method("await_play_at"):
		return
	var host: Node = parent
	if host == null:
		host = _resolve_chip_parent(null)
	if host == null or not is_instance_valid(host):
		return
	await presenter.await_play_at(at, host, opts)


## Field 하위 조회용 앵커: 트리 안 카드 우선 · (유효) MatchVfxHost.
## Orphan Host를 from으로 쓰면 find_under_field가 항상 실패한다.
static func _lookup_from(card: Node) -> Node:
	if card != null and is_instance_valid(card) and card.is_inside_tree():
		return card
	var host := MatchVfx.get_host()
	if host != null and host.is_inside_tree():
		return host
	return null


## from에서 조상 Field를 찾는다.
static func _find_field(from: Node) -> Node:
	var n: Node = from
	while n:
		if str(n.name) == "Field":
			return n
		n = n.get_parent()
	return null


## 칩 부모: GameUILayer(CanvasLayer) 우선 · 트리 안 MatchVfxHost · 카드 부모.
static func _resolve_chip_parent(card: Node) -> Node:
	var from := _lookup_from(card)
	if from != null:
		var ui := FieldBoardBuilder.find_under_field(from, "GameUILayer")
		if ui != null:
			return ui
	var host := MatchVfx.get_host()
	if host != null and is_instance_valid(host) and host.is_inside_tree():
		return host
	# Host가 없거나 orphan이면 Field 아래 재바인딩.
	var field := _find_field(from) if from != null else null
	if field != null:
		FieldBoardBuilder.ensure_match_vfx_host(field)
		var ui2 := field.get_node_or_null("GameUILayer")
		if ui2 != null:
			return ui2
		host = MatchVfx.get_host()
		if host != null and host.is_inside_tree():
			return host
	if card != null and is_instance_valid(card) and card.is_inside_tree():
		return card.get_parent()
	return null


## 카드 zone·trigger·side로 묘지/바인드 앵커 월드 좌표.
static func zone_world_pos_for(card: Node, trigger: String = "") -> Vector2:
	if card == null or not is_instance_valid(card):
		return Vector2.ZERO
	var zone: Variant = card.get("zone")
	var side_v: Variant = card.get("owner_side")
	var side := int(side_v) if side_v != null else int(GameConstants.Side.PLAYER)
	var use_banish := (
		trigger == "BIND"
		or (zone != null and int(zone) == int(EffectTypes.Location.BANISH))
	)
	var use_grave := (
		not use_banish
		and (
			trigger == "TRASH"
			or trigger == "LIFE"
			or zone == null
			or int(zone) == int(EffectTypes.Location.GRAVE)
		)
	)
	var path := ""
	if use_banish:
		path = (
			"PlayerBanishZone"
			if side == int(GameConstants.Side.PLAYER)
			else "OpponentBanishZone"
		)
	elif use_grave:
		path = (
			"PlayerGraveyard"
			if side == int(GameConstants.Side.PLAYER)
			else "OpponentGraveyard"
		)
	else:
		return Vector2.ZERO
	var from := _lookup_from(card)
	if from == null:
		return Vector2.ZERO
	var node := FieldBoardBuilder.find_under_field(from, path) as Node2D
	if node != null:
		return node.global_position
	return Vector2.ZERO


## 존 peek용 앞면 칩을 앵커 중심에 둔다.
static func _spawn_peek_chip(card: Node, parent: Node, at: Vector2) -> DeckCardChip:
	var chip := DeckCardChip.instantiate_chip()
	if chip == null:
		return null
	var cname := String(card.get("card_name") if card.get("card_name") != null else "")
	var rarity := int(
		card.get("instance_rarity") if card.get("instance_rarity") != null else CardRarity.Tier.N
	)
	var chip_size := ActivationFxDefault.PEEK_CHIP_SIZE
	chip.setup(cname, false, -1, chip_size, rarity)
	chip.set_rarity_badge_visible(false)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.top_level = true
	chip.z_as_relative = false
	chip.z_index = 120
	parent.add_child(chip)
	chip.set_chip_size(chip_size)
	chip.pivot_offset = chip_size * 0.5
	chip.scale = Vector2.ZERO
	# 임시: 중심 보정 끄고 좌상단을 존 앵커(at)에 둠.
	chip.global_position = at
	return chip
