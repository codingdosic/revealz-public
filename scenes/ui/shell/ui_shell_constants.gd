class_name UiShellConstants
extends RefCounted
## L4a UI 셸 공통 튜닝 상수.
## 폭·여백·레이어 숫자 SSOT. 색은 UiChromeStyle, 문구는 UiCopy.

# --- 사이드바 ---
## 표시 스케일(기본 230 대비). 폭·카드 일러 크기와 맞출 것.
const SIDEBAR_SCALE := 0.92
## 좌/우 사이드바 표시 폭 (= 230 × SIDEBAR_SCALE). card_info / match_menu / zone_browse / deck_editor 동기화.
const SIDEBAR_WIDTH := 212.0
## SettingsButton(≈ top 8~40) 아래로 비움 — 사이드바가 버튼을 가리지 않음.
const SIDEBAR_TOP_INSET := 48.0
## 하단 여백(살짝 축소 체감).
const SIDEBAR_BOTTOM_INSET := 8.0
## CardInfo 사이드바 일러 기준 크기 (기존 180×250 × SIDEBAR_SCALE).
const SIDEBAR_CARD_IMAGE_SIZE := Vector2(166, 230)
## CardInfo DetailRoot 일러 (사이드바×2, 줌 415×575보다 작음).
const DETAIL_CARD_IMAGE_SIZE := Vector2(332, 460)

# --- 하단 선택 바 / 필드 프롬프트 (BottomSheetShell) ---
## TargetListSheet·FieldTargetPrompt 좌우 여백.
const BOTTOM_BAR_SIDE_MARGIN := 350.0
## FIELD 모드 기본 높이.
const FIELD_PROMPT_HEIGHT := 72.0
## FIELD 모드 상·하단 화면 가장자리 여백 (앵커 offset).
const FIELD_PROMPT_EDGE_MARGIN := 20.0
## LIST 모드 셸 높이(앵커 offset). tscn offset은 _apply_bottom_layout이 덮어씀 — 여기만 바꿀 것.
## TitleRow+마진+셀이 들어가도록 여유. 크롬 버튼 패딩 반영해 소폭 상향.
const TARGET_BAR_HEIGHT := 184.0

# --- 최소화 핸들 ---
## 플레이어 덱(≈970,485) 왼쪽. 배치권(888,485)·덱과 안 겹치게.
const MINIMIZE_HANDLE_OFFSET_LEFT := 800.0
const MINIMIZE_HANDLE_OFFSET_TOP := 530.0
const MINIMIZE_HANDLE_SIZE := Vector2(80, 30)
## CanvasLayer/Control z. game_ui_layer 복귀 버튼과 맞춤.
const MINIMIZE_HANDLE_Z := 200

# --- 팝업 ---
## 확인형 팝업 반폭/반높이(중앙 기준).
const POPUP_CONFIRM_HALF := Vector2(180, 90)
## 알림형 상단 오프셋.
const POPUP_NOTICE_TOP := 8.0
const POPUP_NOTICE_HALF_WIDTH := 180.0
## 열림/닫힘 아래→위 슬라이드. 패널(Builtin/ContentSlot)만 이동.
const POPUP_SLIDE_PX := 40.0
const POPUP_SLIDE_IN_SEC := 0.18
const POPUP_SLIDE_OUT_SEC := 0.14
## 사이드바 좌/우 슬라이드.
const SIDEBAR_SLIDE_IN_SEC := 0.2
const SIDEBAR_SLIDE_OUT_SEC := 0.16
## 바텀시트·필드 프롬프트 상/하 슬라이드.
const SHEET_SLIDE_IN_SEC := 0.2
const SHEET_SLIDE_OUT_SEC := 0.16
## 페이즈 토스트 가로 횡단.
const TOAST_SLIDE_SEC := 0.32
## 메뉴 화면 밀기 (MenuHost). 매치 로딩은 사용하지 않음.
const SCREEN_SLIDE_SEC := 0.24

# --- 닫기 정책 기본값 (UI별 오버라이드) ---
## true면 우클릭으로 dismiss_requested.
const DEFAULT_DISMISS_ON_RIGHT_CLICK := true
## true면 ESC로 dismiss_requested.
const DEFAULT_DISMISS_ON_ESC := true
## true면 패널 바깥 좌클릭으로 dismiss. 사이드바는 보통 true, 모달은 false 권장.
const DEFAULT_DISMISS_ON_OUTSIDE_CLICK := false

# --- 배치권(마나) 표시 PlacementPermissionDisplay ---
## 컨테이너 배경.
const PERMISSION_BG := Color(0.06, 0.06, 0.09, 0.88)
## 컨테이너 테두리.
const PERMISSION_BORDER := Color(0.32, 0.32, 0.38, 1.0)
## 빈 슬롯(미보유).
const PERMISSION_EMPTY := Color(0.42, 0.42, 0.46, 1.0)
## 보유 배치권(사용 가능).
const PERMISSION_FILLED := Color(0.22, 0.871, 0.949, 1.0)
## pending 예약(필드에 올린 코스트, 확정 전).
const PERMISSION_RESERVED := Color(0.029, 0.336, 0.371, 1.0)

# --- Screen 뒤로가기 ---
## 좌상단 Back 버튼 한 변(px).
const SCREEN_BACK_SIZE := 40.0
## 화면 좌상단 여백.
const SCREEN_BACK_MARGIN := 12.0
## Back 기호 (이미지 없을 때).
const SCREEN_BACK_SYMBOL := "←"
