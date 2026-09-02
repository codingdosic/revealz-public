class_name CardInfoMount
extends RefCounted
## CardInfo 사이드바 마운트 헬퍼.
## 게임=tscn Overlay(SidebarShell) · 덱편집=LeftPane Embedded — 내용은 동일 CardInfo.
## 배경·테두리는 CardInfo(내용)만. 셸은 위치·열기/닫기만.

const CARD_INFO_SCENE := preload("res://scenes/ui/card_info_sidebar.tscn")
const SIDEBAR_SHELL_SCENE := preload("res://scenes/ui/shell/sidebar_shell.tscn")


## 부모에 embedded SidebarShell + CardInfo 를 붙인다.
## 반환: { "shell": SidebarShell, "content": Control }
static func mount_embedded(
	host: Control,
	chrome: UiChromeStyle = null,
	width: float = -1.0
) -> Dictionary:
	var w := width if width > 0.0 else UiShellConstants.SIDEBAR_WIDTH
	var shell: SidebarShell = SIDEBAR_SHELL_SCENE.instantiate() as SidebarShell
	shell.setup_embedded(w)
	shell.dismiss_on_outside_click = true
	shell.dismiss_on_right_click = true
	shell.dismiss_on_esc = true
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(shell)
	var content: Control = CARD_INFO_SCENE.instantiate() as Control
	shell.set_content(content)
	if content.has_method("apply_chrome"):
		content.call("apply_chrome", UiChromeStyle.resolve(chrome))
	return {"shell": shell, "content": content}
