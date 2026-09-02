class_name HandFanLayout
extends RefCounted
## 손패 부채꼴 배치. 플레이어/상대 공용.
## 목표: 위 모서리가 살짝만 ∩ 곡선 · 필드 슬롯을 가리지 않음.
##
## --- 직접 조절 (이 파일 const) ---
## *_BASE_Y …………… 가운데 카드 중심 Y (클수록 아래·필드에서 멀어짐)
## *_CENTER_X_OFFSET … 화면 중앙 대비 좌(-)/우(+)
## *_SPACING_X ……… 카드 중심 가로 간격(px)
## *_MAX_HALF_ANGLE_DEG … 맨 끝 카드 기울기 상한(도) — 작을수록 위 모서리가 덜 올라감
## *_PER_CARD_ANGLE_DEG … 장당 기울기(도)
## *_TOP_SAG_PX ……… 양끝 카드가 가운데보다 내려가는 양(px). 0=일자, 6~14=살짝 ∩
## Z_BASE …………… 손패 z_index 시작값


# --- 플레이어 (하단) ---
## 필드 슬롯과 간격 확보 — 너무 올리면 슬롯을 가림.
const PLAYER_BASE_Y := 585.0
const PLAYER_CENTER_X_OFFSET := 0.0
const PLAYER_SPACING_X := 74.0
const PLAYER_MAX_HALF_ANGLE_DEG := 8.5
const PLAYER_PER_CARD_ANGLE_DEG := 2.2
## 위 모서리 곡선 깊이(작을수록 거의 일자).
const PLAYER_TOP_SAG_PX := 6.0

# --- 상대 (상단) ---
const OPPONENT_BASE_Y := 58.0
const OPPONENT_CENTER_X_OFFSET := 0.0
const OPPONENT_SPACING_X := 66.0
const OPPONENT_MAX_HALF_ANGLE_DEG := 10.0
const OPPONENT_PER_CARD_ANGLE_DEG := 2.6
const OPPONENT_TOP_SAG_PX := 7.0

const FALLBACK_VIEWPORT := Vector2(1152, 648)
const Z_BASE := 10


static func pose_for(
	side: GameConstants.Side,
	index: int,
	count: int,
	viewport_size: Vector2 = Vector2.ZERO
) -> Dictionary:
	var vp := viewport_size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = FALLBACK_VIEWPORT

	var is_player := side == GameConstants.Side.PLAYER

	var center := Vector2(
		vp.x * 0.5 + (PLAYER_CENTER_X_OFFSET if is_player else OPPONENT_CENTER_X_OFFSET),
		PLAYER_BASE_Y if is_player else OPPONENT_BASE_Y
	)

	var spacing := PLAYER_SPACING_X if is_player else OPPONENT_SPACING_X
	var max_half := PLAYER_MAX_HALF_ANGLE_DEG if is_player else OPPONENT_MAX_HALF_ANGLE_DEG
	var per_card := PLAYER_PER_CARD_ANGLE_DEG if is_player else OPPONENT_PER_CARD_ANGLE_DEG
	var sag := PLAYER_TOP_SAG_PX if is_player else OPPONENT_TOP_SAG_PX

	var mid := 0.0
	var offset := 0.0
	if count > 1:
		mid = float(count - 1) * 0.5
		offset = float(index) - mid

	var angle_deg := clampf(offset * per_card, -max_half, max_half)
	var angle := deg_to_rad(angle_deg)

	# 기존 sag
	var sag_y := 0.0
	if mid > 0.0 and sag != 0.0:
		var t := absf(offset) / mid
		sag_y = sag * t * t

	# 추가 Arc
	# 회전 방향으로 카드 중심을 아주 조금 이동시켜
	# 회전과 위치가 자연스럽게 연결되도록 함.
	const ARC_X := 10.0
	const ARC_Y := 8.0

	var arc_x := sin(angle) * ARC_X
	var arc_y := (1.0 - cos(angle)) * ARC_Y

	var pos := Vector2(
		center.x + offset * spacing + arc_x,
		center.y + sag_y + arc_y if is_player else center.y - sag_y - arc_y
	)

	var rot := angle if is_player else -angle

	return {
		"position": pos,
		"rotation": rot,
		"z_index": z_for_index(index),
	}


## 손패 장수 기준 z. 오른쪽(큰 index)이 위에 그려지게.
static func z_for_index(index: int) -> int:
	return Z_BASE + maxi(index, 0)
