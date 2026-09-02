class_name CardRarity
extends RefCounted
## 카드 레어도 N/R/SR/UR. 배지는 N 포함 전 등급. 셰이더 아웃라인은 R 이상.


enum Tier {
	N = 0,
	R = 1,
	SR = 2,
	UR = 3,
}

const LABEL_N := "N"
const LABEL_R := "R"
const LABEL_SR := "SR"
const LABEL_UR := "UR"

## StyleBox 테두리·글로우. 레어 쉐이더 전환 중 비활성. 배지·accent·OPEN FX는 유지.
const ENABLE_STYLEBOX_FRAME := false


## 아웃라인·배지 대상이면 true (R 이상). 배지 단독은 shows_badge.
static func shows_display(tier: int) -> bool:
	return tier >= Tier.R


## 우상단 레어도 배지를 그릴 등급이면 true (N 포함).
static func shows_badge(tier: int) -> bool:
	return tier >= Tier.N and tier <= Tier.UR


## StyleBox RarityFrame을 켤지. ENABLE_STYLEBOX_FRAME이 false면 항상 숨김.
static func shows_frame(tier: int) -> bool:
	return ENABLE_STYLEBOX_FRAME and shows_display(tier)


## 팩 개봉 플립 연출(빛/펄스)을 쓸 등급이면 true (SR 이상).
static func plays_reveal_fx(tier: int) -> bool:
	return tier >= Tier.SR


## 등급 짧은 라벨.
static func label_of(tier: int) -> String:
	match tier:
		Tier.R:
			return LABEL_R
		Tier.SR:
			return LABEL_SR
		Tier.UR:
			return LABEL_UR
		_:
			return LABEL_N


## 등급 액센트 색 (테두리·배지·글로우·힌트).
## R 파랑 · SR 붉은 주황 · UR 보라 · N 회색.
static func accent_of(tier: int) -> Color:
	match tier:
		Tier.R:
			return Color(0.127, 0.472, 0.85, 1.0)
		Tier.SR:
			# 기존(0.95, 0.48, 0.08)보다 채도 높은 붉은 주황.
			return Color(0.841, 0.439, 0.0, 1.0)
		Tier.UR:
			return Color(0.68, 0.157, 0.917, 1.0)
		_:
			return Color(0.45, 0.45, 0.5, 1.0)


## 외곽 글로우 shadow_size — 테두리만 살짝 (카드 면을 덮지 않게 작게).
static func glow_size_of(tier: int) -> int:
	match tier:
		Tier.R:
			return 8
		Tier.SR:
			return 9
		Tier.UR:
			return 10
		_:
			return 0


## 테두리 + 약한 외곽 글로우 StyleBox. 중앙은 그리지 않아 일러스트를 가리지 않음.
static func make_frame_style(tier: int, border_width: float = 2.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.draw_center = false
	var accent := accent_of(tier)
	# 테두리 자체도 살짝 밝게.
	style.border_color = accent.lightened(0.12)
	style.set_border_width_all(int(round(border_width)))
	var glow := glow_size_of(tier)
	if glow > 0:
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.32)
		style.shadow_size = glow
		style.shadow_offset = Vector2.ZERO
	return style


## 칩용 레어 배지 StyleBox (우상단).
static func make_badge_style(tier: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent := accent_of(tier)
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.92)
	style.border_color = Color(0, 0, 0, 0.55)
	style.set_border_width_all(1)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	return style
