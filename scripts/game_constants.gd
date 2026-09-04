class_name GameConstants
extends RefCounted

enum Phase { DRAW, SETTING, BATTLE, CLEAN, GAME_OVER }
enum Line { LEFT, CENTER, RIGHT }
enum Side { PLAYER, OPPONENT }
enum RevealState { HAND, SETTING_PREVIEW, SETTING_HIDDEN, REVEALED }

const DEFAULT_HAND_LIMIT := 6
const LIFE_START_COUNT := 3
const SETTING_PLACEMENTS := 5

const COLLISION_LAYER_CARD := 1
const COLLISION_LAYER_CARD_SLOT := 2
const COLLISION_LAYER_DECK := 4
const COLLISION_LAYER_GRAVEYARD := 8
const COLLISION_LAYER_ZONE_TOOLTIP := 16

const ALLY_COLOR := Color(0.0, 0.0, 1.0, 1.0)
const OPPONENT_COLOR :=  Color(1.0, 0.0, 0.0, 1.0)

const NORM_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const POWER_UP_COLOR := Color(0.0, 1.0, 0.0, 1.0)
const POWER_DOWN_COLOR := Color(1.0, 0.0, 0.204, 1.0)

## CardImage / CardBackImage Sprite2D scale.
## 큰 원본 일러스트 시절 0.05 · 작은(인게임≈1) 이미지면 1.
const CARD_SPRITE_SCALE := 0.5
## (레거시) scale.x 눈속임 플립용. tilt 플립에서는 미사용.
const CARD_SPRITE_FLIP_EDGE_RATIO := 0.08
## 인게임 Y축 tilt 플립: 회전 구간 길이 · 옆면(면 교체) 시점(초).
const CARD_FLIP_TOTAL_SEC := 0.32
const CARD_FLIP_SWAP_SEC := 0.14
## 옆면 각도(도). 셰이더 원근으로 폭이 거의 0이 되는 지점.
const CARD_FLIP_EDGE_DEG := 90.0
## 플립 중 약한 pitch — 턴스타일 느낌 완화.
const CARD_FLIP_PITCH_DEG := 10.0
## 공개(뒷→앞) 플립: 위로 뜨다 앞면 최고점 후 쾅 착지.
const CARD_FLIP_LIFT_PX := 20.0
const CARD_FLIP_LIFT_SCALE := 1.12
const CARD_FLIP_LIFT_Z := 6
## 면 교체 시점의 상승량(0~1). 앞면 완전 공개 때 1.0.
const CARD_FLIP_LIFT_AT_SWAP := 0.82
const CARD_FLIP_PEAK_HOLD_SEC := 0.05
const CARD_FLIP_SLAM_SEC := 0.14
## 동일 라인 오픈 충격: 착지 풍압 3단 감쇠 틸트 (근→원→근).
const CARD_OPEN_SHOCK_TILT_MAX_DEG := 32.0
const CARD_OPEN_SHOCK_LIFT_PX := 7.0
const CARD_OPEN_SHOCK_UP_SEC := 0.07
const CARD_OPEN_SHOCK_DOWN_SEC := 0.10
## 2·3번째 펄스 진폭 배율 (1번째=1.0).
const CARD_OPEN_SHOCK_AMP2 := 0.58
const CARD_OPEN_SHOCK_AMP3 := 0.30
## 진폭·시간·방향에 ±비율 노이즈.
const CARD_OPEN_SHOCK_NOISE := 0.5
## 이 거리(px)에서 충격 강도 0.
const CARD_OPEN_SHOCK_FALLOFF_PX := 240.0
## 오픈 플립 착지(쾅) 기준 — slam 구간 내 비율 (카메라 쉐이크와 맞춤).
const CARD_OPEN_SHOCK_SLAM_AT := 0.72
## CardInfoSidebar 일러 클릭 확대 — 사이드바 CardImage(180×250) 대비 배율.
const CARD_INFO_ZOOM_SCALE := 2.5

# TODO: 세팅 페이즈 시간 제한 (초) — 추후 적용
# const SETTING_TIME_LIMIT := 30.0


## 카드 앞/뒤 스프라이트 기본 scale.
static func card_sprite_scale_vec() -> Vector2:
	return Vector2(CARD_SPRITE_SCALE, CARD_SPRITE_SCALE)


## 플립 중간(얇은 옆면) scale.
static func card_sprite_flip_edge_vec() -> Vector2:
	return Vector2(CARD_SPRITE_SCALE * CARD_SPRITE_FLIP_EDGE_RATIO, CARD_SPRITE_SCALE)


static func line_stat_index(line: GameConstants.Line) -> int:
	match line:
		Line.LEFT:
			return 0
		Line.CENTER:
			return 1
		Line.RIGHT:
			return 2
	return 0


static func opposite_side(side: GameConstants.Side) -> GameConstants.Side:
	return GameConstants.Side.OPPONENT if side == GameConstants.Side.PLAYER else GameConstants.Side.PLAYER
