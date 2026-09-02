class_name SidebarContentUtil
extends RefCounted
## SidebarShell 안 콘텐츠용 공통 헬퍼 — 셸 탐색·open/close 동기화.
## CardInfo / MatchMenu / ZoneBrowse 가 복붙하던 _find/_sync 대체.


## 조상 중 SidebarShell(open/close/get_content_slot) 을 찾는다.
static func find_shell(from: Node) -> Control:
	var n: Node = from
	while n:
		if (
			n is Control
			and n.has_method("open")
			and n.has_method("close")
			and n.has_method("get_content_slot")
		):
			return n as Control
		n = n.get_parent()
	return null


## 콘텐츠 visible 과 부모 셸 open/close 를 맞춘다.
static func sync_shell(from: Node, open: bool) -> void:
	var shell := find_shell(from)
	if shell == null:
		return
	if open:
		if not shell.visible:
			shell.call("open")
	elif shell.visible:
		shell.call("close", "content")
