class_name NavToggleButton
extends Button
## 상점/설정 등 동적 탭·소분류용 토글 버튼 프리팹.
## 개수는 코드에서 붙이고, 최소 크기·여백·폰트는 이 씬에서 조정한다.


## 라벨·ButtonGroup·가로 확장 여부를 설정한다.
func configure(
	label: String,
	group: ButtonGroup = null,
	expand_fill: bool = false
) -> void:
	text = label
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	if group != null:
		button_group = group
	if expand_fill:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		size_flags_horizontal = Control.SIZE_FILL


## UiChromeStyle 컴팩트 버튼 룩을 입힌다.
func apply_chrome(style: UiChromeStyle) -> void:
	if style == null:
		return
	style.apply_button_compact(self)
