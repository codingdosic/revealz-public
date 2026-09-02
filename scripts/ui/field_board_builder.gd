class_name FieldBoardBuilder
extends RefCounted
## 정적 PlayerBoard/OpponentBoard · Board3DViewports(tscn 전체 SubViewport×1) 전제.
## PhaseButton → GameUILayer + 단색 스킨 + L|C|R + Board3D on/off.
## LineSeparators·ZoneSkins는 game.tscn 정적 자식 — Builder는 표시/단색만 적용.


const _META := &"_field_skins_applied"


## PhaseButton·단색 스킨·라인·존 패드·Board3D 토글. 멱등. 슬롯 이동 없음.
static func build(field: Node) -> void:
	if field == null or not is_instance_valid(field):
		return
	_move_phase_button_to_ui(field)
	_ensure_match_vfx_host(field)
	if field.has_meta(_META):
		return
	_apply_solid_sprite(
		field.get_node_or_null("FieldBackdrop") as Sprite2D,
		FieldBoardLayout.FIELD_BG_CENTER,
		FieldBoardLayout.FIELD_BG_SIZE,
		FieldBoardLayout.FIELD_BG_COLOR
	)
	var use_board_3d := (
		FieldBoardLayout.BOARD_3D_VIEWPORTS_ENABLED
		and DisplayServer.get_name() != "headless"
	)
	_apply_board_3d_mode(field, use_board_3d)
	if not use_board_3d:
		_apply_2d_fallback_skins(field)
	else:
		# 3D 모드: 색 패드·슬롯 이미지·존 플레이스홀더만 숨김 (카드·히트는 유지).
		_hide_2d_board_chrome(field)
	AccessoryRuntime.apply_field_boards(field)
	field.set_meta(_META, true)


## 2D 폴백: BoardSkin·LineSeparators·ZoneSkins 표시 + 단색 텍스처.
static func _apply_2d_fallback_skins(field: Node) -> void:
	_apply_solid_sprite(
		field.get_node_or_null("PlayerBoard/BoardSkin") as Sprite2D,
		FieldBoardLayout.PLAYER_SKIN_CENTER,
		FieldBoardLayout.BOARD_SKIN_SIZE,
		FieldBoardLayout.PLAYER_SKIN_COLOR
	)
	_apply_solid_sprite(
		field.get_node_or_null("OpponentBoard/BoardSkin") as Sprite2D,
		FieldBoardLayout.OPPONENT_SKIN_CENTER,
		FieldBoardLayout.BOARD_SKIN_SIZE,
		FieldBoardLayout.OPPONENT_SKIN_COLOR
	)
	_show_board_chrome(field.get_node_or_null("PlayerBoard") as Node2D)
	_show_board_chrome(field.get_node_or_null("OpponentBoard") as Node2D)
	_paint_zone_skins(
		field.get_node_or_null("PlayerBoard/ZoneSkins") as Node2D,
		FieldBoardLayout.PLAYER_SKIN_COLOR,
		[
			{"node": "PlayerDeckSkin", "size": FieldBoardLayout.ZONE_CARD_SKIN_SIZE},
			{"node": "PlayerGraveyardSkin", "size": FieldBoardLayout.ZONE_CARD_SKIN_SIZE},
			{"node": "PlayerBanishZoneSkin", "size": FieldBoardLayout.ZONE_CARD_SKIN_SIZE},
			{"node": "PlayerLifeContainerSkin", "size": FieldBoardLayout.ZONE_LIFE_SKIN_SIZE},
		]
	)
	_paint_zone_skins(
		field.get_node_or_null("OpponentBoard/ZoneSkins") as Node2D,
		FieldBoardLayout.OPPONENT_SKIN_COLOR,
		[
			{"node": "OpponentDeckSkin", "size": FieldBoardLayout.ZONE_CARD_SKIN_SIZE},
			{"node": "OpponentGraveyardSkin", "size": FieldBoardLayout.ZONE_CARD_SKIN_SIZE},
			{"node": "OpponentBanishZoneSkin", "size": FieldBoardLayout.ZONE_CARD_SKIN_SIZE},
			{"node": "OpponentLifeContainerSkin", "size": FieldBoardLayout.ZONE_LIFE_SKIN_SIZE},
		]
	)


## LineSeparators·ZoneSkins 표시 (위치는 tscn).
static func _show_board_chrome(board: Node2D) -> void:
	if board == null:
		return
	var lines := board.get_node_or_null("LineSeparators") as CanvasItem
	if lines:
		lines.visible = true
	var zones := board.get_node_or_null("ZoneSkins") as CanvasItem
	if zones:
		zones.visible = true


## ZoneSkins 아래 정적 Sprite에 단색 텍스처·스케일을 입힌다 (위치는 tscn 유지).
static func _paint_zone_skins(root: Node2D, color: Color, specs: Array) -> void:
	if root == null:
		return
	for spec in specs:
		var pad := root.get_node_or_null(String(spec.node)) as Sprite2D
		if pad == null:
			continue
		_apply_solid_sprite(pad, pad.position, spec.size as Vector2, color)


## Field 직속 또는 PlayerBoard/OpponentBoard 아래 이름 경로.
static func find_under_field(from: Node, field_child_path: String) -> Node:
	var field := _find_field(from)
	if field == null:
		return null
	var direct := field.get_node_or_null(field_child_path)
	if direct:
		return direct
	var player := field.get_node_or_null("PlayerBoard/" + field_child_path)
	if player:
		return player
	return field.get_node_or_null("OpponentBoard/" + field_child_path)


## MatchVfxHost를 Field 아래 두고 바인딩한다. 멱등. (ActivationFx·MatchVfx 재바인딩용)
static func ensure_match_vfx_host(field: Node) -> MatchVfxHost:
	if field == null or not is_instance_valid(field):
		return null
	var existing := field.get_node_or_null("MatchVfxHost") as MatchVfxHost
	if existing == null:
		# 이전 세션/리로드로 orphan된 Host가 있으면 재사용.
		var bound := MatchVfx.get_host()
		if bound != null and is_instance_valid(bound) and not bound.is_inside_tree():
			existing = bound
			if existing.get_parent() != null:
				existing.get_parent().remove_child(existing)
			existing.name = "MatchVfxHost"
			field.add_child(existing)
		else:
			existing = MatchVfxHost.new()
			existing.name = "MatchVfxHost"
			field.add_child(existing)
	elif not existing.is_inside_tree():
		if existing.get_parent() != null:
			existing.get_parent().remove_child(existing)
		field.add_child(existing)
	MatchVfx.bind(existing)
	return existing


## MatchVfxHost를 Field 아래 두고 바인딩한다. 멱등.
static func _ensure_match_vfx_host(field: Node) -> void:
	ensure_match_vfx_host(field)


## tscn Board3DViewports 표시 · BoardSkin은 반대로. 노드 생성 없음.
static func _apply_board_3d_mode(field: Node, enabled: bool) -> void:
	var board3d := field.get_node_or_null("Board3DViewports") as CanvasItem
	if board3d:
		board3d.visible = enabled
	_set_board_skin_visible(field, not enabled)
	# 보드·슬롯 루트는 켜 둠 (카드/Area2D). 숨김은 이미지·패드만.
	for path in ["PlayerBoard", "OpponentBoard", "PlayerBoard/CardSlots", "OpponentBoard/CardSlots"]:
		var n := field.get_node_or_null(path) as CanvasItem
		if n:
			n.visible = true


## Board3D 모드용: ZoneSkins·라인·슬롯이미지·존 플레이스홀더 Sprite만 숨김.
## 덱/라이프 카드 노드·슬롯 Area2D·보드 루트는 유지.
static func _hide_2d_board_chrome(field: Node) -> void:
	for board_name in ["PlayerBoard", "OpponentBoard"]:
		var board := field.get_node_or_null(board_name) as Node2D
		if board == null:
			continue
		var zone_skins := board.get_node_or_null("ZoneSkins") as CanvasItem
		if zone_skins:
			zone_skins.visible = false
		var lines := board.get_node_or_null("LineSeparators") as CanvasItem
		if lines:
			lines.visible = false
		_hide_named_sprites_under(board.get_node_or_null("CardSlots"), "CardSlotImage")
		# 묘지·제외 플레이스홀더만 숨김. 덱 Sprite2D·라이프 카드는 유지.
		for zone_path in ["PlayerGraveyard", "OpponentGraveyard", "PlayerBanishZone", "OpponentBanishZone"]:
			var zone := board.get_node_or_null(zone_path)
			if zone == null:
				continue
			var spr := zone.get_node_or_null("Sprite2D") as CanvasItem
			if spr:
				spr.visible = false


## root 아래 이름 name인 CanvasItem을 모두 숨긴다 (재귀).
static func _hide_named_sprites_under(root: Node, node_name: String) -> void:
	if root == null:
		return
	if root.name == node_name and root is CanvasItem:
		(root as CanvasItem).visible = false
	for child in root.get_children():
		_hide_named_sprites_under(child, node_name)


## Player/Opponent BoardSkin visible 토글 (보드 노드·슬롯은 유지).
static func _set_board_skin_visible(field: Node, visible: bool) -> void:
	for path in ["PlayerBoard/BoardSkin", "OpponentBoard/BoardSkin"]:
		var skin := field.get_node_or_null(path) as CanvasItem
		if skin:
			skin.visible = visible


## PhaseButton을 GameUILayer로 옮긴다. 위치·크기는 씬(또는 현재 offset)을 유지한다.
static func _move_phase_button_to_ui(field: Node) -> void:
	var button := field.get_node_or_null("PhaseButton") as Button
	var ui := field.get_node_or_null("GameUILayer") as CanvasLayer
	if button == null or ui == null:
		return
	var left := button.offset_left
	var top := button.offset_top
	var w := button.offset_right - button.offset_left
	var h := button.offset_bottom - button.offset_top
	if w < 1.0:
		w = FieldBoardLayout.PHASE_BUTTON_SIZE.x
	if h < 1.0:
		h = FieldBoardLayout.PHASE_BUTTON_SIZE.y
	if button.get_parent() != ui:
		button.reparent(ui)
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.offset_left = left
	button.offset_top = top
	button.offset_right = left + w
	button.offset_bottom = top + h
	button.custom_minimum_size = Vector2(w, h)
	button.z_index = 50
	# reparent 직후 크롬 — finish_setup 전에 기본 Godot 스킨이 보이지 않게.
	var chrome_res: UiChromeStyle = null
	if ui.get("chrome_style") != null:
		chrome_res = ui.chrome_style as UiChromeStyle
	UiChromeStyle.resolve(chrome_res).apply_phase_button(button)


## 1×1 단색 텍스처를 스프라이트에 올려 size만큼 스케일한다. position은 인자 값 유지.
static func _apply_solid_sprite(sprite: Sprite2D, center: Vector2, size: Vector2, color: Color) -> void:
	if sprite == null:
		return
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(color)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = true
	sprite.position = center
	sprite.scale = size


## from에서 상위로 Field 노드를 찾는다.
static func _find_field(from: Node) -> Node:
	var n := from
	while n:
		if n.name == "Field":
			return n
		n = n.get_parent()
	return null
