class_name FieldBoardLayout
extends RefCounted
## 필드 보드 레이아웃 SSOT. 그룹은 game.tscn 정적 PlayerBoard/OpponentBoard.
## 단색 임시 스킨(FieldBackdrop / BoardSkin) + L|C|R 분리선.
## FX-3a: Board3D는 game.tscn 정적 SubViewport 1개(전체). Builder는 on/off·단색 폴백만.

# --- Field 전체 바탕 ---
const FIELD_BG_CENTER := Vector2(576, 324)
const FIELD_BG_SIZE := Vector2(1152, 648)
const FIELD_BG_COLOR := Color(0.292, 0.326, 0.427, 1.0)

# --- 진영 보드 스킨 (2D 폴백) ---
## Player 슬롯 밴드 세로 중점 (= BOARD_BAND_MID_Y).
const PLAYER_SKIN_CENTER := Vector2(576, 438)
const OPPONENT_SKIN_CENTER := Vector2(576, 210)
const BOARD_SKIN_SIZE := Vector2(820, 230)
const PLAYER_SKIN_COLOR := Color(0.348, 0.467, 0.591, 1.0)
const OPPONENT_SKIN_COLOR := Color(0.406, 0.343, 0.502, 1.0)

# --- PlayerBoard 슬롯·존 배치 SSOT (Opponent = 화면 중심 기준 180° 대칭) ---
## 라인 내 슬롯 가로 피치 (72→76). 상하 행 간격에도 동일 +4.
const SLOT_PITCH_X := 76.0
const SLOT_ROW_GAP := 94.0  # 구 90
## 라인(L/C/R) 중점 간격. 피치↑에 맞춰 라인 간 간격 유지.
const LINE_MID_SPACING := 236.0
## 보드 간 파워 라벨 통로용으로 밴드 중점을 화면 중앙에서 조금 더 바깥으로.
const BOARD_BAND_MID_Y := 438.0
const SLOT_Y_TOP := BOARD_BAND_MID_Y - SLOT_ROW_GAP * 0.5  # 391
const SLOT_Y_BOT := BOARD_BAND_MID_Y + SLOT_ROW_GAP * 0.5  # 485
const CENTER_LINE_MID_X := 576.0
const FIELD_SIZE := Vector2(1152.0, 648.0)
## 우측 존 열 / 라이프 (에디터 미세 조정값 · Opponent는 180° 대칭).
const PLAYER_ZONE_COL_X := 970.0
const PLAYER_LIFE_POS := Vector2(167.0, BOARD_BAND_MID_Y)
const PLAYER_DECK_POS := Vector2(PLAYER_ZONE_COL_X, SLOT_Y_BOT)  # (970, 485)
const PLAYER_GRAVEYARD_POS := Vector2(PLAYER_ZONE_COL_X, 407.0)
const PLAYER_BANISH_POS := Vector2(PLAYER_ZONE_COL_X, 358.0)
## 배치권 표시 (덱 왼쪽).
const PLAYER_PERMISSION_POS := Vector2(888.0, SLOT_Y_BOT)

## Opponent 슬롯 행 Y (Player 180°: 648 - y).
const OPP_SLOT_Y_FAR := FIELD_SIZE.y - SLOT_Y_BOT  # 163
const OPP_SLOT_Y_NEAR := FIELD_SIZE.y - SLOT_Y_TOP  # 257
const OPP_BOARD_BAND_MID_Y := (OPP_SLOT_Y_FAR + OPP_SLOT_Y_NEAR) * 0.5  # 210
## Opponent 존 = (FIELD_SIZE - player_pos) 성분별.
const OPP_LIFE_POS := Vector2(FIELD_SIZE.x - PLAYER_LIFE_POS.x, FIELD_SIZE.y - PLAYER_LIFE_POS.y)  # (985, 210)
const OPP_DECK_POS := Vector2(FIELD_SIZE.x - PLAYER_DECK_POS.x, FIELD_SIZE.y - PLAYER_DECK_POS.y)  # (182, 163)
const OPP_GRAVEYARD_POS := Vector2(FIELD_SIZE.x - PLAYER_GRAVEYARD_POS.x, FIELD_SIZE.y - PLAYER_GRAVEYARD_POS.y)  # (182, 241)
const OPP_BANISH_POS := Vector2(FIELD_SIZE.x - PLAYER_BANISH_POS.x, FIELD_SIZE.y - PLAYER_BANISH_POS.y)  # (182, 290)

## 라인 파워 라벨 (각 라인 중점 X · 보드 사이 통로 세로 중앙).
const POWER_LABEL_SIZE := Vector2(60.0, 35.0)
const POWER_LABEL_Y := (SLOT_Y_TOP + OPP_SLOT_Y_NEAR) * 0.5  # 324
const POWER_LABEL_LEFT_X := CENTER_LINE_MID_X - LINE_MID_SPACING  # 340
const POWER_LABEL_CENTER_X := CENTER_LINE_MID_X
const POWER_LABEL_RIGHT_X := CENTER_LINE_MID_X + LINE_MID_SPACING  # 812

# --- Board3D SubViewport (전체 화면 1개 · 양 진영 메시) ---
## false면 Board3D 숨김 · 단색 BoardSkin 사용.
const BOARD_3D_VIEWPORTS_ENABLED := true
## Display z (Backdrop -50 · BoardSkin -20 사이). tscn과 맞춤.
const BOARD_3D_Z_INDEX := -25
## SubViewport·Display 픽셀 크기 (필드 전체).
const BOARD_3D_VIEWPORT_SIZE := Vector2(1152, 648)
const BOARD_3D_DISPLAY_CENTER := Vector2(576, 324)
## 클리어색 (tscn Environment · 참고).
const BOARD_3D_CLEAR := Color(0.1, 0.12, 0.16, 1.0)
## 탑다운 직교 카메라 (tscn Camera3D · Inspector 조절).
## pos (0,22,0) rot X -90° · size=세로 전장(월드 유닛).
const BOARD_3D_CAMERA_HEIGHT := 22.0
const BOARD_3D_CAMERA_ORTHO_SIZE := 23.0
## 메시 배치 참고: PlayerBoard Z=+5.305 · OpponentBoard Z=-5.265 (scale 8.2)
const BOARD_3D_PLAYER_MESH_PATH := "Board3DViewports/SubViewport/PlayerBoard"
const BOARD_3D_OPPONENT_MESH_PATH := "Board3DViewports/SubViewport/OpponentBoard"
const DEFAULT_FIELD_SCENE := "res://assets_lite/accessories/field/board.glb"

# --- 존(덱·라이프·묘지·제외) 단색 패드 — 보드 스킨과 동일 색 ---
## 덱/묘지/제외 (스케일 0.4 카드 발자국, 보드 로컬·비회전 패드)
const ZONE_CARD_SKIN_SIZE := Vector2(100, 120)
## 라이프 스택 (슬롯 상하 밴드 ≈ SLOT_Y_BOT-SLOT_Y_TOP+카드높이)
const ZONE_LIFE_SKIN_SIZE := Vector2(110, 200)

# --- L|C|R 라인 분리선 (Field 로컬 X · 슬롯 군집 사이 중점) ---
## (Left mid + pitch)와 (Center mid − pitch)의 중점 등.
const LINE_SEP_X_LEFT_CENTER := CENTER_LINE_MID_X - LINE_MID_SPACING * 0.5  # 458
const LINE_SEP_X_CENTER_RIGHT := CENTER_LINE_MID_X + LINE_MID_SPACING * 0.5  # 694
const LINE_SEP_COLOR := Color(0.292, 0.326, 0.427, 1.0)
const LINE_SEP_WIDTH := 2.0
## 보드 스킨 세로 길이의 비율로 선 길이 (1=스킨 높이 전체)
const LINE_SEP_HEIGHT_RATIO := 1.0

# --- PhaseButton (GameUILayer 스크린 좌표) ---
## game.tscn PhaseButton 배치 SSOT (폭 150). Builder는 씬 크기 우선, 폴백만 이 값.
const PHASE_BUTTON_OFFSET := Vector2(968, 297)
const PHASE_BUTTON_SIZE := Vector2(150, 31)
