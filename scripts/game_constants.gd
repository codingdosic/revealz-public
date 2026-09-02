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
## 플립 애니 중간(옆면) — 풀 스케일의 X 비율.
const CARD_SPRITE_FLIP_EDGE_RATIO := 0.08
## 공개 플립: 옆면 교체 시점(초).
## card.tscn / opponent_card.tscn card_flip · card_flip_back 키와 맞출 것.
const CARD_FLIP_SWAP_SEC := 0.14
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
