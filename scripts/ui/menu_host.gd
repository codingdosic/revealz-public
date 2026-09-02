class_name MenuHost
extends Control
## 메뉴 화면 스택 호스트. 밀기(push/pop). 매치 로딩·game은 이 씬을 버린다.
## 전진: 새 화면이 오른쪽에서, 이전은 왼쪽. 후퇴: 반대. 이전 인스턴스 유지.
## 튜닝: UiShellConstants.SCREEN_SLIDE_SEC


const HOST_SCENE := "res://scenes/ui/shell/menu_host.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"

## 호스트 부팅 시 메인 위에 즉시 올릴 경로. 비면 메인만. 슬라이드 없음.
static var pending_boot_path: String = ""

var _stack: Array[Control] = []
var _busy: bool = false
var _block: ColorRect
var _tween: Tween


## 클립·입력 차단 레이어 · 메인(+pending) 즉시 마운트.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_block = ColorRect.new()
	_block.name = "InputBlock"
	_block.color = Color(0, 0, 0, 0)
	_block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block.z_index = 64
	add_child(_block)
	var extra := pending_boot_path
	pending_boot_path = ""
	_mount_root(MAIN_SCENE)
	if not extra.is_empty() and extra != MAIN_SCENE:
		_mount_on_top(extra)
	var fade_sec := SceneTransition.take_pending_fade_in()
	if fade_sec >= 0.0:
		await SceneTransition.fade_from_black(fade_sec)


## 뷰포트 크기 변경 시 페이지 폭을 맞춘다.
func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED:
		return
	var sz := _page_size()
	for page in _stack:
		if is_instance_valid(page):
			page.size = sz


## 현재 씬이 MenuHost면 그것을 반환한다.
static func from_tree(tree: SceneTree = null) -> MenuHost:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene as MenuHost


## 호스트가 있으면 밀고, 없으면 path로 씬 교체 (매치 중 폴백).
static func push_file(path: String) -> void:
	if path.is_empty():
		return
	var host := from_tree()
	if host:
		host.push(path)
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.change_scene_to_file(path)


## 호스트 스택이면 pop. 호스트가 없을 때만 fallback 씬 교체.
static func pop_or_file(fallback_path: String = MAIN_SCENE) -> void:
	var host := from_tree()
	if host:
		if host.can_pop():
			host.pop()
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var path := fallback_path if not fallback_path.is_empty() else MAIN_SCENE
	tree.change_scene_to_file(path)


## 매치 종료 등 — 호스트를 새로 연다. extra_path면 메인 위에 즉시 올린다.
static func open_root(tree: SceneTree, extra_path: String = "") -> void:
	pending_boot_path = extra_path
	if tree:
		tree.change_scene_to_file(HOST_SCENE)


## 스택에 이전 화면이 있고 전환 중이 아니면 true.
func can_pop() -> bool:
	return _stack.size() > 1 and not _busy


## path 화면을 오른쪽에 올려 민다. 진행 중이면 무시.
func push(path: String) -> void:
	if path.is_empty() or _busy:
		return
	var page := _make_page(path)
	if page == null:
		return
	_busy = true
	var width := _page_size().x
	page.position.x = width
	add_child(page)
	_raise_block()
	var outgoing := _top()
	_stack.append(page)
	if _skip_anim() or outgoing == null:
		page.position.x = 0.0
		_rest_page(outgoing)
		_busy = false
		return
	await _animate_slide(outgoing, page, -width, 0.0)
	_rest_page(outgoing)


## 최상단을 오른쪽으로 밀고 이전 화면을 살린다.
func pop() -> void:
	if not can_pop():
		return
	_busy = true
	var outgoing := _stack[_stack.size() - 1]
	var incoming := _stack[_stack.size() - 2]
	var width := _page_size().x
	_wake_page(incoming)
	incoming.position.x = -width
	if _skip_anim():
		incoming.position.x = 0.0
		_finish_pop(outgoing)
		_busy = false
		return
	await _animate_slide(outgoing, incoming, width, 0.0)
	_finish_pop(outgoing)


## 메인만 스택에 올린다 (부팅, 슬라이드 없음).
func _mount_root(path: String) -> void:
	var page := _make_page(path)
	if page == null:
		return
	page.position.x = 0.0
	add_child(page)
	_raise_block()
	_stack.append(page)


## 부팅 extra — 이전 페이지는 숨기고 위에 즉시 올린다.
func _mount_on_top(path: String) -> void:
	var page := _make_page(path)
	if page == null:
		return
	page.position.x = 0.0
	add_child(page)
	_raise_block()
	_rest_page(_top())
	_stack.append(page)


## path를 뷰포트 크기 페이지로 인스턴스한다.
func _make_page(path: String) -> Control:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var screen := packed.instantiate() as Control
	if screen == null:
		return null
	var page := Control.new()
	page.name = path.get_file().get_basename()
	page.set_anchors_preset(Control.PRESET_TOP_LEFT)
	page.size = _page_size()
	page.clip_contents = true
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(screen)
	return page


## outgoing을 out_x, incoming을 in_x로 보간한다. 호출 측이 이미 _busy.
func _animate_slide(outgoing: Control, incoming: Control, out_x: float, in_x: float) -> void:
	_set_block(true)
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var sec := UiShellConstants.SCREEN_SLIDE_SEC
	if outgoing != null and is_instance_valid(outgoing):
		_tween.tween_property(outgoing, "position:x", out_x, sec).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_IN_OUT)
	if incoming != null and is_instance_valid(incoming):
		_tween.tween_property(incoming, "position:x", in_x, sec).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	_set_block(false)
	_busy = false


## pop 후 나간 페이지를 제거한다.
func _finish_pop(outgoing: Control) -> void:
	if _stack.is_empty():
		return
	_stack.pop_back()
	if outgoing != null and is_instance_valid(outgoing):
		outgoing.queue_free()


## 스택에 남겨 두고 입력·처리를 끈다.
func _rest_page(page: Control) -> void:
	if page == null or not is_instance_valid(page):
		return
	page.visible = false
	page.process_mode = Node.PROCESS_MODE_DISABLED


## 숨겼던 페이지를 켜고 on_menu_shown이 있으면 호출한다.
func _wake_page(page: Control) -> void:
	if page == null or not is_instance_valid(page):
		return
	page.process_mode = Node.PROCESS_MODE_INHERIT
	page.visible = true
	if page.get_child_count() <= 0:
		return
	var screen := page.get_child(0)
	if screen.has_method("on_menu_shown"):
		screen.call("on_menu_shown")


## 스택 최상단. 비면 null.
func _top() -> Control:
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1]


## 입력 차단 레이어를 맨 앞으로.
func _raise_block() -> void:
	if _block != null and is_instance_valid(_block):
		move_child(_block, get_child_count() - 1)


## 전환 중 클릭을 막는다.
func _set_block(on: bool) -> void:
	if _block == null:
		return
	_block.mouse_filter = (
		Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	)


## headless면 트윈 생략.
func _skip_anim() -> bool:
	return DisplayServer.get_name() == "headless"


## 호스트(뷰포트) 크기.
func _page_size() -> Vector2:
	var sz := size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = get_viewport_rect().size
	return sz
