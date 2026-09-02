class_name ScreenRmbBack
extends Node
## Screen 우클릭 → 뒤로가기. host에 붙여 on_back 호출.
## `_input` 사용 — Control이 이벤트를 가로채도 동작. LineEdit 등은 제외.
## should_ignore가 true면 스킵 (덱에디터 사이드바 표시 중 등).
## 열린 취소 가능 PopupShell이 있으면 스킵(팝업이 RMB 취소를 처리).

var on_back: Callable = Callable()
var should_ignore: Callable = Callable()


## host에 ScreenRmbBack 자식을 붙인다. 이미 있으면 콜백만 갱신.
static func install(host: Node, back: Callable, ignore: Callable = Callable()) -> void:
	if host == null or not back.is_valid():
		return
	var existing := host.get_node_or_null("ScreenRmbBack") as ScreenRmbBack
	if existing == null:
		existing = ScreenRmbBack.new()
		existing.name = "ScreenRmbBack"
		host.add_child(existing)
	existing.on_back = back
	existing.should_ignore = ignore


## 우클릭 뒤로가기. 팝업·텍스트 입력 위면 패스.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if should_ignore.is_valid() and bool(should_ignore.call()):
		return
	if _has_open_cancelable_popup():
		return
	if _should_skip_for_hovered():
		return
	if not on_back.is_valid():
		return
	get_viewport().set_input_as_handled()
	on_back.call()


## 씬에 RMB로 닫을 수 있는 PopupShell이 보이면 true.
func _has_open_cancelable_popup() -> bool:
	var scene := get_tree().current_scene if get_tree() else null
	if scene == null:
		return false
	return _find_cancelable_popup(scene)


## 노드 트리에서 취소 가능한 열린 PopupShell을 찾는다.
func _find_cancelable_popup(node: Node) -> bool:
	if node is PopupShell:
		var popup := node as PopupShell
		if popup.is_rmb_cancelable():
			return true
	for child in node.get_children():
		if _find_cancelable_popup(child):
			return true
	return false


## LineEdit/네이티브 Popup 위 우클릭은 기본 동작 유지.
func _should_skip_for_hovered() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if hovered is LineEdit or hovered is TextEdit or hovered is SpinBox:
		return true
	var n: Node = hovered
	while n:
		if n is PopupMenu or n is Popup:
			return true
		n = n.get_parent()
	return false
