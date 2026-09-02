class_name MatchVfx
extends RefCounted
## 매치 카드 이동·연출 진입점. Host에 바인딩 · Dedicated/headless는 snap no-op.
## 계약: play=병렬 즉시 · await_*=끝날 때까지 대기.
## params 키: from, to, duration, trail, color, trail_width, trail_fade_sec, to_rotation, face(KEEP|UP|DOWN).
## 파이프라인: StepMoveCards 등 fx_* → EffectContext.begin_move_vfx → merge_opts.
##
## --- 튜닝 SSOT ---
## 기본 상수: 이 파일 DEFAULT_* / default_*_params()
## 패·드로우: scenes/game/player_hand.gd · opponent_hand.gd (speed→duration) + DeckZone.CARD_DRAW_SPEED
## 라이프→패: DeckZone._place_card_at_life_for_hand_fx + CARD_DRAW_SPEED (배틀·셔플·드로우 라이프)
## 필드 배치·리로케이트·스왑: default_field_params() · PhaseManager._place_* · EffectContext.place_on_slot_with_fx
## 슬롯 착지: 배치 직후 play_slot_land · 오픈: play_slot_land_after_flip (플립 완료 후)
## 필드→묘지: default_grave_params() · move_to_graveyard
## CLEAN 일괄 묘지: FieldManager.clear_field_to_graveyard (trail off)
## 바인드/제외: default_banish_params() · move_to_banishzone / bind_*
## 패 도착 face: face_for_hand_side (내 UP · 상대 DOWN)


## 이동 중 앞/뒷면. 생략·KEEP이면 카드 현재 비주얼 유지.
const FACE_KEEP := "keep"
const FACE_UP := "up"
const FACE_DOWN := "down"

const DEFAULT_HAND_MOVE_SEC := 1
const DEFAULT_ZONE_MOVE_SEC := 0.3
const DEFAULT_FIELD_MOVE_SEC := 0.3
## 라인 배틀 5단: prep → lunge → impact(+shake) → return. SSOT — MatchVfxHost.await_line_clash
const DEFAULT_BATTLE_PREP_SEC := 0.10
const DEFAULT_BATTLE_PULLBACK_PX := 24.0
const DEFAULT_BATTLE_PREP_SCALE := 0.95
const DEFAULT_BATTLE_LUNGE_SEC := 0.16
## Y만 교전선 쪽으로 이동(0~1). X(슬롯 열) 유지 — 1이면 한 점으로 뭉침.
const DEFAULT_BATTLE_LUNGE_Y_FRAC := 0.58
const DEFAULT_BATTLE_IMPACT_PUNCH_SEC := 0.05
const DEFAULT_BATTLE_IMPACT_SCALE := 1.08
const DEFAULT_BATTLE_IMPACT_HOLD_SEC := 0.08
const DEFAULT_BATTLE_RETURN_SEC := 0.24
const DEFAULT_BATTLE_HIT_SHAKE_SEC := 0.14
const DEFAULT_BATTLE_HIT_SHAKE_PX := 5.0
const DEFAULT_BATTLE_HIT_SHAKE_STEPS := 4
const DEFAULT_BATTLE_CAMERA_SHAKE_SEC := 0.3
const DEFAULT_BATTLE_CAMERA_SHAKE_PX := 10
const DEFAULT_BATTLE_CAMERA_SHAKE_STEPS := 7
const DEFAULT_TRAIL_WIDTH := 4.0
const DEFAULT_TRAIL_FADE_SEC := 0.12
const DEFAULT_TRAIL_COLOR := Color(0.35, 0.85, 1.0, 0.55)
const TRAIL_COLOR_BLACK := Color(0.62, 0.28, 0.95, 0.7)
const TRAIL_COLOR_WHITE := Color(0.95, 0.88, 0.55, 0.7)
const TRAIL_COLOR_GREEN := Color(0.25, 0.85, 0.35, 0.7)
const TRAIL_COLOR_RED := Color(0.95, 0.35, 0.25, 0.7)
const TRAIL_COLOR_BLUE := Color(0.25, 0.55, 1.0, 0.7)
## 슬롯 착지/오픈 rim flash — 시작 직후 날카로운 사각 → 이후 soft spread.
## SEC = 전체 길이(작을수록 빠름) · HOLD = 날카로운 사각 유지 시간 · 나머지는 soft 확산.
## START/END_SIZE = 월드 px (카드 footprint ≈ 63×88 @ scale 0.4).
const SLOT_LAND_TEX_SIZE := 128
const SLOT_LAND_COLOR_PLACE := Color(0.72, 0.9, 1.0, 1.0)
const SLOT_LAND_COLOR_OPEN := Color(1.0, 0.94, 0.72, 1.0)
const SLOT_LAND_START_SIZE := Vector2(68, 94)
const SLOT_LAND_END_SIZE := Vector2(104, 142)
const SLOT_LAND_OPEN_END_SIZE := Vector2(118, 160)
const SLOT_LAND_HOLD_SEC := 0.045
const SLOT_LAND_SEC := 0.3
const SLOT_LAND_OPEN_SEC := 0.3
const SLOT_LAND_PEAK_ALPHA := 0.75
const SLOT_LAND_OPEN_PEAK_ALPHA := 0.8
const COLOR_FLAG_BLACK := 1
const COLOR_FLAG_WHITE := 2
const COLOR_FLAG_GREEN := 4
const COLOR_FLAG_RED := 8
const COLOR_FLAG_BLUE := 16

static var _host: MatchVfxHost = null


## Host를 등록한다. null이면 이후 호출은 즉시 snap.
static func bind(host: MatchVfxHost) -> void:
	_host = host


## 등록된 Host. 없거나 freed면 null.
## 트리 여부는 보지 않는다 — orphan Host라도 카드 Tween은 재생 가능.
static func get_host() -> MatchVfxHost:
	if _host != null and is_instance_valid(_host):
		return _host
	return null


## 재생용 Host. 가능하면 Field 아래 트리 안으로 복구한다.
static func _resolve_play_host(card: Node = null) -> MatchVfxHost:
	var host := get_host()
	if host != null and host.is_inside_tree():
		return host
	var field: Node = null
	if card != null and is_instance_valid(card) and card.is_inside_tree():
		var n: Node = card
		while n:
			if str(n.name) == "Field":
				field = n
				break
			n = n.get_parent()
	if field != null:
		host = FieldBoardBuilder.ensure_match_vfx_host(field)
		if host != null:
			return host
	return get_host()


## 연출을 재생할 수 있으면 true (headless·미바인딩=false).
static func is_active() -> bool:
	var host := get_host()
	return host != null and host.is_vfx_active()


## 이동/연출 재생 중이면 true.
static func is_busy() -> bool:
	var host := get_host()
	return host != null and host.is_busy()


## 파이프라인 오버라이드를 params에 합친다. 없는 키는 기본 유지.
static func merge_opts(params: Dictionary, override: Dictionary) -> Dictionary:
	if override.is_empty():
		return params
	var out := params.duplicate()
	if override.has("trail"):
		out["trail"] = bool(override["trail"])
	if override.has("color"):
		out["color"] = override["color"]
	if override.has("trail_width") and float(override["trail_width"]) > 0.0:
		out["trail_width"] = float(override["trail_width"])
	if override.has("duration") and float(override["duration"]) > 0.0:
		out["duration"] = float(override["duration"])
	if override.has("trail_fade_sec") and float(override["trail_fade_sec"]) > 0.0:
		out["trail_fade_sec"] = float(override["trail_fade_sec"])
	return out


## 시전 카드 색 플래그 → 트레일 기본색.
static func trail_color_for_card(card: Node) -> Color:
	if card == null or not is_instance_valid(card):
		return DEFAULT_TRAIL_COLOR
	var flags := int(card.get("card_color")) if card.get("card_color") != null else 0
	if (flags & COLOR_FLAG_BLACK) != 0:
		return TRAIL_COLOR_BLACK
	if (flags & COLOR_FLAG_WHITE) != 0:
		return TRAIL_COLOR_WHITE
	if (flags & COLOR_FLAG_GREEN) != 0:
		return TRAIL_COLOR_GREEN
	if (flags & COLOR_FLAG_RED) != 0:
		return TRAIL_COLOR_RED
	if (flags & COLOR_FLAG_BLUE) != 0:
		return TRAIL_COLOR_BLUE
	return DEFAULT_TRAIL_COLOR


## 카드 이동을 즉시 시작한다(대기 없음). 패 부채 등 병렬용.
static func play_card_move(card: Node2D, params: Dictionary = {}) -> void:
	var host := _resolve_play_host(card)
	if host == null or not host.is_vfx_active():
		MatchVfx.snap_card(card, params)
		return
	host.play_card_move(card, params)


## 카드 이동이 끝날 때까지 기다린다. 존 이동·효과 스텝용.
static func await_card_move(card: Node2D, params: Dictionary = {}) -> void:
	var host := _resolve_play_host(card)
	if host == null or not host.is_vfx_active():
		snap_card(card, params)
		return
	await host.await_card_move(card, params)


## 병렬 Tween을 모두 기다린다. 이미 끝난 tween에 await finished 하면 Godot 4에서 영구 정지한다.
static func await_all_tweens(tweens: Array) -> void:
	var box := {"n": 0}
	for item in tweens:
		var tween := item as Tween
		if tween == null or not tween.is_valid() or not tween.is_running():
			continue
		box["n"] = int(box["n"]) + 1
		tween.finished.connect(_on_join_tween_finished.bind(box), CONNECT_ONE_SHOT)
	if int(box["n"]) <= 0:
		return
	var tree := _scene_tree()
	if tree == null:
		return
	var frames := 0
	while int(box["n"]) > 0 and frames < 900:
		frames += 1
		await tree.process_frame


## await_all_tweens 카운터 감소. 인라인 람다는 파서가 깨질 수 있음.
static func _on_join_tween_finished(box: Dictionary) -> void:
	box["n"] = int(box["n"]) - 1


## 재생용 SceneTree. Host 우선.
static func _scene_tree() -> SceneTree:
	var host := get_host()
	if host != null and is_instance_valid(host) and host.is_inside_tree():
		return host.get_tree()
	return Engine.get_main_loop() as SceneTree


## 여러 이동을 동시에 시작하고 모두 끝날 때까지 기다린다.
static func await_parallel_moves(moves: Array) -> void:
	var card0: Node = null
	for item in moves:
		if typeof(item) == TYPE_DICTIONARY:
			card0 = item.get("card") as Node
			if card0 != null:
				break
	var host := _resolve_play_host(card0)
	if host == null or not host.is_vfx_active():
		for item in moves:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			snap_card(item.get("card") as Node2D, item.get("params", {}) as Dictionary)
		return
	await host.await_parallel_moves(moves)


## 존→묘지 기본 파라미터. 공개 존이라 face=UP.
static func default_grave_params() -> Dictionary:
	return {
		"duration": DEFAULT_ZONE_MOVE_SEC,
		"trail": true,
		"color": DEFAULT_TRAIL_COLOR,
		"to_rotation": 0.0,
		"face": FACE_UP,
	}


## 존→바인드/제외 기본 파라미터. 공개 존이라 face=UP.
static func default_banish_params() -> Dictionary:
	return {
		"duration": DEFAULT_ZONE_MOVE_SEC,
		"trail": true,
		"color": Color(0.75, 0.35, 1.0, 0.55),
		"to_rotation": 0.0,
		"face": FACE_UP,
	}


## 패/드로우 기본 파라미터. face는 호출측에서 UP/DOWN 지정 권장.
static func default_hand_params(
	duration: float = DEFAULT_HAND_MOVE_SEC,
	face: String = FACE_KEEP
) -> Dictionary:
	return {
		"duration": duration,
		"trail": false,
		"color": DEFAULT_TRAIL_COLOR,
		"face": face,
	}


## 필드 슬롯·배치·리로케이트 기본. face=KEEP (세팅 프리뷰/히든 유지).
static func default_field_params(face: String = FACE_KEEP) -> Dictionary:
	return {
		"duration": DEFAULT_FIELD_MOVE_SEC,
		"trail": false,
		"color": DEFAULT_TRAIL_COLOR,
		"to_rotation": 0.0,
		"face": face,
	}


## 슬롯 착지/오픈 사각 rim flash. kind: place | open. 튜닝: SLOT_LAND_*.
static func play_slot_land(world_pos: Vector2, kind: String = "place") -> void:
	var host := _resolve_play_host()
	if host == null or not host.is_vfx_active():
		return
	host.play_slot_land(world_pos, kind)


## card_flip 재생이 끝난 뒤 슬롯 open FX. 애니 없으면 즉시.
static func play_slot_land_after_flip(card: Node2D, kind: String = "open") -> void:
	var host := _resolve_play_host(card)
	if host == null or not host.is_vfx_active():
		return
	host.play_slot_land_after_flip(card, kind)


## 패 도착 face: 내 카드 앞면 · 상대 카드 뒷면.
static func face_for_hand_side(side: GameConstants.Side) -> String:
	return FACE_UP if side == GameConstants.Side.PLAYER else FACE_DOWN


## 슬롯으로 이동 연출. place 직후 위치를 from으로 되돌린 뒤 Tween.
static func await_move_to_slot(
	card: Node2D,
	slot: Node2D,
	face: String = FACE_KEEP
) -> void:
	if card == null or not is_instance_valid(card) or slot == null:
		return
	var from := card.global_position
	var to := slot.global_position
	var params := default_field_params(face)
	params["from"] = from
	params["to"] = to
	await await_card_move(card, params)


## params.face에 맞춰 앞/뒷면 비주얼을 적용한다. KEEP·없음은 no-op.
static func apply_face(card: Node2D, params: Dictionary) -> void:
	if card == null or not is_instance_valid(card):
		return
	if not params.has("face"):
		return
	var face := String(params.get("face", FACE_KEEP))
	match face:
		FACE_UP:
			CardHelpers.apply_hand_visual(card)
		FACE_DOWN:
			CardHelpers.apply_hand_hidden(card)
		_:
			pass


## 라인 배틀 5단 + Field camera shake.
static func await_line_clash(cards: Array, clash_pos: Vector2) -> void:
	var card0: Node2D = null
	for c in cards:
		if c != null and is_instance_valid(c):
			card0 = c as Node2D
			break
	var host := _resolve_play_host(card0)
	if host == null or not host.is_vfx_active():
		return
	await host.await_line_clash(cards, clash_pos)


## 토큰 등 슬롯 팝인(스케일). card_flip과 겹치지 않게 호출측에서 instant reveal 후 사용.
static func await_token_spawn_pop_in(
	card: Node2D,
	target_scale: Vector2 = Vector2(0.4, 0.4)
) -> void:
	var host := _resolve_play_host(card)
	if host == null or not host.is_vfx_active():
		card.scale = target_scale
		return
	await host.await_token_spawn_pop_in(card, target_scale)


## Host 없이 목표 pose로 즉시 맞춘다.
static func snap_card(card: Node2D, params: Dictionary) -> void:
	if card == null or not is_instance_valid(card):
		return
	apply_face(card, params)
	if params.has("from"):
		card.global_position = params["from"] as Vector2
	if params.has("to"):
		card.global_position = params["to"] as Vector2
	if params.has("to_rotation"):
		card.rotation = float(params["to_rotation"])
	elif params.has("rotation"):
		card.rotation = float(params["rotation"])
