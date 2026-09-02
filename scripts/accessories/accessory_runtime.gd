class_name AccessoryRuntime
extends RefCounted
## 카탈로그 id → 인게임/UI 텍스처 · 카드 뒷면·필드 보드 적용.


const FALLBACK_CARD_BACK := preload("res://assets_lite/accessories/card_back/card_back_default.png")
const _FIELD_MESH_META := &"_field_accessory_id"

static var _scene_cache: Dictionary = {}


static func texture_for_id(accessory_id: String) -> Texture2D:
	var id := AccessoryCatalog.migrate_accessory_id(accessory_id.strip_edges())
	if id.is_empty():
		return null
	var tex := AccessoryCatalog.preview_for_id(id)
	return tex if tex != null else null


static func card_back_texture(accessory_id: String) -> Texture2D:
	var tex := texture_for_id(accessory_id)
	return tex if tex != null else FALLBACK_CARD_BACK


static func apply_card_back(card: Node, accessory_id: String) -> void:
	if card == null:
		return
	var back := card.get_node_or_null("CardBackImage") as Sprite2D
	if back == null:
		return
	back.texture = card_back_texture(accessory_id)


static func card_back_id_for_owner_side(side: GameConstants.Side) -> String:
	var session := GameSession.get_active()
	if session == null:
		return AccessoryCatalog.DEFAULT_CARD_BACK_ID
	return session.card_back_id_for_owner_side(side)


static func field_id_for_owner_side(side: GameConstants.Side) -> String:
	var session := GameSession.get_active()
	if session == null:
		return AccessoryCatalog.DEFAULT_FIELD_ID
	return session.field_id_for_owner_side(side)


## Field 노드 아래 SubViewport 앵커에 side별 field 악세서리 GLB를 적용한다.
static func apply_field_boards(field: Node) -> void:
	if field == null or not is_instance_valid(field):
		return
	_apply_field_mesh(
		field,
		FieldBoardLayout.BOARD_3D_PLAYER_MESH_PATH,
		field_id_for_owner_side(GameConstants.Side.PLAYER)
	)
	_apply_field_mesh(
		field,
		FieldBoardLayout.BOARD_3D_OPPONENT_MESH_PATH,
		field_id_for_owner_side(GameConstants.Side.OPPONENT)
	)


static func _apply_field_mesh(field: Node, anchor_path: String, accessory_id: String) -> void:
	var anchor := field.get_node_or_null(anchor_path) as Node3D
	if anchor == null:
		return
	var resolved_id := AccessoryCatalog.resolve_field_id(accessory_id)
	if anchor.has_meta(_FIELD_MESH_META) and String(anchor.get_meta(_FIELD_MESH_META)) == resolved_id:
		return
	var scene_path := AccessoryCatalog.scene_path_for_id(resolved_id)
	var packed := _load_scene(scene_path)
	if packed == null:
		push_warning("[AccessoryRuntime] missing field scene: %s (id=%s)" % [scene_path, resolved_id])
		return
	for child in anchor.get_children():
		anchor.remove_child(child)
		child.free()
	var mesh := packed.instantiate()
	anchor.add_child(mesh)
	anchor.set_meta(_FIELD_MESH_META, resolved_id)


static func _load_scene(path: String) -> PackedScene:
	var p := path.strip_edges()
	if p.is_empty():
		return null
	if _scene_cache.has(p):
		return _scene_cache[p] as PackedScene
	if not ResourceLoader.exists(p):
		return null
	var packed := load(p) as PackedScene
	if packed != null:
		_scene_cache[p] = packed
	return packed
