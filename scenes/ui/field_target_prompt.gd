extends BottomSheetShell
## 필드/슬롯 대상 선택 프롬프트 — BottomSheetShell FIELD 모드 파사드.
## L4a: 타겟 선택 계열. 최소화 → MinimizeHandle.
## 배경·버튼 룩: UiChromeStyle.sheet_* (BottomSheetShell.apply_chrome).
##
## 튜닝: UiShellConstants.BOTTOM_BAR_SIDE_MARGIN / FIELD_PROMPT_HEIGHT / FIELD_PROMPT_EDGE_MARGIN

## selection_confirmed / minimized 는 BottomSheetShell 시그널 재사용.


## FIELD 모드로 프롬프트를 연다.
func show_prompt(title_text: String, message_text: String, needed: int, anchor_top: bool = false) -> void:
	open_field(title_text, message_text, needed, anchor_top)


## 프롬프트를 닫는다.
func hide_prompt() -> void:
	hide_sheet()


## 프롬프트를 최소화한다.
func minimize_prompt() -> void:
	minimize_sheet()


## 최소화된 프롬프트를 복원한다.
func restore_prompt() -> void:
	restore_sheet()


## 호환: 기존 API명. min_count 미사용(필드 선택은 needed 고정).
func update_selection_count(selected: int, needed: int, _min_count: int = -1) -> void:
	super.update_selection_count(selected, needed)
