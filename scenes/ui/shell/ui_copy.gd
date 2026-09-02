class_name UiCopy
extends Resource
## UI 버튼·라벨·툴팁 문구. 인스펙터에서 고치고, null/빈 문자열이면 코드 기본값.
## 기본 리소스: ui_copy_ko.tres. 동적 상태 메시지(로비 오류 등)는 여기 두지 않음.

const DEFAULT_PATH := "res://scenes/ui/shell/ui_copy_ko.tres"

@export_group("Navigation")
## Screen 좌상단 Back 툴팁.
@export var back_tooltip: String = "뒤로"
## 임베드 설정(인게임 오버레이) 닫기 툴팁.
@export var close_tooltip: String = "닫기"

@export_group("Common buttons")
@export var confirm: String = "확인"
@export var cancel: String = "취소"
@export var yes: String = "예"
@export var no: String = "아니오"
@export var restore: String = "복귀"
@export var close: String = "닫기"

@export_group("Match menu")
@export var match_menu_title: String = "메뉴"
@export var match_menu_settings: String = "설정"
@export var match_menu_restart: String = "재시작"
@export var match_menu_surrender: String = "항복"
@export var surrender_title: String = "항복"
@export var surrender_message: String = "항복하시겠습니까?"

@export_group("Card info")
## 색 라벨 접두 ("COLOR: BLACK").
@export var card_color_prefix: String = "COLOR: "
## 레어도 라벨 접두 ("RARITY: SR").
@export var card_rarity_prefix: String = "RARITY: "
## 속도 라벨 포맷 ("%d" 자리 하나).
@export var card_spd_format: String = "SPD: %d"

@export_group("Zone / Notice")
@export var zone_empty: String = "(비어 있음)"
@export var effect_notice_title: String = "상대 효과 처리 중"


## 기본 한국어 .tres 로드. 실패 시 인메모리 기본값.
static func load_default() -> UiCopy:
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded := load(DEFAULT_PATH)
		if loaded is UiCopy:
			return loaded as UiCopy
	return UiCopy.new()


## null 이면 기본 카피 반환.
static func resolve(copy: UiCopy) -> UiCopy:
	if copy != null:
		return copy
	return load_default()


## 빈 문자열이면 fallback, 아니면 value.
static func pick(value: String, fallback: String) -> String:
	if value.is_empty():
		return fallback
	return value
