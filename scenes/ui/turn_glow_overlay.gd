extends Control
## 턴/효과 소유 글로우 오버레이 (풀스크린, 클릭 통과).
## 부모는 CanvasLayer(layer=-10) — GameUILayer(15)와 분리해 월드 핸드·필드 카드 아래에 그린다.
##
## 튜닝:
## - GLOW_ALPHA — 글로우 농도
## - ARC_DEPTH_RATIO — 중앙 경계에서 곡선이 파고드는 비율 (0.05~0.2)
## - OFFSET_RATIO / ROUND_STEPS — 호 형태·폴리곤 해상도
## - COLOR_PLAYER / COLOR_OPPONENT — GameConstants.ALLY/OPPONENT_COLOR

const COLOR_PLAYER := GameConstants.ALLY_COLOR
const COLOR_OPPONENT := GameConstants.OPPONENT_COLOR
const GLOW_ALPHA := 0.18
const ROUND_STEPS := 32
const OFFSET_RATIO := 0.5 

# 호가 중앙 경계(mid_y)로부터 얼마나 파고들지 결정하는 깊이 비율 (0.05 ~ 0.2 추천)
# 화면 높이(size.y)의 몇 %만큼 곡선이 깎일지 설정합니다.
const ARC_DEPTH_RATIO := 0.10 

var _glow_side: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 부모 CanvasLayer.layer=-10 → 월드(핸드·필드 카드)보다 아래. Control z_index로 핸드를 못 밑는다.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)


func set_glow_side(local_side: int) -> void:
	if _glow_side == local_side:
		return
	_glow_side = local_side
	visible = _glow_side >= 0
	queue_redraw()


func _draw() -> void:
	if _glow_side < 0:
		return

	var size := get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var base_color := COLOR_PLAYER if _glow_side == GameConstants.Side.PLAYER else COLOR_OPPONENT
	
	# 수정한 부분: 기본 y축 기준점(mid_y)을 화면 정중앙에서 각각 위/아래로 밀어냅니다.
	var offset := size.y * OFFSET_RATIO

	if _glow_side == GameConstants.Side.PLAYER:
		# 플레이어는 기준선을 아래로 끌어내림 (영역 감소)
		var custom_mid_y := (size.y * 0.5) + offset 
		_draw_bottom_half(size, custom_mid_y, base_color)
	else:
		# 상대방은 기준선을 위로 끌어올림 (영역 감소)
		var custom_mid_y := (size.y * 0.5) - offset 
		_draw_top_half(size, custom_mid_y, base_color)


func _draw_bottom_half(size: Vector2, mid_y: float, base_color: Color) -> void:
	var color := base_color
	color.a = GLOW_ALPHA
	var points := PackedVector2Array()

	# 1. 외곽 사각형 모서리 채우기 (하단 화면)
	points.append(Vector2(0.0, size.y))
	points.append(Vector2(size.x, size.y))
	
	# 2. 우측 끝(size.x, mid_y)에서 좌측 끝(0.0, mid_y)으로 이어지는 거대한 곡선 추가
	# 플레이어(하단)는 위로 깎인 모양(위가 오목하게 들어간 형태)을 만듭니다.
	_append_large_arc_boundary(points, size.x, mid_y, size.y * ARC_DEPTH_RATIO, true)

	draw_colored_polygon(points, color)


func _draw_top_half(size: Vector2, mid_y: float, base_color: Color) -> void:
	var color := base_color
	color.a = GLOW_ALPHA
	var points := PackedVector2Array()

	# 1. 외곽 사각형 모서리 채우기 (상단 화면)
	points.append(Vector2(0.0, 0.0))
	points.append(Vector2(size.x, 0.0))
	
	# 2. 우측 끝에서 좌측 끝으로 이어지는 거대한 곡선 추가
	# 상대(상단)는 아래로 깎인 모양(아래가 오목하게 들어간 형태)을 만듭니다.
	_append_large_arc_boundary(points, size.x, mid_y, size.y * ARC_DEPTH_RATIO, false)

	draw_colored_polygon(points, color)


# 화면 전체를 가로지르는 호의 정점들을 계산하여 다각형 배열에 추가하는 함수
func _append_large_arc_boundary(
	points: PackedVector2Array,
	width: float,
	mid_y: float,
	depth: float,
	curve_downward: bool
) -> void:
	if depth <= 0.0:
		# 깊이가 없으면 그냥 직선으로 연결
		points.append(Vector2(width, mid_y))
		points.append(Vector2(0.0, mid_y))
		return

	# 현의 길이(w)와 처짐량(h = depth)을 이용해 원의 반지름(R) 계산
	# 공식: R = (w^2 / 8h) + (h / 2)
	var w := width
	var h := depth
	var radius := (w * w) / (8.0 * h) + (h / 2.0)
	
	# 원의 중심점 계산
	var center_x := width * 0.5
	var center_y := mid_y + (radius - h) if curve_downward else mid_y - (radius - h)
	
	# 시작각과 끝각 계산 (우측 끝 -> 좌측 끝 방향)
	# 원의 중심에서 양쪽 끝점(w, mid_y)과 (0, mid_y)를 바라보는 각도 구하기
	var start_angle := atan2(mid_y - center_y, width - center_x)
	var end_angle := atan2(mid_y - center_y, 0.0 - center_x)
	
	# 보간 처리 (우측 끝에서 좌측 끝으로 부드럽게 이동)
	for step in ROUND_STEPS + 1:
		var t := float(step) / float(ROUND_STEPS)
		var angle := lerp_angle(start_angle, end_angle, t)
		
		# lerp_angle의 최단 경로 문제를 방지하기 위한 안전장치
		if curve_downward and angle < 0:
			angle += TAU
			
		var vx := center_x + cos(angle) * radius
		var vy := center_y + sin(angle) * radius
		points.append(Vector2(vx, vy))
