extends Node2D
class_name CardSlot

@export var line: GameConstants.Line = GameConstants.Line.LEFT
@export var side: GameConstants.Side = GameConstants.Side.PLAYER

var card_in_slot: Node2D = null
var _candidate_overlay: Panel
var _chosen_overlay: Panel
var _in_slot_select_mode: bool = false


func is_empty() -> bool:
	return card_in_slot == null


func occupy(card: Node2D) -> void:
	card_in_slot = card
	card.card_slot_card_is_in = self


func release() -> void:
	if card_in_slot:
		card_in_slot.card_slot_card_is_in = null
	card_in_slot = null


func set_select_highlight(enabled: bool) -> void:
	set_slot_select_candidate(enabled)


func set_slot_select_candidate(enabled: bool) -> void:
	_in_slot_select_mode = enabled
	_ensure_slot_select_overlays()
	if _candidate_overlay == null or _chosen_overlay == null:
		return
	if not enabled:
		_candidate_overlay.visible = false
		_chosen_overlay.visible = false
		return
	_refresh_slot_select_overlays(false)


func set_slot_selection_chosen(chosen: bool) -> void:
	_ensure_slot_select_overlays()
	_refresh_slot_select_overlays(chosen)


func _ensure_slot_select_overlays() -> void:
	if _candidate_overlay and _chosen_overlay:
		_apply_slot_overlay_size(_candidate_overlay)
		_apply_slot_overlay_size(_chosen_overlay)
		return
	_candidate_overlay = get_node_or_null("CandidateOverlay") as Panel
	_chosen_overlay = get_node_or_null("ChosenOverlay") as Panel
	if _candidate_overlay == null:
		_candidate_overlay = _spawn_overlay_child("CandidateOverlay")
	if _chosen_overlay == null:
		_chosen_overlay = _spawn_overlay_child("ChosenOverlay")
	_candidate_overlay.add_theme_stylebox_override("panel", SelectionHighlight.make_candidate_stylebox())
	_chosen_overlay.add_theme_stylebox_override("panel", SelectionHighlight.make_chosen_stylebox())
	_apply_slot_overlay_size(_candidate_overlay)
	_apply_slot_overlay_size(_chosen_overlay)
	_chosen_overlay.visible = false


## 씬에 오버레이가 없을 때 런타임 폴백 (상대 슬롯 등 구 인스턴스 대비).
func _spawn_overlay_child(node_name: String) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 5
	add_child(panel)
	return panel


## CardSlotImage(카드 백) 표시 크기에 하이라이트 맞춤.
func _apply_slot_overlay_size(panel: Panel) -> void:
	if panel == null:
		return
	var img := get_node_or_null("CardSlotImage") as Sprite2D
	SelectionHighlight.configure_world_overlay(
		panel,
		SelectionHighlight.overlay_size_from_sprite(img)
	)


func _refresh_slot_select_overlays(chosen: bool) -> void:
	if _candidate_overlay == null or _chosen_overlay == null:
		return
	if not _in_slot_select_mode:
		_candidate_overlay.visible = false
		_chosen_overlay.visible = false
		return
	_chosen_overlay.visible = chosen
	_candidate_overlay.visible = not chosen
