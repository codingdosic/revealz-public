extends Node
## 페이즈 루프·배치·온라인 이벤트 큐. DRAW/TURN/GAME_START 송신은 OnlineAuthority 세션 duck API (S2).
## 존 변이·효과 파이프라인은 EffectManager/Context에 위임. MP 프로토콜 문자열은 여기서 바꾸지 않음.
## S4: 외부(EM 등)는 `refresh_match_ui()`만 호출 — LP/라인 파워 private `_update_*` duck-call 금지.

const AI_DELAY := 1.0
const FLIP_DELAY := 0.5
const PHASE_PAUSE := 1.0
const PHASE_PAUSE_LONG := 3.0
const BATTLE_CLASH_LINE_GAP := 0.18
const MP_PLACE_DEBUG := false
const MP_DRAW_DEBUG := false

const COLOR_POWER_POSITIVE := Color(0.25, 0.45, 1.0)
const COLOR_POWER_NEGATIVE := Color(1.0, 0.25, 0.25)
const COLOR_POWER_NEUTRAL := Color(1.0, 1.0, 1.0)

const PLAYER_CARD_SCENE := preload("uid://c2ad0j2453lap")
const OPPONENT_CARD_SCENE := preload("uid://bdd7xc700lf05")

var current_phase: GameConstants.Phase = GameConstants.Phase.DRAW
var first_player: GameConstants.Side = GameConstants.Side.PLAYER
var last_round_winner: GameConstants.Side = GameConstants.Side.PLAYER

var placements_remaining: Dictionary = {}
var active_side: GameConstants.Side = GameConstants.Side.PLAYER
var round_pair_cards: Array = []
var setting_turn_index: int = 0

var player_pending_card: Node2D = null

## 새 룰 리소스. null 이면 기존 동작 (MP 호환). 싱글에서만 활성화.
@export var rules: GameRulesResource = null

## 배치권 풀 {Side: int} — rules 활성 시에만 사용
var placement_permission: Dictionary = {}
## 현재 턴에 배치 예정 중인 카드 목록 (확정 전)
var pending_cards: Array = []
## 현재 턴 라인 잠금 (-1 = 없음, 0/1/2 = Line enum)
var _locked_line: int = -1

var battle_timer: Timer
var phase_button: Button
var player_deck: DeckZone
var opponent_deck: DeckZone
var field_manager: Node
var player_hand: Node
var opponent_hand: Node
var effect_manager: EffectManager

var player_life_display: LifeContainerDisplay
var opponent_life_display: LifeContainerDisplay

var left_power_label: Label
var center_power_label: Label
var right_power_label: Label

## 플레이어 배치권 MVP 표시 (덱 왼쪽). rules 모드에서만 갱신.
var placement_permission_display: PlacementPermissionDisplay

var _processing: bool = false
var _awaiting_remote_place_ack: bool = false
var _awaiting_ack_card: Node2D = null
var _match_ready: bool = false
var _awaiting_turn_sync: bool = false
var _net_event_queue: Array = []
var _net_event_busy: bool = false
var _change_applier: EffectChangeApplier = EffectChangeApplier.new()
## SETTING 토스트 중복 방지 키 ("n/turns"). TURN_CHANGED 이중 송신 대비.
var _last_setting_toast_key: String = ""


func _ready() -> void:
	# PhaseButton → UI + 필드 스킨/Board3D 뷰포트.
	FieldBoardBuilder.build(get_parent())
	battle_timer = $"../BattleTimer"
	battle_timer.one_shot = true
	phase_button = get_node_or_null("../GameUILayer/PhaseButton") as Button
	if phase_button == null:
		phase_button = get_node_or_null("../PhaseButton") as Button
	player_deck = _field_node("PlayerDeck") as DeckZone
	opponent_deck = _field_node("OpponentDeck") as DeckZone
	field_manager = $"../FieldManager"
	player_hand = $"../PlayerHand"
	opponent_hand = $"../OpponentHand"
	effect_manager = $"../EffectManager"
	effect_manager.setup(
		self,
		field_manager,
		player_deck,
		opponent_deck,
		player_hand,
		opponent_hand,
		$"../CardManager"
	)

	player_life_display = _field_node("PlayerLifeContainer") as LifeContainerDisplay
	opponent_life_display = _field_node("OpponentLifeContainer") as LifeContainerDisplay
	player_life_display.setup(player_deck, PLAYER_CARD_SCENE)
	opponent_life_display.setup(opponent_deck, OPPONENT_CARD_SCENE)

	var game_ui := $"../GameUILayer"
	game_ui.call_deferred(
		"finish_setup",
		effect_manager,
		player_deck,
		opponent_deck,
		player_hand,
		opponent_hand,
		_field_node("PlayerGraveyard"),
		_field_node("OpponentGraveyard"),
		player_life_display,
		opponent_life_display,
		_field_node("PlayerBanishZone"),
		_field_node("OpponentBanishZone"),
		$"../OpponentHandHover"
	)

	left_power_label = $"../LeftPowerLabel/ValueLabel"
	center_power_label = $"../CenterPowerLabel/ValueLabel"
	right_power_label = $"../RightPowerLabel/ValueLabel"
	placement_permission_display = _field_node("PlacementPermissionDisplay") as PlacementPermissionDisplay
	if placement_permission_display:
		# rules 미연결 시 배치권 바를 처음부터 숨김 (레거시 모드).
		placement_permission_display.visible = rules != null
		if rules == null:
			placement_permission_display.clear_permission()

	if phase_button:
		phase_button.pressed.connect(_on_confirm_pressed)

	call_deferred("_boot_match")


## 로딩→game 페이드인이 있으면 밝아진 뒤 start_match (페이즈 토스트 포함).
func _boot_match() -> void:
	await SceneTransition.play_armed_fade_in()
	await start_match()


## Field 직속 또는 PlayerBoard/OpponentBoard 아래 노드.
func _field_node(field_child_path: String) -> Node:
	return FieldBoardBuilder.find_under_field(self, field_child_path)


func _session() -> GameSessionBase:
	return GameSession.get_active()


func _mp_role() -> String:
	if not _is_online():
		return "LOCAL"
	return "HOST" if _is_authoritative() else "CLIENT"


func _mp_reveal_name(state: GameConstants.RevealState) -> String:
	match state:
		GameConstants.RevealState.HAND:
			return "HAND"
		GameConstants.RevealState.SETTING_PREVIEW:
			return "PREVIEW"
		GameConstants.RevealState.SETTING_HIDDEN:
			return "HIDDEN"
		GameConstants.RevealState.REVEALED:
			return "REVEALED"
		_:
			return str(int(state))


func _mp_place_log(tag: String, details: String = "") -> void:
	if not MP_PLACE_DEBUG:
		return
	var msg := "[MP-PLACE][%s][%s]" % [_mp_role(), tag]
	if details != "":
		msg += " %s" % details
	print(msg)


func _mp_draw_log(tag: String, details: String = "") -> void:
	if not MP_DRAW_DEBUG:
		return
	var msg := "[MP-DRAW][%s][%s]" % [_mp_role(), tag]
	if details != "":
		msg += " %s" % details
	print(msg)


func _mp_slot_label(slot: CardSlot) -> String:
	if slot == null:
		return "slot=null"
	return "side=%d line=%d idx=%d empty=%s occupant_uuid=%d" % [
		int(slot.side),
		int(slot.line),
		field_manager.get_slot_index_for_slot(slot),
		str(slot.is_empty()),
		slot.card_in_slot.network_uuid if slot.card_in_slot else 0,
	]


func _mp_card_label(card: Node2D) -> String:
	if card == null:
		return "card=null"
	var slot: CardSlot = card.card_slot_card_is_in
	var slot_text := "off_field"
	if slot:
		slot_text = _mp_slot_label(slot)
	return (
		"uuid=%d name=%s reveal=%s locked=%s interactive=%s pending=%s ack=%s %s"
		% [
			card.network_uuid,
			card.card_name,
			_mp_reveal_name(card.reveal_state),
			str(card.is_locked),
			str(card.is_interactive),
			str(card == player_pending_card),
			str(card == _awaiting_ack_card),
			slot_text,
		]
	)


func _is_online() -> bool:
	return _session().play_mode == GameSessionBase.PlayMode.ONLINE


func _is_authoritative() -> bool:
	return _session().is_authoritative()


func _effects_enabled() -> bool:
	# 새 룰 모드에서 세팅 페이즈는 rules.setting_effects_enabled 우선
	if _is_rules_mode() and current_phase == GameConstants.Phase.SETTING:
		return rules.setting_effects_enabled
	return _session().effects_enabled


## 매치 시작: 덱/라이프 초기화 → (온라인 권위) scene-ready·dispatch_game_start → DRAW→SETTING.
## 왜: GAME_START/resend는 세션 duck API — PM은 Host/Dedicated 타입 분기하지 않음 (S2).
func start_match() -> void:
	var session := _session()
	session.register_phase_manager(self)

	if _is_online() and not session.should_start_match_locally():
		return

	if _is_online() and _is_online_authority_session(session):
		first_player = session.first_player
	elif session.play_mode == GameSessionBase.PlayMode.LOCAL_SINGLE:
		first_player = session.first_player
	else:
		first_player = session.roll_first_player()
	last_round_winner = first_player
	var first_label := "플레이어" if first_player == GameConstants.Side.PLAYER else "상대"
	print("선공: %s" % first_label)

	if _is_online():
		player_deck.init_match_from_entries(session.get_deck_entries_for_local_side(GameConstants.Side.PLAYER))
		opponent_deck.init_match_from_entries(session.get_deck_entries_for_local_side(GameConstants.Side.OPPONENT))
	else:
		# get_deck_ids_for_side 우선; 비면 get_deck_names_for_side→names_to_ids 폴백.
		var p_ids := session.get_deck_ids_for_side(GameConstants.Side.PLAYER)
		var o_ids := session.get_deck_ids_for_side(GameConstants.Side.OPPONENT)
		if p_ids.is_empty():
			p_ids = CardRegistry.names_to_ids(session.get_deck_names_for_side(GameConstants.Side.PLAYER))
		if o_ids.is_empty():
			o_ids = CardRegistry.names_to_ids(session.get_deck_names_for_side(GameConstants.Side.OPPONENT))
		player_deck.init_match(p_ids, session.get_deck_rarities_for_side(GameConstants.Side.PLAYER))
		opponent_deck.init_match(o_ids, session.get_deck_rarities_for_side(GameConstants.Side.OPPONENT))

	player_deck.take_cards_to_life(GameConstants.LIFE_START_COUNT)
	opponent_deck.take_cards_to_life(GameConstants.LIFE_START_COUNT)
	_update_life_ui()

	if _is_online_authority_session(session) and _is_online():
		await session.wait_for_client_scene_ready()
		if session.has_method("is_match_aborted") and session.is_match_aborted():
			print("[MP-DRAW] match aborted during CLIENT_SCENE_READY wait — skip GAME_START/DRAW")
			return
		(session as OnlineAuthoritySessionBase).dispatch_game_start()
		if not session.is_client_scene_ready():
			push_warning("[MP-DRAW] starting match without CLIENT_SCENE_READY")

	if _is_authoritative():
		if session.has_method("is_match_aborted") and session.is_match_aborted():
			return
		await enter_draw_phase()
		if _is_online_authority_session(session) and _is_online():
			if not session.is_client_scene_ready():
				(session as OnlineAuthoritySessionBase).resend_match_init()


## Host|Dedicated(OnlineAuthoritySessionBase) 여부. ClientGameSession·Local은 false.
## 왜: GAME_START/DRAW/TURN duck API는 권위 세션에만 있음 (S1 타입 유니온 → S2 세션 호출).
func _is_online_authority_session(session: GameSessionBase = null) -> bool:
	var s := session if session else _session()
	return s is OnlineAuthoritySessionBase


func _finish_remote_placement_wait() -> void:
	var s := _session()
	if s.has_method("finish_remote_placement_wait"):
		s.finish_remote_placement_wait()

func enter_draw_phase() -> void:
	current_phase = GameConstants.Phase.DRAW
	_processing = true
	_update_phase_button()
	await _show_phase_toast("~ draw phase ~")

	var player_draw := player_deck.draw_to_hand_limit(player_hand.get_hand_size(), true)
	var opponent_draw := opponent_deck.draw_to_hand_limit(opponent_hand.get_hand_size(), false)
	_update_life_ui()

	if _is_online() and _is_authoritative():
		_mp_draw_log(
			"host_draw",
			"player limit=%d entries=%d hand=%d | opponent limit=%d entries=%d hand=%d"
			% [
				player_draw.get("hand_limit", 0),
				player_draw.get("hand_entries", []).size(),
				player_hand.get_hand_size(),
				opponent_draw.get("hand_limit", 0),
				opponent_draw.get("hand_entries", []).size(),
				opponent_hand.get_hand_size(),
			]
		)
		_dispatch_draw_result(player_draw, opponent_draw)

	_match_ready = true

	if _is_authoritative():
		await enter_setting_phase()


func enter_setting_phase() -> void:
	current_phase = GameConstants.Phase.SETTING
	_last_setting_toast_key = ""
	var game_ui := $"../GameUILayer"
	if game_ui and game_ui.has_method("hide_card_sidebar"):
		game_ui.hide_card_sidebar()
	var turns := rules.setting_turns_per_player if rules else GameConstants.SETTING_PLACEMENTS
	placements_remaining = {
		GameConstants.Side.PLAYER: turns,
		GameConstants.Side.OPPONENT: turns,
	}
	active_side = first_player
	round_pair_cards.clear()
	player_pending_card = null
	pending_cards.clear()
	_locked_line = -1
	setting_turn_index = 0
	_reset_line_power_labels()

	if _is_rules_mode():
		placement_permission = {
			GameConstants.Side.PLAYER: 0,
			GameConstants.Side.OPPONENT: 0,
		}
		print("[RULES] ▶ 세팅 페이즈 시작 — 배치권 리셋 0/0  턴수/플레이어: %d" % turns)

	if _is_online() and _is_authoritative():
		_dispatch_turn_changed()

	if _is_authoritative():
		await _begin_setting_turn()
	elif _is_online():
		_awaiting_turn_sync = true
		_processing = true
		_update_phase_button()
	else:
		_update_phase_button()


func _begin_setting_turn() -> void:
	if _all_placements_done():
		if _is_authoritative():
			await enter_battle_phase()
		return

	if _is_rules_mode():
		_rules_grant_permission(active_side)
		pending_cards.clear()
		_locked_line = -1
		if _is_online() and _is_authoritative():
			_dispatch_turn_changed()

	# Dedicated server: both seats are remote thin clients.
	if _is_online() and _is_authoritative() and _session() is ServerAuthoritySession:
		await _run_remote_authority_setting_turn()
		return

	if active_side == GameConstants.Side.OPPONENT:
		await _run_opponent_setting_turn()
	else:
		# 플레이어 턴: 토스트 후 processing 해제·버튼 활성화
		_processing = true
		_update_phase_button()
		await _show_own_setting_phase_toast()
		_processing = false
		_update_phase_button()


func _run_remote_authority_setting_turn() -> void:
	_processing = true
	_update_phase_button()
	var session := _session() as ServerAuthoritySession
	session.begin_remote_placement_wait()
	await session.wait_for_remote_placement()
	_processing = false


func _all_placements_done() -> bool:
	return (
		placements_remaining[GameConstants.Side.PLAYER] <= 0
		and placements_remaining[GameConstants.Side.OPPONENT] <= 0
	)


func _run_opponent_setting_turn() -> void:
	# MP: 상대는 원격 인간 — COM 룰 AI보다 원격 대기를 우선.
	if _is_online() and _is_authoritative():
		_processing = true
		_update_phase_button()
		var host_session := _session() as HostGameSession
		await host_session.wait_for_remote_placement()
		_processing = false
		return

	if _is_rules_mode():
		await _rules_com_setting_turn()
		return

	_processing = true
	_update_phase_button()

	await wait(AI_DELAY)

	var hand_cards: Array = opponent_hand.get_hand_cards()
	if hand_cards.is_empty():
		await _confirm_side_placement(null)
		return

	var card: Node2D = hand_cards[0]
	var slot: CardSlot = field_manager.get_random_empty_slot(GameConstants.Side.OPPONENT)
	if slot == null:
		push_warning("PhaseManager: no empty opponent slots available")
		await _confirm_side_placement(null)
		return

	opponent_hand.remove_card_from_hand(card)
	await _finalize_placed_card(card, false, _play_setting_hidden_flip())
	await _place_card_with_move_fx(card, slot)

	await wait(AI_DELAY)
	await _confirm_side_placement(card)


# ─────────────────────────────────────────────
#  NEW RULES 헬퍼
# ─────────────────────────────────────────────

## rules 리소스가 있으면 싱글·온라인 모두 새 배치 룰 사용.
## null = 레거시(1장/턴). 의도적으로 비운 경우를 default로 덮지 않음 — 클라·Dedicated 동일 전제.
func _is_rules_mode() -> bool:
	return rules != null


## 해당 side 의 턴 시작 배치권 부여. 상한 초과 소멸.
func _rules_grant_permission(side: GameConstants.Side) -> void:
	var before := int(placement_permission.get(side, 0))
	var gained := rules.permission_gain_per_turn
	var after := mini(before + gained, rules.permission_max_stored)
	placement_permission[side] = after
	var side_label := "플레이어" if side == GameConstants.Side.PLAYER else "COM"
	print("[RULES] %s 턴 시작 — 배치권 %d → %d  (상한 %d)" % [side_label, before, after, rules.permission_max_stored])


## 현재 active_side 의 배치권 반환.
func _rules_current_permission() -> int:
	return int(placement_permission.get(active_side, 0))


## pending_cards 의 총 코스트 합산.
func _rules_pending_cost() -> int:
	var total := 0
	for c in pending_cards:
		if c and c.card_data:
			total += c.card_data.setting_cost
	return total


## 새 카드를 추가했을 때 배치권이 충분한지.
func _rules_can_afford(card: Node2D) -> bool:
	if not card or not card.card_data:
		return false
	return _rules_pending_cost() + card.card_data.setting_cost <= _rules_current_permission()


## 슬롯의 라인이 현재 턴 잠금 라인과 충돌하지 않는지 확인.
## exclude_card: 재배치 시 해당 카드를 제외하고 잠금 라인 계산.
func _rules_check_line_for_slot(slot: CardSlot, card: Node2D, exclude_card: Node2D = null) -> bool:
	if not card or not card.card_data:
		return true
	var is_unit: bool = card.card_data.card_type == "Unit"
	var is_spell: bool = card.card_data.card_type == "Spell"
	var needs_lock: bool = (is_unit and rules.require_same_line_unit) or (is_spell and rules.require_same_line_spell)
	if not needs_lock:
		return true
	# 다른 pending 카드들에서 잠금 라인 계산
	var effective_lock: int = -1
	for c in pending_cards:
		if c == exclude_card or not c.card_data or not c.card_slot_card_is_in:
			continue
		var c_is_unit: bool = c.card_data.card_type == "Unit"
		var c_is_spell: bool = c.card_data.card_type == "Spell"
		if (c_is_unit and rules.require_same_line_unit) or (c_is_spell and rules.require_same_line_spell):
			effective_lock = int(c.card_slot_card_is_in.line)
			break
	if effective_lock == -1:
		return true
	return int(slot.line) == effective_lock


## pending_cards 의 현재 슬롯 위치를 기반으로 _locked_line 재계산.
func _update_locked_line_from_pending() -> void:
	_locked_line = -1
	for c in pending_cards:
		if not c.card_data or not c.card_slot_card_is_in:
			continue
		var c_is_unit: bool = c.card_data.card_type == "Unit"
		var c_is_spell: bool = c.card_data.card_type == "Spell"
		if (c_is_unit and rules.require_same_line_unit) or (c_is_spell and rules.require_same_line_spell):
			_locked_line = int(c.card_slot_card_is_in.line)
			break


## GameConstants.Line int → 문자열 (로그용).
func _line_label(line_int: int) -> String:
	match line_int:
		0: return "LEFT"
		1: return "CENTER"
		2: return "RIGHT"
		_: return "?"


## 카드가 현재 플레이어 pending 상태인지 (player_pending_card 또는 multi-pending).
func is_card_pending(card: Node2D) -> bool:
	if card == player_pending_card:
		return true
	if _is_rules_mode():
		return card in pending_cards
	return false


## COM 새 룰 세팅 턴. 배치권/비용/라인 규칙 적용.
func _rules_com_setting_turn() -> void:
	_processing = true
	_update_phase_button()
	await wait(AI_DELAY)

	var perm := int(placement_permission.get(GameConstants.Side.OPPONENT, 0))
	var hand_cards: Array = opponent_hand.get_hand_cards()
	print("[RULES] COM 턴 — 배치권: %d  패: %d장" % [perm, hand_cards.size()])

	# 패가 없으면 즉시 패스
	if hand_cards.is_empty():
		print("[RULES] COM 패스 (패 없음)")
		await _confirm_side_placement_multi([])
		return

	# 비용 낼 수 있는 카드 목록
	var affordable: Array = []
	for c in hand_cards:
		if c.card_data and c.card_data.setting_cost <= perm:
			affordable.append(c)

	if affordable.is_empty():
		print("[RULES] COM 패스 (배치 가능 카드 없음 — 최소 비용 %d, 보유 배치권 %d)" % [
			_com_min_cost(hand_cards), perm
		])
		await _confirm_side_placement_multi([])
		return

	var cards_to_place: Array = []
	var remaining_perm := perm
	var locked_line_com: int = -1

	for c in affordable:
		if cards_to_place.size() >= rules.max_cards_per_turn:
			break
		var cost: int = c.card_data.setting_cost
		if cost > remaining_perm:
			continue

		var is_unit: bool = c.card_data.card_type == "Unit"
		var is_spell: bool = c.card_data.card_type == "Spell"
		var needs_lock: bool = (is_unit and rules.require_same_line_unit) or (is_spell and rules.require_same_line_spell)

		var slot: CardSlot = null
		if needs_lock and locked_line_com != -1:
			var line_enum := locked_line_com as GameConstants.Line
			var empties: Array = field_manager.get_empty_slots(GameConstants.Side.OPPONENT, line_enum)
			if not empties.is_empty():
				slot = empties[randi() % empties.size()]
		else:
			slot = field_manager.get_random_empty_slot(GameConstants.Side.OPPONENT)

		if slot == null:
			continue

		if needs_lock and locked_line_com == -1:
			locked_line_com = int(slot.line)

		opponent_hand.remove_card_from_hand(c)
		await _finalize_placed_card(c, false, _play_setting_hidden_flip())
		await _place_card_with_move_fx(c, slot)

		cards_to_place.append(c)
		remaining_perm -= cost
		print("[RULES] COM 배치: %s  cost=%d  line=%s  잔여권=%d" % [
			c.card_name, cost, _line_label(int(slot.line)), remaining_perm
		])

	# 루프 후에도 배치 카드가 없으면 패스 (슬롯 없음 등)
	if cards_to_place.is_empty():
		print("[RULES] COM 패스 (빈 슬롯 없음 또는 조건 미충족)")
		await _confirm_side_placement_multi([])
		return

	await wait(AI_DELAY)
	await _confirm_side_placement_multi(cards_to_place)


## COM 패 중 최소 비용 반환 (패스 로그용)
func _com_min_cost(hand_cards: Array) -> int:
	var min_cost := 9999
	for c in hand_cards:
		if c.card_data:
			var cost: int = c.card_data.setting_cost
			if cost < min_cost:
				min_cost = cost
	return min_cost if min_cost < 9999 else 0


func on_player_pending_place(card: Node2D, slot: CardSlot) -> void:
	if active_side != GameConstants.Side.PLAYER:
		return
	if current_phase != GameConstants.Phase.SETTING:
		return

	if _is_rules_mode():
		_on_player_pending_place_rules(card, slot)
		return

	# ─── 기존 싱글/온라인 경로 ───
	if not player_hand.get_hand_cards().has(card) and player_pending_card != card:
		return

	if player_hand.get_hand_cards().has(card):
		player_hand.remove_card_from_hand(card)

	if player_pending_card != null and player_pending_card != card:
		var previous_pending: Node2D = player_pending_card
		player_pending_card = null
		_return_card_to_hand(previous_pending)

	player_pending_card = card
	_place_pending_with_move_fx(card, slot)
	_mp_place_log(
		"pending_place",
		"%s target=%s turn=%d" % [_mp_card_label(card), _mp_slot_label(slot), setting_turn_index]
	)
	_update_phase_button()
	_update_line_power_labels()


## 새 룰 모드: 플레이어 카드 pending 배치 처리.
func _on_player_pending_place_rules(card: Node2D, slot: CardSlot) -> void:
	var is_re_drag := card in pending_cards

	if is_re_drag:
		# 이미 pending인 카드 → 슬롯만 변경 (비용 재계산 불필요)
		field_manager.remove_card_from_slot(card)
		_place_pending_with_move_fx(card, slot)
		_update_locked_line_from_pending()
		player_pending_card = card
		print("[RULES] 플레이어 재배치: %s → line=%s" % [card.card_name, _line_label(int(slot.line))])
	else:
		# 패에서 새로 배치 (can_drop_on_slot 통과 보장)
		if not player_hand.get_hand_cards().has(card):
			return
		player_hand.remove_card_from_hand(card)
		pending_cards.append(card)
		_place_pending_with_move_fx(card, slot)
		player_pending_card = card

		# 라인 잠금 갱신
		if card.card_data:
			var is_unit: bool = card.card_data.card_type == "Unit"
			var is_spell: bool = card.card_data.card_type == "Spell"
			if (is_unit and rules.require_same_line_unit) or (is_spell and rules.require_same_line_spell):
				if _locked_line == -1:
					_locked_line = int(slot.line)

		var perm := _rules_current_permission()
		var used := _rules_pending_cost()
		print("[RULES] 플레이어 배치 예정: %s  cost=%d  배치권=%d  사용중=%d  잔여=%d" % [
			card.card_name,
			card.card_data.setting_cost if card.card_data else 0,
			perm, used, perm - used
		])

	_update_phase_button()
	_update_line_power_labels()


func on_player_drag_cancelled(card: Node2D) -> void:
	if active_side != GameConstants.Side.PLAYER:
		return
	if player_pending_card == card:
		player_pending_card = null
	if _is_rules_mode() and card in pending_cards:
		pending_cards.erase(card)
		_update_locked_line_from_pending()
		print("[RULES] 플레이어 배치 취소: %s  pending 잔여 %d장" % [card.card_name, pending_cards.size()])
	_return_card_to_hand(card)
	_update_phase_button()
	_update_line_power_labels()


func _return_card_to_hand(card: Node2D) -> void:
	field_manager.remove_card_from_slot(card)
	card.is_locked = false
	CardHelpers.enable_interaction(card)
	card.apply_hand_visual()
	card.z_index = 1
	card.scale = Vector2(0.4, 0.4)

	if card.owner_side == GameConstants.Side.PLAYER:
		if not player_hand.get_hand_cards().has(card):
			player_hand.add_card_to_hand(card, 0.1)
		else:
			player_hand.update_hand_positions(0.1)
	else:
		opponent_hand.add_card_to_hand(card, 0.1)


func _on_confirm_pressed() -> void:
	if not is_match_ready():
		return
	if _awaiting_turn_sync:
		return
	if _processing:
		return
	if current_phase != GameConstants.Phase.SETTING:
		return
	if active_side != GameConstants.Side.PLAYER:
		return

	# ─── 새 룰 경로 ───
	if _is_rules_mode():
		print("[RULES] 확정 버튼 — pending=%d장  allow_pass=%s  processing=%s" % [
			pending_cards.size(), str(rules.allow_pass), str(_processing)
		])
		if pending_cards.is_empty():
			if not rules.allow_pass:
				print("[RULES] 패스 불가 (allow_pass=false)")
				return
			_processing = true
			_update_phase_button()
			var do_pass := await _ask_pass_confirm()
			if not do_pass:
				print("[RULES] 플레이어 패스 취소")
				_processing = false
				_update_phase_button()
				return
			print("[RULES] 플레이어 패스 (배치권 %d 유지)" % _rules_current_permission())
			if _is_online() and not _is_authoritative():
				_awaiting_remote_place_ack = true
				_session().submit_intent({
					"type": NetworkConstants.INTENT_PLACE,
					"pass": true,
					"placements": [],
					"uuid": 0,
					"line": 0,
					"slotIndex": 0,
				})
				return
			await _confirm_side_placement_multi([])
			return
		_processing = true
		if _is_online() and not _is_authoritative():
			_submit_rules_place_intent(pending_cards.duplicate())
			return
		await _confirm_side_placement_multi(pending_cards.duplicate())
		return

	# ─── 기존 경로 ───
	if player_pending_card == null:
		return

	if _is_online() and not _is_authoritative():
		var slot: CardSlot = player_pending_card.card_slot_card_is_in
		if slot == null:
			_mp_place_log("confirm_blocked", "client pending card has no slot")
			return
		var card: Node2D = player_pending_card
		_mp_place_log(
			"confirm_client_send",
			"before_finalize %s intent_line=%d intent_slot=%d"
			% [_mp_card_label(card), int(slot.line), field_manager.get_slot_index_for_slot(slot)]
		)
		await _finalize_placed_card(card, true, _play_setting_hidden_flip())
		_awaiting_ack_card = card
		_processing = true
		_awaiting_remote_place_ack = true
		_mp_place_log("confirm_client_send", "after_finalize %s" % _mp_card_label(card))
		_session().submit_intent({
			"type": NetworkConstants.INTENT_PLACE,
			"uuid": card.network_uuid,
			"line": int(slot.line),
			"slotIndex": field_manager.get_slot_index_for_slot(slot),
		})
		return

	_processing = true
	var card: Node2D = player_pending_card
	_mp_place_log("confirm_host_local", "before_place %s" % _mp_card_label(card))
	await _confirm_side_placement(card)
	_processing = false


func _confirm_side_placement(card: Node2D) -> void:
	_mp_place_log(
		"confirm_side_enter",
		"card=%s active_side=%d turn_before=%d pair_size=%d"
		% [
			_mp_card_label(card),
			int(active_side),
			setting_turn_index,
			round_pair_cards.size(),
		]
	)
	if card:
		await _finalize_placed_card(card, true, _play_setting_hidden_flip())
		round_pair_cards.append(card)

	placements_remaining[active_side] -= 1
	setting_turn_index += 1
	var placed_side := active_side
	active_side = GameConstants.opposite_side(active_side)

	var did_flip := false
	var flip_cards: Array = []
	if setting_turn_index % 2 == 0 and round_pair_cards.size() >= 2:
		did_flip = true
		flip_cards = round_pair_cards.duplicate()

	if _is_online() and _is_authoritative():
		_broadcast_place_card(card, placed_side, did_flip, flip_cards)

	if did_flip:
		await _flip_round_pair()
		round_pair_cards.clear()

	_mp_place_log(
		"confirm_side_done",
		"placed_side=%d did_flip=%s turn=%d active_side=%d pair_size=%d"
		% [int(placed_side), str(did_flip), setting_turn_index, int(active_side), round_pair_cards.size()]
	)

	_update_phase_button()
	_update_line_power_labels()

	if _all_placements_done():
		if _is_authoritative():
			await enter_battle_phase()
		return

	_processing = false

	if _is_online() and _is_authoritative():
		_dispatch_turn_changed()

	if _is_authoritative():
		await _begin_setting_turn()


## 새 룰: 패스 확인 다이얼로그. await로 사용, true=패스 확인, false=취소.
## 패스 확인. 항복과 동일하게 GameUILayer EffectDialogPanel 사용.
## ConfirmationDialog 는 hide 시 canceled 가 추가로 나와 결과가 덮일 수 있어 사용하지 않음.
func _ask_pass_confirm() -> bool:
	var game_ui := get_node_or_null("../GameUILayer")
	var dialog: PanelContainer = null
	if game_ui != null and game_ui.has_method("get_effect_dialog"):
		dialog = game_ui.get_effect_dialog()

	if dialog == null or not dialog.has_method("configure") or not dialog.has_method("show_dialog"):
		print("[RULES] 패스 확인 UI 없음 — 자동 패스")
		return true

	if dialog.visible:
		print("[RULES] 패스 확인: 다른 다이얼로그 사용 중")
		return false

	dialog.configure(
		"패스 확인",
		"배치 없이 턴을 넘기겠습니까?\n현재 배치권: %d (유지됨)" % _rules_current_permission(),
		"패스",
		"취소"
	)

	# first-wins: confirmed 이후 canceled 가 와도 덮지 않음
	var out: Array = []
	var on_ok := func() -> void:
		if out.is_empty():
			out.append(true)
	var on_cancel := func() -> void:
		if out.is_empty():
			out.append(false)

	if dialog.has_signal("confirmed"):
		dialog.confirmed.connect(on_ok, CONNECT_ONE_SHOT)
	if dialog.has_signal("canceled"):
		dialog.canceled.connect(on_cancel, CONNECT_ONE_SHOT)
	if dialog.has_signal("minimized"):
		dialog.minimized.connect(on_cancel, CONNECT_ONE_SHOT)

	dialog.show_dialog()
	print("[RULES] 패스 확인 다이얼로그 표시")

	while out.is_empty():
		await get_tree().process_frame

	if dialog.has_method("hide_dialog"):
		dialog.hide_dialog()

	if dialog.has_signal("confirmed") and dialog.confirmed.is_connected(on_ok):
		dialog.confirmed.disconnect(on_ok)
	if dialog.has_signal("canceled") and dialog.canceled.is_connected(on_cancel):
		dialog.canceled.disconnect(on_cancel)
	if dialog.has_signal("minimized") and dialog.minimized.is_connected(on_cancel):
		dialog.minimized.disconnect(on_cancel)

	var accepted: bool = out[0]
	print("[RULES] 패스 확인 결과: %s" % ("패스" if accepted else "취소"))
	return accepted


## 새 룰 전용 다중 배치 확정. cards = [] 이면 패스.
func _confirm_side_placement_multi(cards: Array) -> void:
	var cost_total := 0
	await _finalize_placed_cards(cards, false, _play_setting_hidden_flip())
	for c in cards:
		round_pair_cards.append(c)
		if c != null and is_instance_valid(c) and c.card_data:
			cost_total += c.card_data.setting_cost

	# 배치권 차감
	var perm_before := int(placement_permission.get(active_side, 0))
	placement_permission[active_side] = max(0, perm_before - cost_total)
	var side_label := "플레이어" if active_side == GameConstants.Side.PLAYER else "COM"
	if cards.is_empty():
		print("[RULES] %s 패스 확정 — 배치권 %d 유지" % [side_label, placement_permission[active_side]])
	else:
		print("[RULES] %s 배치 확정 — %d장  코스트합계=%d  배치권 %d → %d" % [
			side_label, cards.size(), cost_total, perm_before, placement_permission[active_side]
		])

	placements_remaining[active_side] -= 1
	setting_turn_index += 1
	var placed_side := active_side
	active_side = GameConstants.opposite_side(active_side)
	pending_cards.clear()
	player_pending_card = null
	_locked_line = -1

	var did_flip := setting_turn_index % 2 == 0
	var flip_cards: Array = round_pair_cards.duplicate() if did_flip else []

	if _is_online() and _is_authoritative():
		_broadcast_place_cards_multi(cards, placed_side, did_flip, flip_cards)

	# 양측 모두 1턴씩 했으면 플립
	if did_flip:
		await _flip_round_pair()
		# _flip_round_pair 는 내부에서 _processing = false 로 끝남.
		# 아직 _begin_setting_turn 을 호출하기 전이므로, 버튼이 일찍
		# 활성화되는 것을 막기 위해 다시 true 로 유지.
		_processing = true
		round_pair_cards.clear()

	_update_phase_button()
	_update_line_power_labels()

	if _all_placements_done():
		if _is_authoritative():
			await enter_battle_phase()
		return

	_processing = false
	if _is_authoritative():
		await _begin_setting_turn()


## 온라인 thin client: pending 카드들로 PLACE(A1) intent 제출.
func _submit_rules_place_intent(cards: Array) -> void:
	var placements: Array = []
	for card in cards:
		if card == null or not is_instance_valid(card):
			continue
		var slot: CardSlot = card.card_slot_card_is_in
		if slot == null:
			_mp_place_log("confirm_blocked", "rules pending card has no slot")
			_processing = false
			_update_phase_button()
			return
		await _finalize_placed_card(card, false, _play_setting_hidden_flip())
		var _pcd: CardData = card.get("card_data") as CardData
		var _pcid: int = int(_pcd.id) if _pcd != null else 0
		placements.append({
			"uuid": int(card.network_uuid),
			"line": int(slot.line),
			"slotIndex": field_manager.get_slot_index_for_slot(slot),
			"cardName": String(card.card_name),
			"cardId": _pcid,
		})
	if placements.is_empty():
		_processing = false
		_update_phase_button()
		return
	_awaiting_remote_place_ack = true
	var first: Dictionary = placements[0]
	_session().submit_intent({
		"type": NetworkConstants.INTENT_PLACE,
		"pass": false,
		"placements": placements,
		"uuid": int(first.get("uuid", 0)),
		"line": int(first.get("line", 0)),
		"slotIndex": int(first.get("slotIndex", 0)),
	})
	_mp_place_log("confirm_client_send_rules", "placements=%d" % placements.size())


func _flip_round_pair() -> void:
	var to_flip: Array
	# 새 룰: 해당 페이즈에 배치된 모든 카드 플립 (최대 4장)
	if _is_rules_mode():
		to_flip = round_pair_cards.duplicate()
	else:
		to_flip = round_pair_cards.slice(-2)
	for c in to_flip:
		c.reveal()
		MatchVfx.play_slot_land_after_flip(c, "open")
	# 오픈 플립·라인 충격이 끝난 뒤에 효과 팝업/창이 뜨도록 대기.
	await CardHoverTilt.await_open_reveal_fx(to_flip, field_manager)
	if _effects_enabled() and effect_manager:
		effect_manager.schedule_passive_refresh()
	_processing = true
	if _effects_enabled():
		await effect_manager.run_open_window(to_flip)
	else:
		if _is_online() and _is_authoritative():
			_broadcast_reveal_pair(to_flip)
		await wait(FLIP_DELAY)
	_update_line_power_labels()
	_processing = false


func enter_battle_phase() -> void:
	current_phase = GameConstants.Phase.BATTLE
	_update_phase_button()
	effect_manager.reset_turn_history()
	if effect_manager:
		# clear_passive 직후 전투가 돌면 대주교 LP=10 등이 0으로 잡힘 → 완료까지 대기.
		await effect_manager.await_passive_refresh()

	var player_by_line: Dictionary = field_manager.get_cards_by_line(GameConstants.Side.PLAYER)
	var opponent_by_line: Dictionary = field_manager.get_cards_by_line(GameConstants.Side.OPPONENT)
	var result: Dictionary = BattleResolver.resolve_round(
		player_by_line,
		opponent_by_line,
		first_player
	)

	var round_winner: GameConstants.Side = result.round_winner
	var round_loser: GameConstants.Side = GameConstants.opposite_side(round_winner)
	var loser_deck: DeckZone = opponent_deck if round_loser == GameConstants.Side.OPPONENT else player_deck
	var loser_hand: Node = opponent_hand if round_loser == GameConstants.Side.OPPONENT else player_hand

	_log_battle_result(result)

	await _play_battle_clash_vfx()

	if loser_deck.get_life_count() == 0:
		enter_game_over(round_winner)
		if _is_online() and _is_authoritative():
			_broadcast_game_over(round_winner)
		return

	var life_pop := loser_deck.pop_life_card_for_hand()
	var life_card_id := int(life_pop.get("cardId", 0))
	var life_card_name := String(life_pop.get("name", ""))
	var life_uuid := int(life_pop.get("uuid", 0))
	var life_rarity := int(life_pop.get("rarity", CardRarity.Tier.N))
	var reveal_in_hand := round_loser == GameConstants.Side.PLAYER
	var new_card: Node2D
	if life_card_id > 0:
		new_card = loser_deck.spawn_card_by_id(life_card_id, reveal_in_hand, life_uuid, life_rarity)
	else:
		new_card = loser_deck.spawn_card_by_name(life_card_name, reveal_in_hand, life_uuid, life_rarity)
	loser_deck._place_card_at_life_for_hand_fx(new_card)
	loser_hand.add_card_to_hand(new_card, DeckZone.CARD_DRAW_SPEED)
	_update_life_ui()
	if MatchVfx.is_active():
		await wait(DeckZone.CARD_DRAW_SPEED)

	if _effects_enabled():
		await effect_manager.run_life_check(round_loser, new_card)

	last_round_winner = round_winner

	if _is_online() and _is_authoritative():
		_mp_draw_log(
			"battle_life_host",
			"loser=%d name=%s uuid=%d hand_limit=%d"
			% [int(round_loser), life_card_name, life_uuid, loser_deck.hand_limit]
		)
		_broadcast_battle_result(result, round_winner, round_loser, life_card_name, new_card)

	await wait(PHASE_PAUSE_LONG)
	await enter_clean_phase()


## 싱글 전용: LEFT→RIGHT 라인 격돌 후 전원 슬롯 복귀.
func _play_battle_clash_vfx() -> void:
	# 싱글 라인 격돌 연출 비활성. 다시 켤 때 true.
	const ENABLED := false
	if not ENABLED or _is_online() or not MatchVfx.is_active():
		return
	_processing = true
	var player_by_line: Dictionary = field_manager.get_cards_by_line(GameConstants.Side.PLAYER)
	var opponent_by_line: Dictionary = field_manager.get_cards_by_line(GameConstants.Side.OPPONENT)
	var lines: Array = [
		GameConstants.Line.LEFT,
		GameConstants.Line.CENTER,
		GameConstants.Line.RIGHT,
	]
	for i in lines.size():
		var line: GameConstants.Line = lines[i]
		var cards: Array = []
		for c in player_by_line.get(line, []):
			if c != null and is_instance_valid(c):
				cards.append(c)
		for c in opponent_by_line.get(line, []):
			if c != null and is_instance_valid(c):
				cards.append(c)
		if cards.is_empty():
			continue
		await MatchVfx.await_line_clash(cards, _battle_clash_pos_for_line(line))
		if i < lines.size() - 1:
			await wait(BATTLE_CLASH_LINE_GAP)
	_processing = false


func _battle_clash_pos_for_line(line: GameConstants.Line) -> Vector2:
	var x: float
	match line:
		GameConstants.Line.LEFT:
			x = FieldBoardLayout.POWER_LABEL_LEFT_X
		GameConstants.Line.RIGHT:
			x = FieldBoardLayout.POWER_LABEL_RIGHT_X
		_:
			x = FieldBoardLayout.POWER_LABEL_CENTER_X
	return Vector2(x, FieldBoardLayout.POWER_LABEL_Y)


func enter_clean_phase() -> void:
	current_phase = GameConstants.Phase.CLEAN
	_update_phase_button()

	await field_manager.clear_field_to_graveyard(player_deck, opponent_deck)
	first_player = last_round_winner
	_reset_line_power_labels()

	if _is_online() and _is_authoritative():
		_broadcast_clean_done()

	await wait(PHASE_PAUSE)

	if _is_authoritative():
		await enter_draw_phase()


func enter_game_over(winner: GameConstants.Side, reason: String = "") -> void:
	current_phase = GameConstants.Phase.GAME_OVER
	_update_phase_button()
	var game_ui := $"../GameUILayer"
	if game_ui and game_ui.has_method("show_game_over"):
		game_ui.show_game_over(winner, reason)
	var winner_name := "플레이어" if winner == GameConstants.Side.PLAYER else "상대"
	if reason == "surrender":
		print("게임 종료 — 항복 · 승자: %s" % winner_name)
	elif reason == "forfeit":
		print("게임 종료 — 기권/접속 종료 · 승자: %s" % winner_name)
	else:
		print("게임 종료 — 승자: %s" % winner_name)


func force_forfeit_game_over(winner: GameConstants.Side) -> void:
	## Dedicated server: stop Logic without broadcasting (session sends per remaining peer).
	if current_phase == GameConstants.Phase.GAME_OVER:
		return
	_finish_remote_placement_wait()
	if effect_manager and effect_manager.has_method("abort_pending_decisions"):
		effect_manager.abort_pending_decisions()
	enter_game_over(winner, "forfeit")


## 자발적 항복 종료. 권위/싱글이 호출. 방송은 세션 책임.
func force_surrender_game_over(winner: GameConstants.Side) -> void:
	if current_phase == GameConstants.Phase.GAME_OVER:
		return
	_finish_remote_placement_wait()
	enter_game_over(winner, "surrender")


func apply_remote_place_intent(intent: Dictionary, from_peer_id: int = 0) -> void:
	if not _is_authoritative():
		return

	var session := _session()
	var place_side := GameConstants.Side.OPPONENT
	var mirror_coords := true
	if session is ServerAuthoritySession:
		var net_side := (session as ServerAuthoritySession).net_side_for_peer(from_peer_id)
		if net_side < 0:
			_mp_place_log("remote_intent_ignored", "unknown peer=%d" % from_peer_id)
			return
		place_side = session.network_side_to_local(net_side)
		# Seat 0 = authority PLAYER coordinates (no mirror); seat 1 = opponent view (mirror).
		mirror_coords = net_side == int(GameConstants.Side.OPPONENT)

	if active_side != place_side:
		_mp_place_log(
			"remote_intent_ignored",
			"active_side=%d expected=%d intent=%s"
			% [int(active_side), int(place_side), str(intent)]
		)
		_broadcast_place_failed("wrong_turn")
		_finish_remote_placement_wait()
		return

	# A1: pass / placements — rules 모드면 룰 경로. 레거시면 1장만 레거시로 강등, 패스/다장은 거부.
	var is_a1_place := (
		bool(intent.get("pass", false))
		or intent.has("placements")
	)
	if _is_rules_mode():
		await _apply_remote_place_intent_rules(intent, place_side, mirror_coords)
		_finish_remote_placement_wait()
		return
	if is_a1_place:
		if bool(intent.get("pass", false)):
			push_warning("PhaseManager: PLACE pass without rules — rejecting")
			_broadcast_place_failed("rules_unavailable")
			_finish_remote_placement_wait()
			return
		var a1_placements: Array = intent.get("placements", [])
		if a1_placements.size() > 1:
			push_warning("PhaseManager: PLACE multi without rules — rejecting")
			_broadcast_place_failed("rules_unavailable")
			_finish_remote_placement_wait()
			return
		if a1_placements.size() == 1 and a1_placements[0] is Dictionary:
			var one: Dictionary = a1_placements[0]
			intent = intent.duplicate()
			intent["uuid"] = int(one.get("uuid", intent.get("uuid", 0)))
			intent["line"] = int(one.get("line", intent.get("line", 0)))
			intent["slotIndex"] = int(one.get("slotIndex", intent.get("slotIndex", 0)))
		elif int(intent.get("uuid", 0)) == 0:
			push_warning("PhaseManager: PLACE A1 empty without rules — rejecting")
			_broadcast_place_failed("rules_unavailable")
			_finish_remote_placement_wait()
			return

	var uuid: int = int(intent.get("uuid", 0))
	if uuid == 0:
		push_warning("PhaseManager: remote PLACE missing uuid (legacy path)")
		_broadcast_place_failed("uuid_not_found")
		_finish_remote_placement_wait()
		return
	var line_idx: int = int(intent.get("line", 0))
	var line: GameConstants.Line = line_idx as GameConstants.Line
	var slot_index: int = int(intent.get("slotIndex", 0))
	if mirror_coords:
		line = _mirror_line_for_opponent_view(line_idx as GameConstants.Line)
		var slot_count: int = field_manager.get_slots_for_side_line(place_side, line).size()
		slot_index = _mirror_slot_index_for_opponent_view(slot_index, slot_count)
	_mp_place_log(
		"remote_intent_recv",
		"peer=%d side=%d uuid=%d client_line=%d auth_line=%d client_slot=%d auth_slot=%d"
		% [
			from_peer_id,
			int(place_side),
			uuid,
			line_idx,
			int(line),
			int(intent.get("slotIndex", 0)),
			slot_index,
		]
	)
	var card := _find_card_by_uuid(uuid)
	if card == null:
		push_warning("PhaseManager: remote PLACE uuid %d not found" % uuid)
		_broadcast_place_failed("uuid_not_found")
		_finish_remote_placement_wait()
		return

	var slot: CardSlot = field_manager.get_slot_for_side_line_index(place_side, line, slot_index)
	_mp_place_log(
		"remote_intent_slot",
		"card=%s target=%s" % [_mp_card_label(card), _mp_slot_label(slot)]
	)
	if slot == null or (not slot.is_empty() and slot.card_in_slot != card):
		push_warning("PhaseManager: remote PLACE slot unavailable line=%d" % int(line))
		_broadcast_place_failed("slot_unavailable")
		_finish_remote_placement_wait()
		return

	var hand: Node = player_hand if place_side == GameConstants.Side.PLAYER else opponent_hand
	hand.remove_card_from_hand(card)
	await _finalize_placed_card(
		card,
		place_side == GameConstants.Side.PLAYER,
		_play_setting_hidden_flip()
	)
	await _place_card_with_move_fx(card, slot)

	await _confirm_side_placement(card)

	_finish_remote_placement_wait()


## PLACE A1: pass 또는 placements[] 검증 후 multi confirm.
func _apply_remote_place_intent_rules(
	intent: Dictionary,
	place_side: GameConstants.Side,
	mirror_coords: bool
) -> void:
	var is_pass := bool(intent.get("pass", false))
	var placements: Array = intent.get("placements", [])
	if placements.is_empty() and not is_pass and int(intent.get("uuid", 0)) != 0:
		placements = [{
			"uuid": int(intent.get("uuid", 0)),
			"line": int(intent.get("line", 0)),
			"slotIndex": int(intent.get("slotIndex", 0)),
		}]

	if is_pass or placements.is_empty():
		if not rules.allow_pass:
			_broadcast_place_failed("pass_not_allowed")
			return
		await _confirm_side_placement_multi([])
		return

	if placements.size() > rules.max_cards_per_turn:
		_broadcast_place_failed("too_many_cards")
		return

	var resolved: Array = []
	var cost_total := 0
	var locked_line: int = -1
	var hand: Node = player_hand if place_side == GameConstants.Side.PLAYER else opponent_hand

	for entry in placements:
		if not entry is Dictionary:
			_broadcast_place_failed("bad_placement_entry")
			return
		var uuid: int = int(entry.get("uuid", 0))
		var line_idx: int = int(entry.get("line", 0))
		var line: GameConstants.Line = line_idx as GameConstants.Line
		var slot_index: int = int(entry.get("slotIndex", 0))
		if mirror_coords:
			line = _mirror_line_for_opponent_view(line_idx as GameConstants.Line)
			var slot_count: int = field_manager.get_slots_for_side_line(place_side, line).size()
			slot_index = _mirror_slot_index_for_opponent_view(slot_index, slot_count)

		var card := _find_card_by_uuid(uuid)
		if card == null:
			_broadcast_place_failed("uuid_not_found")
			return
		if card.card_data:
			cost_total += int(card.card_data.setting_cost)

		var is_unit: bool = card.card_data != null and card.card_data.card_type == "Unit"
		var is_spell: bool = card.card_data != null and card.card_data.card_type == "Spell"
		var needs_lock: bool = (
			(is_unit and rules.require_same_line_unit)
			or (is_spell and rules.require_same_line_spell)
		)
		if needs_lock:
			if locked_line < 0:
				locked_line = int(line)
			elif locked_line != int(line):
				_broadcast_place_failed("line_mismatch")
				return

		var slot: CardSlot = field_manager.get_slot_for_side_line_index(place_side, line, slot_index)
		if slot == null or (not slot.is_empty() and slot.card_in_slot != card):
			_broadcast_place_failed("slot_unavailable")
			return
		resolved.append({"card": card, "slot": slot})

	var perm := int(placement_permission.get(place_side, 0))
	if cost_total > perm:
		_broadcast_place_failed("cannot_afford")
		return

	var cards: Array = []
	for item in resolved:
		var card: Node2D = item["card"]
		var slot: CardSlot = item["slot"]
		hand.remove_card_from_hand(card)
		await _finalize_placed_card(
			card,
			place_side == GameConstants.Side.PLAYER,
			_play_setting_hidden_flip()
		)
		await _place_card_with_move_fx(card, slot)
		cards.append(card)

	await _confirm_side_placement_multi(cards)


func enqueue_network_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	if event_type in [
		NetworkConstants.EVENT_PLACE_CARD,
		NetworkConstants.EVENT_PLACE_FAILED,
		NetworkConstants.EVENT_REVEAL_PAIR,
		NetworkConstants.EVENT_TURN_CHANGED,
		NetworkConstants.EVENT_EFFECT_WINDOW_START,
		NetworkConstants.EVENT_EFFECT_WINDOW_END,
		NetworkConstants.EVENT_EFFECT_DECISION_REQUEST,
		NetworkConstants.EVENT_EFFECT_RESULT,
	]:
		_mp_place_log("event_enqueue", "%s payload=%s" % [event_type, str(event)])
	elif event_type == NetworkConstants.EVENT_DRAW_RESULT:
		_mp_draw_log("event_enqueue", _summarize_draw_event(event))
	_net_event_queue.append(event)
	if not _net_event_busy:
		_drain_network_events()


func _drain_network_events() -> void:
	_net_event_busy = true
	_run_network_event_queue()


func _run_network_event_queue() -> void:
	while not _net_event_queue.is_empty():
		var event: Dictionary = _net_event_queue.pop_front()
		await apply_network_event(event)
	_net_event_busy = false


func apply_network_event(event: Dictionary) -> void:
	if _is_authoritative():
		return

	var event_type := String(event.get("type", ""))
	if event_type in [
		NetworkConstants.EVENT_PLACE_CARD,
		NetworkConstants.EVENT_PLACE_FAILED,
		NetworkConstants.EVENT_REVEAL_PAIR,
		NetworkConstants.EVENT_TURN_CHANGED,
	]:
		_mp_place_log("event_apply_start", "%s queue_left=%d" % [event_type, _net_event_queue.size()])
	elif event_type == NetworkConstants.EVENT_DRAW_RESULT:
		_mp_draw_log("event_apply_start", _summarize_draw_event(event))

	match event_type:
		NetworkConstants.EVENT_GAME_START:
			_apply_network_game_start(event)
		NetworkConstants.EVENT_DRAW_RESULT:
			await _apply_network_draw_result(event)
		NetworkConstants.EVENT_TURN_CHANGED:
			await _apply_network_turn_changed(event)
		NetworkConstants.EVENT_PLACE_CARD:
			await _apply_network_place_card(event)
		NetworkConstants.EVENT_PLACE_FAILED:
			_apply_network_place_failed(event)
		NetworkConstants.EVENT_REVEAL_PAIR:
			await _apply_network_reveal_pair(event)
		NetworkConstants.EVENT_BATTLE_RESULT:
			await _apply_network_battle_result(event)
		NetworkConstants.EVENT_CLEAN_DONE:
			await _apply_network_clean_done(event)
		NetworkConstants.EVENT_GAME_OVER:
			_apply_network_game_over(event)
		NetworkConstants.EVENT_EFFECT_WINDOW_START:
			await _apply_network_effect_window_start(event)
		NetworkConstants.EVENT_EFFECT_WINDOW_END:
			_apply_network_effect_window_end(event)
		NetworkConstants.EVENT_EFFECT_DECISION_REQUEST:
			await _apply_network_effect_decision_request(event)
		NetworkConstants.EVENT_EFFECT_RESULT:
			await _apply_network_effect_result(event)


func _apply_network_game_start(event: Dictionary) -> void:
	var session := _session()
	session.my_network_side = event.get("mySide", int(GameConstants.Side.OPPONENT)) as GameConstants.Side
	first_player = session.network_side_to_local(int(event.get("firstPlayer", 0)))
	last_round_winner = first_player
	session.effects_enabled = event.get("effectsEnabled", false)
	session.sync_local_display_name()
	var opp_name := String(event.get("opponentDisplayName", "")).strip_edges()
	var opp_icon := String(event.get("opponentProfileIconId", ""))
	var opp_back := String(event.get("opponentCardBackId", ""))
	var opp_field := String(event.get("opponentFieldId", ""))
	session.apply_opponent_profile_from_network(opp_name, opp_icon, opp_back, opp_field)
	player_deck.init_match_from_entries(event.get("playerDeck", []))
	opponent_deck.init_match_from_entries(event.get("opponentDeck", []))
	player_deck.take_cards_to_life(GameConstants.LIFE_START_COUNT)
	opponent_deck.take_cards_to_life(GameConstants.LIFE_START_COUNT)
	_update_life_ui()
	var game_ui := get_node_or_null("../GameUILayer")
	if game_ui and game_ui.has_method("refresh_player_id_labels"):
		game_ui.refresh_player_id_labels()


func _apply_network_draw_result(event: Dictionary) -> void:
	current_phase = GameConstants.Phase.DRAW
	_processing = true
	_update_phase_button()
	await _show_phase_toast("~ draw phase ~")

	var self_draw := _resolve_draw_packet(event, "selfDraw", "self")
	if not _draw_packet_usable(self_draw):
		self_draw = {
			"steps": _legacy_draw_entries_to_steps(event.get("selfDrawn", [])),
			"hand_limit": player_deck.hand_limit,
		}

	var opponent_draw := _resolve_draw_packet(event, "opponentDraw", "opponent")
	if not _draw_packet_usable(opponent_draw):
		var legacy_count: int = int(event.get("opponentDrawCount", 0))
		opponent_draw = {"steps": _legacy_hidden_draw_steps(legacy_count)}

	_mp_draw_log(
		"draw_apply_before",
		"self limit=%d entries=%d hand=%d | opp limit=%d entries=%d hand=%d"
		% [
			int(self_draw.get("hand_limit", player_deck.hand_limit)),
			_draw_entry_count(self_draw),
			player_hand.get_hand_size(),
			int(opponent_draw.get("hand_limit", opponent_deck.hand_limit)),
			_draw_entry_count(opponent_draw),
			opponent_hand.get_hand_size(),
		]
	)

	player_deck.apply_network_draw_state(self_draw, true)
	opponent_deck.apply_network_draw_state(opponent_draw, false)

	_mp_draw_log(
		"draw_apply_after",
		"self limit=%d hand=%d | opp limit=%d hand=%d"
		% [
			player_deck.hand_limit,
			player_hand.get_hand_size(),
			opponent_deck.hand_limit,
			opponent_hand.get_hand_size(),
		]
	)

	_update_life_ui()
	var expected_hand := _draw_entry_count(self_draw)
	if player_hand.get_hand_size() == 0 and expected_hand > 0:
		push_warning(
			"[MP-DRAW] client hand empty after draw apply (expected entries=%d)" % expected_hand
		)
		_mp_draw_log("draw_guard", "blocking enter_setting — hand empty, entries=%d" % expected_hand)
		return
	_match_ready = true
	await enter_setting_phase()


func _resolve_draw_packet(event: Dictionary, nested_key: String, flat_prefix: String) -> Dictionary:
	var packet: Dictionary = {}
	var nested = event.get(nested_key, {})
	if nested is Dictionary and not nested.is_empty():
		packet = nested.duplicate(true)

	var flat_keys := {
		"hand_limit": flat_prefix + "HandLimit",
		"hand_entries": flat_prefix + "HandEntries",
		"deck_remaining": flat_prefix + "DeckRemaining",
		"graveyard_remaining": flat_prefix + "GraveyardRemaining",
		"life_remaining": flat_prefix + "LifeRemaining",
		"start_hand_size": flat_prefix + "StartHandSize",
		"drawn_entries": flat_prefix + "DrawnEntries",
		"life_transfers": flat_prefix + "LifeTransfers",
	}
	for key in flat_keys:
		var event_key: String = flat_keys[key]
		if event.has(event_key):
			packet[key] = event[event_key]
	return packet


func _draw_packet_usable(packet: Dictionary) -> bool:
	return (
		packet.has("hand_entries")
		or packet.has("drawn_entries")
		or packet.has("life_transfers")
		or not packet.get("steps", []).is_empty()
	)


func _draw_entry_count(packet: Dictionary) -> int:
	if packet.has("hand_entries"):
		return packet.get("hand_entries", []).size()
	return int(packet.get("drawn_entries", []).size()) + int(packet.get("life_transfers", []).size())


func _summarize_draw_event(event: Dictionary) -> String:
	var self_draw := _resolve_draw_packet(event, "selfDraw", "self")
	var opponent_draw := _resolve_draw_packet(event, "opponentDraw", "opponent")
	return (
		"nested_self=%d nested_opp=%d | self limit=%d entries=%d | opp limit=%d entries=%d | flat_keys=%s"
		% [
			event.get("selfDraw", {}).size() if event.get("selfDraw", {}) is Dictionary else -1,
			event.get("opponentDraw", {}).size() if event.get("opponentDraw", {}) is Dictionary else -1,
			int(self_draw.get("hand_limit", -1)),
			_draw_entry_count(self_draw),
			int(opponent_draw.get("hand_limit", -1)),
			_draw_entry_count(opponent_draw),
			str(event.keys()),
		]
	)


func _legacy_draw_entries_to_steps(entries: Array) -> Array:
	var steps: Array = []
	for entry in entries:
		steps.append({
			"type": "draw",
			"name": String(entry.get("name", "")),
			"uuid": int(entry.get("uuid", 0)),
			"rarity": int(entry.get("rarity", CardRarity.Tier.N)),
		})
	return steps


func _legacy_hidden_draw_steps(count: int) -> Array:
	var steps: Array = []
	for _i in range(count):
		steps.append({"type": "draw", "name": "", "uuid": 0})
	return steps


func _apply_network_turn_changed(event: Dictionary) -> void:
	var session := _session()
	active_side = session.network_side_to_local(int(event.get("activeSide", 0)))
	placements_remaining = {
		GameConstants.Side.PLAYER: int(event.get("playerPlacements", GameConstants.SETTING_PLACEMENTS)),
		GameConstants.Side.OPPONENT: int(event.get("opponentPlacements", GameConstants.SETTING_PLACEMENTS)),
	}
	setting_turn_index = int(event.get("settingTurnIndex", 0))
	_apply_network_permissions(event, false)
	_awaiting_turn_sync = false
	_mp_place_log(
		"turn_changed",
		"active_side=%d turn=%d pending=%s ack=%s"
		% [
			int(active_side),
			setting_turn_index,
			_mp_card_label(player_pending_card),
			_mp_card_label(_awaiting_ack_card),
		]
	)
	# 자신 턴이면 토스트 동안 조작 차단. ack 대기 중이면 잠금 유지.
	if not _awaiting_remote_place_ack:
		_processing = true
		_update_phase_button()
		if active_side == GameConstants.Side.PLAYER:
			await _show_own_setting_phase_toast()
		_processing = false
	_update_phase_button()


func _apply_network_place_card(event: Dictionary) -> void:
	var session := _session()
	var net_side: int = int(event.get("side", 0))
	var placements: Array = event.get("placements", [])
	var is_pass := bool(event.get("pass", false))
	if placements.is_empty() and not is_pass and int(event.get("uuid", 0)) != 0:
		placements = [{
			"uuid": int(event.get("uuid", 0)),
			"line": int(event.get("line", 0)),
			"slotIndex": int(event.get("slotIndex", 0)),
			"cardName": String(event.get("cardName", "")),
		}]

	_mp_place_log(
		"place_card_recv",
		"net_side=%d pass=%s placements=%d did_flip=%s"
		% [net_side, str(is_pass), placements.size(), str(event.get("didFlip", false))]
	)

	var last_card: Node2D = null
	if not is_pass:
		for entry in placements:
			if not entry is Dictionary:
				continue
			var uuid: int = int(entry.get("uuid", 0))
			var raw_line: int = int(entry.get("line", 0))
			var raw_slot_index: int = int(entry.get("slotIndex", 0))
			var coords := resolve_placement_coords_from_network(net_side, raw_line, raw_slot_index)
			var local_side: GameConstants.Side = coords.local_side
			var line: GameConstants.Line = coords.line as GameConstants.Line
			var slot_index: int = coords.slot_index
			var slot: CardSlot = field_manager.get_slot_for_side_line_index(local_side, line, slot_index)
			var card_event := {
				"uuid": uuid,
				"cardName": String(entry.get("cardName", "")),
				"rarity": int(entry.get("rarity", CardRarity.Tier.N)),
			}
			var card := _resolve_placement_card(card_event, local_side)
			if card == null and slot and slot.card_in_slot and slot.card_in_slot.network_uuid == uuid:
				card = slot.card_in_slot
			if card == null or slot == null:
				push_warning(
					"PhaseManager: PLACE_CARD failed uuid=%d line=%d local_side=%d slot=%d"
					% [uuid, int(line), int(local_side), slot_index]
				)
				_rollback_failed_local_place()
				return

			var already_committed: bool = false
			if card and card.card_slot_card_is_in is CardSlot:
				var committed_slot: CardSlot = card.card_slot_card_is_in
				already_committed = (
					committed_slot.side == local_side
					and committed_slot.line == line
					and field_manager.get_slot_index_for_slot(committed_slot) == slot_index
					and card.is_locked
				)

			if local_side == GameConstants.Side.PLAYER:
				_remove_card_from_hand_by_uuid(player_hand, uuid, card)
			else:
				_remove_card_from_hand_by_uuid(opponent_hand, uuid, card)

			if not already_committed:
				# 권위 didFlip이면 바로 OPEN — flip_back 생략.
				var play_flip := not bool(event.get("didFlip", false))
				await _finalize_placed_card(card, false, play_flip)
				await _place_card_with_move_fx(card, slot)
				if card:
					card.is_locked = true
					CardHelpers.disable_interaction(card)

			if card and card not in round_pair_cards:
				round_pair_cards.append(card)
			last_card = card

	pending_cards.clear()
	player_pending_card = null
	_locked_line = -1
	_awaiting_ack_card = null

	var placed_local := session.network_side_to_local(net_side)
	placements_remaining[placed_local] = int(
		event.get("placementsRemaining", placements_remaining.get(placed_local, 0))
	)
	setting_turn_index = int(event.get("settingTurnIndex", setting_turn_index))
	active_side = session.network_side_to_local(int(event.get("activeSide", 0)))
	_apply_network_permissions(event)

	if event.get("didFlip", false):
		_mp_place_log("place_card_flip", "flip_uuids=%s" % str(event.get("flipUuids", [])))
		await _apply_flip_uuids(event.get("flipUuids", []))
		round_pair_cards.clear()

	_mp_place_log(
		"place_card_done",
		"card=%s active_side=%d turn=%d pair_size=%d"
		% [_mp_card_label(last_card), int(active_side), setting_turn_index, round_pair_cards.size()]
	)

	_update_phase_button()
	_update_line_power_labels()
	_processing = false
	_awaiting_remote_place_ack = false
	_awaiting_ack_card = null
	_awaiting_turn_sync = false

	if _all_placements_done():
		return
	elif active_side == GameConstants.Side.PLAYER:
		_update_phase_button()


## PLACE_CARD(권위 좌표)는 remap=true, TURN_CHANGED(Dedicated는 seat remap됨)는 false.
func _apply_network_permissions(event: Dictionary, remap_from_net: bool = true) -> void:
	if not event.has("playerPermission") and not event.has("opponentPermission"):
		return
	var p_perm := int(event.get("playerPermission", 0))
	var o_perm := int(event.get("opponentPermission", 0))
	if remap_from_net:
		var session := _session()
		placement_permission[session.network_side_to_local(int(GameConstants.Side.PLAYER))] = p_perm
		placement_permission[session.network_side_to_local(int(GameConstants.Side.OPPONENT))] = o_perm
	else:
		placement_permission[GameConstants.Side.PLAYER] = p_perm
		placement_permission[GameConstants.Side.OPPONENT] = o_perm


func _apply_network_place_failed(event: Dictionary) -> void:
	push_warning("PhaseManager: placement rejected — %s" % String(event.get("reason", "")))
	_mp_place_log("place_failed_recv", "reason=%s pending=%s ack=%s" % [
		String(event.get("reason", "")),
		_mp_card_label(player_pending_card),
		_mp_card_label(_awaiting_ack_card),
	])
	_rollback_failed_local_place()


func _rollback_failed_local_place() -> void:
	var cards: Array = []
	if not pending_cards.is_empty():
		cards = pending_cards.duplicate()
	elif player_pending_card:
		cards = [player_pending_card]
	elif _awaiting_ack_card:
		cards = [_awaiting_ack_card]
	_mp_place_log("rollback", "before count=%d" % cards.size())
	_awaiting_ack_card = null
	for card in cards:
		if card == null or not is_instance_valid(card):
			continue
		card.is_locked = false
		CardHelpers.enable_interaction(card)
		if card.card_slot_card_is_in:
			card.apply_setting_preview()
		else:
			_return_card_to_hand(card)
	# pending 유지(미리보기 복구) — 실패 시 다시 확정 가능
	if cards.is_empty():
		player_pending_card = null
	elif cards.size() == 1:
		player_pending_card = cards[0]
		if cards[0] not in pending_cards:
			pending_cards = [cards[0]]
	_processing = false
	_awaiting_remote_place_ack = false
	_update_phase_button()
	_update_line_power_labels()


func _finalize_placed_card(
	card: Node2D,
	clear_pending: bool = true,
	play_flip: bool = true
) -> void:
	if card == null:
		return
	_mp_place_log(
		"finalize",
		"before %s clear_pending=%s play_flip=%s"
		% [_mp_card_label(card), str(clear_pending), str(play_flip)]
	)
	_prepare_finalize_placed_card(card, clear_pending)
	await CardHelpers.await_setting_hidden(card, play_flip)
	CardHelpers.disable_interaction(card)
	_mp_place_log("finalize", "after %s" % _mp_card_label(card))


func _prepare_finalize_placed_card(card: Node2D, clear_pending: bool = true) -> void:
	var card_manager: Node = get_node_or_null("../CardManager")
	if card_manager and card_manager.has_method("clear_hover_state"):
		card_manager.clear_hover_state(card)
	else:
		card.scale = Vector2(0.4, 0.4)
		if card.z_index == 2:
			card.z_index = 1
	card.is_locked = true
	if clear_pending and card == player_pending_card:
		player_pending_card = null


func _finalize_placed_cards(
	cards: Array,
	clear_pending: bool = false,
	play_flip: bool = true
) -> void:
	var valid: Array = []
	for card in cards:
		if card == null or not is_instance_valid(card):
			continue
		_prepare_finalize_placed_card(card, clear_pending)
		valid.append(card)
	await CardHelpers.await_setting_hidden_all(valid, play_flip)
	for card in valid:
		CardHelpers.disable_interaction(card)


## 이번 확정이 페어 OPEN 플립을 바로 트리거하면 true (후공 배치).
func _will_open_flip_after_this_place() -> bool:
	return setting_turn_index % 2 == 1


## 페어 OPEN이 바로 이어지면 flip_back 생략.
func _play_setting_hidden_flip() -> bool:
	return not _will_open_flip_after_this_place()


## 확정 배치: 슬롯 점유 후 from→slot을 await. 착지 FX는 배치 직후.
func _place_card_with_move_fx(card: Node2D, slot: CardSlot) -> void:
	if card == null or slot == null:
		return
	var from := card.global_position
	field_manager.place_card_on_slot(card, slot)
	MatchVfx.play_slot_land(slot.global_position, "place")
	if not MatchVfx.is_active():
		return
	card.global_position = from
	var params := MatchVfx.default_field_params(MatchVfx.FACE_KEEP)
	params["from"] = from
	params["to"] = slot.global_position
	await MatchVfx.await_card_move(card, params)


## 세팅 pending: 프리뷰 유지 · 이동은 play(비대기). 착지 FX는 배치 직후.
func _place_pending_with_move_fx(card: Node2D, slot: CardSlot) -> void:
	if card == null or slot == null:
		return
	var from := card.global_position
	field_manager.place_card_on_slot(card, slot)
	card.global_position = from
	card.apply_setting_preview()
	MatchVfx.play_slot_land(slot.global_position, "place")
	if not MatchVfx.is_active():
		card.global_position = slot.global_position
		return
	var params := MatchVfx.default_field_params(MatchVfx.FACE_KEEP)
	params["from"] = from
	params["to"] = slot.global_position
	MatchVfx.play_card_move(card, params)


func _mirror_line_for_opponent_view(line: GameConstants.Line) -> GameConstants.Line:
	match line:
		GameConstants.Line.LEFT:
			return GameConstants.Line.RIGHT
		GameConstants.Line.RIGHT:
			return GameConstants.Line.LEFT
		_:
			return line


func _broadcast_place_failed(reason: String) -> void:
	if not _is_online() or not _is_authoritative():
		return
	_session().broadcast_event({
		"type": NetworkConstants.EVENT_PLACE_FAILED,
		"reason": reason,
	})


func is_match_ready() -> bool:
	return _match_ready or not _is_online()


func _apply_network_reveal_pair(event: Dictionary) -> void:
	var uuids: Array = event.get("uuids", [])
	_mp_place_log("reveal_pair_recv", "uuids=%s" % str(uuids))
	_processing = true
	await _apply_flip_uuids(uuids)
	_update_line_power_labels()
	_processing = false


func _apply_network_battle_result(event: Dictionary) -> void:
	current_phase = GameConstants.Phase.BATTLE
	_update_phase_button()

	var session := _session()
	var round_winner := session.network_side_to_local(int(event.get("roundWinner", 0)))

	if event.get("gameOver", false):
		enter_game_over(round_winner)
		return

	var life_side := session.network_side_to_local(int(event.get("lifeSide", 0)))
	var life_name := String(event.get("lifeCardName", ""))
	var life_uuid := int(event.get("lifeUuid", 0))
	var loser_deck: DeckZone = opponent_deck if life_side == GameConstants.Side.OPPONENT else player_deck
	var loser_hand: Node = opponent_hand if life_side == GameConstants.Side.OPPONENT else player_hand
	var already_in_hand := false
	if life_uuid > 0:
		for card in loser_hand.get_hand_cards():
			if card.network_uuid == life_uuid:
				already_in_hand = true
				break
	if not already_in_hand:
		var life_pop := loser_deck.pop_life_card_for_hand()
		var life_rarity := int(event.get("lifeRarity", life_pop.get("rarity", CardRarity.Tier.N)))
		var life_card_id := int(event.get("lifeCardId", life_pop.get("cardId", 0)))
		var reveal_in_hand := life_side == GameConstants.Side.PLAYER
		var new_card: Node2D
		if life_card_id > 0:
			new_card = loser_deck.spawn_card_by_id(life_card_id, reveal_in_hand, life_uuid, life_rarity)
		else:
			new_card = loser_deck.spawn_card_by_name(life_name, reveal_in_hand, life_uuid, life_rarity)
		loser_deck._place_card_at_life_for_hand_fx(new_card)
		loser_hand.add_card_to_hand(new_card, DeckZone.CARD_DRAW_SPEED)
		_mp_draw_log(
			"battle_life_to_hand",
			"side=%d name=%s uuid=%d rarity=%d already_in_hand=false"
			% [int(life_side), life_name, life_uuid, life_rarity]
		)
	_update_life_ui()

	last_round_winner = round_winner
	await wait(PHASE_PAUSE)


func _apply_network_clean_done(event: Dictionary) -> void:
	current_phase = GameConstants.Phase.CLEAN
	_update_phase_button()
	await field_manager.clear_field_to_graveyard(player_deck, opponent_deck)
	var session := _session()
	first_player = session.network_side_to_local(int(event.get("firstPlayer", 0)))
	last_round_winner = first_player
	_reset_line_power_labels()
	await wait(PHASE_PAUSE)


func _apply_network_game_over(event: Dictionary) -> void:
	var session := _session()
	var winner := session.network_side_to_local(int(event.get("winner", 0)))
	var reason := String(event.get("reason", ""))
	enter_game_over(winner, reason)


## 온라인 권위 세션에 DRAW_RESULT 송신을 위임한다 (Host 스왑 / Dedicated per-peer는 세션 책임).
func _dispatch_draw_result(player_draw: Dictionary, opponent_draw: Dictionary) -> void:
	var session := _session()
	if not (session is OnlineAuthoritySessionBase):
		return
	(session as OnlineAuthoritySessionBase).dispatch_draw_result(player_draw, opponent_draw)


## 온라인 권위 세션에 TURN_CHANGED 송신을 위임한다. active_side·placements·배치권 전달.
func _dispatch_turn_changed() -> void:
	var session := _session()
	if not (session is OnlineAuthoritySessionBase):
		return
	(session as OnlineAuthoritySessionBase).dispatch_turn_changed(
		active_side,
		placements_remaining,
		setting_turn_index,
		placement_permission if _is_rules_mode() else {}
	)


func _line_for_network(placed_side: GameConstants.Side, local_line: GameConstants.Line) -> int:
	# 프로토콜 line = 배치한 플레이어 시점. 호스트 OPPONENT(클라 배치)는 L/R 미러 역변환.
	if placed_side == GameConstants.Side.OPPONENT:
		return int(_mirror_line_for_opponent_view(local_line))
	return int(local_line)


## PLACE_CARD 수신: 상대 필드만 L/R·슬롯 미러 (자기 배치 echo는 wire가 이미 로컬 좌표).
func resolve_placement_coords_from_network(
	net_side: int,
	raw_line: int,
	raw_slot_index: int
) -> Dictionary:
	var session := _session()
	var local_side := session.network_side_to_local(net_side)
	var line: GameConstants.Line = raw_line as GameConstants.Line
	var slot_index: int = raw_slot_index
	if local_side == GameConstants.Side.OPPONENT:
		line = _mirror_line_for_opponent_view(line)
		var slot_count: int = field_manager.get_slots_for_side_line(local_side, line).size()
		slot_index = _mirror_slot_index_for_opponent_view(slot_index, slot_count)
	return {
		"local_side": local_side,
		"line": line,
		"slot_index": slot_index,
	}


## 소생 슬롯·EFFECT_RESULT 필드 MOVE — PLACE_CARD와 동일한 L/R 규칙.
func resolve_effect_field_coords_from_network(
	net_side: int,
	raw_line: int,
	raw_slot_index: int
) -> Dictionary:
	return resolve_placement_coords_from_network(net_side, raw_line, raw_slot_index)


func _authority_field_view_for_slot(slot: CardSlot) -> Dictionary:
	var field_side: GameConstants.Side = slot.side
	var line: GameConstants.Line = slot.line
	var slot_index: int = field_manager.get_slot_index_for_slot(slot)
	if _is_authoritative():
		return {"side": field_side, "line": line, "slot_index": slot_index}
	# 클라 로컬 → 호스트 권한 좌표 (apply_remote_place_intent 와 동일)
	var slot_count: int = field_manager.get_slots_for_side_line(field_side, line).size()
	if field_side == GameConstants.Side.PLAYER:
		return {
			"side": GameConstants.Side.OPPONENT,
			"line": _mirror_line_for_opponent_view(line),
			"slot_index": _mirror_slot_index_for_opponent_view(slot_index, slot_count),
		}
	return {
		"side": GameConstants.Side.PLAYER,
		"line": _mirror_line_for_opponent_view(line),
		"slot_index": _mirror_slot_index_for_opponent_view(slot_index, slot_count),
	}


func resolve_field_slot_from_network(
	net_side: int,
	raw_line: int,
	raw_slot_index: int
) -> CardSlot:
	var coords := resolve_effect_field_coords_from_network(net_side, raw_line, raw_slot_index)
	return field_manager.get_slot_for_side_line_index(
		coords.local_side,
		coords.line as GameConstants.Line,
		coords.slot_index
	)


func encode_field_slot_for_network(slot: CardSlot) -> Dictionary:
	var session := _session()
	var auth_view := _authority_field_view_for_slot(slot)
	var auth_side: GameConstants.Side = auth_view.side
	var auth_line: GameConstants.Line = auth_view.line
	var auth_slot_index: int = auth_view.slot_index
	var net_side := session.local_side_to_network(
		auth_side if _is_authoritative() else slot.side
	)
	var line_out := _line_for_network(auth_side, auth_line)
	var slot_idx := _slot_index_for_network(auth_side, auth_line, auth_slot_index)
	return {
		"side": net_side,
		"line": line_out,
		"slotIndex": slot_idx,
	}


func _mirror_slot_index_for_opponent_view(slot_index: int, slot_count: int) -> int:
	if slot_count <= 1:
		return slot_index
	return (slot_count - 1) - slot_index


func _slot_index_for_network(
	placed_side: GameConstants.Side,
	line: GameConstants.Line,
	local_slot_index: int
) -> int:
	var slot_count: int = field_manager.get_slots_for_side_line(placed_side, line).size()
	if placed_side == GameConstants.Side.OPPONENT:
		return _mirror_slot_index_for_opponent_view(local_slot_index, slot_count)
	return local_slot_index


func _apply_flip_uuids(uuids: Array) -> void:
	var flipped: Array = []
	for uuid_value in uuids:
		var flip_uuid := int(uuid_value)
		var flip_card := _find_card_by_uuid(flip_uuid)
		if flip_card:
			_mp_place_log(
				"flip_uuid",
				"uuid=%d before=%s" % [flip_uuid, _mp_card_label(flip_card)]
			)
			flip_card.reveal()
			MatchVfx.play_slot_land_after_flip(flip_card, "open")
			flipped.append(flip_card)
			_mp_place_log("flip_uuid", "uuid=%d after=%s" % [flip_uuid, _mp_card_label(flip_card)])
		else:
			_mp_place_log("flip_uuid_missing", "uuid=%d not found" % flip_uuid)
	await CardHoverTilt.await_open_reveal_fx(flipped, field_manager)
	# 호스트 _flip_round_pair는 reveal 직후 schedule — 클라도 동일해야 PASSIVE(이즈라엘 등) 반영
	if _effects_enabled() and effect_manager:
		effect_manager.schedule_passive_refresh()


func _broadcast_place_card(
	card: Node2D,
	placed_side: GameConstants.Side,
	did_flip: bool,
	flip_cards: Array = []
) -> void:
	var cards: Array = []
	if card:
		cards.append(card)
	_broadcast_place_cards_multi(cards, placed_side, did_flip, flip_cards)


## PLACE_CARD A1: placements[] / pass + 배치권 동기화.
func _broadcast_place_cards_multi(
	cards: Array,
	placed_side: GameConstants.Side,
	did_flip: bool,
	flip_cards: Array = []
) -> void:
	var session := _session()
	var placements_net: Array = []
	for card in cards:
		if card == null or not is_instance_valid(card):
			continue
		if card.card_slot_card_is_in == null:
			continue
		var placed_slot: CardSlot = card.card_slot_card_is_in
		var _bcd: CardData = card.get("card_data") as CardData
		var _bcid: int = int(_bcd.id) if _bcd != null else 0
		placements_net.append({
			"uuid": int(card.network_uuid),
			"line": _line_for_network(placed_side, placed_slot.line),
			"slotIndex": _slot_index_for_network(
				placed_side,
				placed_slot.line,
				field_manager.get_slot_index_for_slot(placed_slot)
			),
			"cardName": String(card.card_name),
			"cardId": _bcid,
			"rarity": int(card.get("instance_rarity") if card.get("instance_rarity") != null else CardRarity.Tier.N),
		})

	var net_side := session.local_side_to_network(placed_side)
	var first_uuid := 0
	var first_line := 0
	var first_slot := 0
	var first_name := ""
	if not placements_net.is_empty():
		var first: Dictionary = placements_net[0]
		first_uuid = int(first.get("uuid", 0))
		first_line = int(first.get("line", 0))
		first_slot = int(first.get("slotIndex", 0))
		first_name = String(first.get("cardName", ""))

	var payload := {
		"type": NetworkConstants.EVENT_PLACE_CARD,
		"side": net_side,
		"line": first_line,
		"slotIndex": first_slot,
		"uuid": first_uuid,
		"cardName": first_name,
		"pass": placements_net.is_empty(),
		"placements": placements_net,
		"placementsRemaining": placements_remaining[placed_side],
		"settingTurnIndex": setting_turn_index,
		"activeSide": session.local_side_to_network(active_side),
		"didFlip": did_flip,
		"playerPermission": int(placement_permission.get(GameConstants.Side.PLAYER, 0)),
		"opponentPermission": int(placement_permission.get(GameConstants.Side.OPPONENT, 0)),
	}
	if did_flip:
		var flip_uuids: Array = []
		for flip_card in flip_cards:
			if flip_card:
				flip_uuids.append(flip_card.network_uuid)
		payload["flipUuids"] = flip_uuids
	_mp_place_log("broadcast_place_card", "payload=%s" % str(payload))
	session.broadcast_event(payload)


func _broadcast_reveal_pair(cards: Array) -> void:
	var uuids: Array = []
	for c in cards:
		if c:
			uuids.append(c.network_uuid)
	_mp_place_log("broadcast_reveal_pair", "uuids=%s" % str(uuids))
	_session().broadcast_event({
		"type": NetworkConstants.EVENT_REVEAL_PAIR,
		"uuids": uuids,
	})


func _broadcast_battle_result(
	result: Dictionary,
	round_winner: GameConstants.Side,
	round_loser: GameConstants.Side,
	life_card_name: String,
	life_card: Node2D
) -> void:
	var session := _session()
	var _lc_cid := 0
	if life_card != null:
		var _lc_cd: CardData = life_card.get("card_data") as CardData
		if _lc_cd != null and int(_lc_cd.id) > 0:
			_lc_cid = int(_lc_cd.id)
		elif not life_card_name.is_empty():
			_lc_cid = CardRegistry.name_to_id(life_card_name)
	_session().broadcast_event({
		"type": NetworkConstants.EVENT_BATTLE_RESULT,
		"roundWinner": session.local_side_to_network(round_winner),
		"lifeSide": session.local_side_to_network(round_loser),
		"lifeCardName": life_card_name,
		"lifeCardId": _lc_cid,
		"lifeUuid": life_card.network_uuid if life_card else 0,
		"lifeRarity": int(
			life_card.get("instance_rarity") if life_card and life_card.get("instance_rarity") != null
			else CardRarity.Tier.N
		),
		"gameOver": false,
		"lineResults": result.get("line_results", []),
	})


func _broadcast_clean_done() -> void:
	var session := _session()
	session.broadcast_event({
		"type": NetworkConstants.EVENT_CLEAN_DONE,
		"firstPlayer": session.local_side_to_network(first_player),
	})


func _broadcast_game_over(winner: GameConstants.Side) -> void:
	var session := _session()
	session.broadcast_event({
		"type": NetworkConstants.EVENT_GAME_OVER,
		"winner": session.local_side_to_network(winner),
	})


func _remove_card_from_hand_by_uuid(hand: Node, uuid: int, placed_card: Node2D) -> void:
	if uuid <= 0:
		if placed_card and hand.get_hand_cards().has(placed_card):
			hand.remove_card_from_hand(placed_card)
		return
	for c in hand.get_hand_cards().duplicate():
		if not is_instance_valid(c):
			continue
		if c.network_uuid != uuid:
			continue
		hand.remove_card_from_hand(c)
		if c != placed_card:
			c.queue_free()


func _resolve_placement_card(event: Dictionary, local_side: GameConstants.Side) -> Node2D:
	var uuid := int(event.get("uuid", 0))
	if uuid > 0:
		var existing := _find_card_by_uuid(uuid)
		if existing:
			return existing
	var card_id := int(event.get("cardId", 0))
	var card_name := String(event.get("cardName", ""))
	if card_id <= 0:
		card_id = CardRegistry.name_to_id(card_name)
	if (card_id <= 0 and card_name.is_empty()) or uuid <= 0:
		return null
	var deck: DeckZone = player_deck if local_side == GameConstants.Side.PLAYER else opponent_deck
	var reveal_in_hand := local_side == GameConstants.Side.PLAYER
	var rarity := clampi(int(event.get("rarity", CardRarity.Tier.N)), CardRarity.Tier.N, CardRarity.Tier.UR)
	var spawned: Node2D
	if card_id > 0:
		spawned = deck.spawn_card_by_id(card_id, reveal_in_hand, uuid, rarity)
	else:
		spawned = deck.spawn_card_by_name(card_name, reveal_in_hand, uuid, rarity)
	if spawned:
		_mp_place_log(
			"place_card_spawn_fallback",
			"side=%d name=%s cardId=%d uuid=%d rarity=%d" % [int(local_side), card_name, card_id, uuid, rarity]
		)
	return spawned


func _find_card_by_uuid(uuid: int) -> Node2D:
	if uuid <= 0:
		return null
	for card in player_hand.get_hand_cards():
		if card.network_uuid == uuid:
			return card
	for card in opponent_hand.get_hand_cards():
		if card.network_uuid == uuid:
			return card
	for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
		for line in [GameConstants.Line.LEFT, GameConstants.Line.CENTER, GameConstants.Line.RIGHT]:
			for slot in field_manager.get_slots_for_side_line(side, line):
				if slot.card_in_slot and slot.card_in_slot.network_uuid == uuid:
					return slot.card_in_slot
	var ctx: EffectContext = effect_manager.context if effect_manager else null
	if ctx:
		for card in ctx.reveal_select_nodes:
			if is_instance_valid(card) and int(card.network_uuid) == uuid:
				return card
		for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
			for card in ctx.graveyard_nodes.get(side, []):
				if is_instance_valid(card) and card.network_uuid == uuid:
					return card
		for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
			for line in [GameConstants.Line.LEFT, GameConstants.Line.CENTER, GameConstants.Line.RIGHT]:
				for slot in field_manager.get_slots_for_side_line(side, line):
					if slot.card_in_slot and slot.card_in_slot.get("stack_cards"):
						for stacked in slot.card_in_slot.stack_cards:
							if is_instance_valid(stacked) and stacked.network_uuid == uuid:
								return stacked
		for side in [GameConstants.Side.PLAYER, GameConstants.Side.OPPONENT]:
			for card in ctx.banishzone_nodes.get(side, []):
				if is_instance_valid(card) and card.network_uuid == uuid:
					return card
	return null


func deliver_effect_decision(intent: Dictionary) -> void:
	if effect_manager:
		effect_manager.deliver_effect_decision(intent)


func broadcast_effect_window_start(window_id: int, trigger: String, card_uuids: Array) -> void:
	if not _is_online() or not _is_authoritative():
		return
	_session().broadcast_event({
		"type": NetworkConstants.EVENT_EFFECT_WINDOW_START,
		"windowId": window_id,
		"trigger": trigger,
		"cardUuids": card_uuids,
	})


func broadcast_effect_window_end(window_id: int) -> void:
	if not _is_online() or not _is_authoritative():
		return
	_session().broadcast_event({
		"type": NetworkConstants.EVENT_EFFECT_WINDOW_END,
		"windowId": window_id,
	})


func broadcast_effect_decision_request(
	window_id: int,
	kind: String,
	owner_net_side: int,
	payload: Dictionary
) -> void:
	if not _is_online() or not _is_authoritative():
		return
	_session().broadcast_event({
		"type": NetworkConstants.EVENT_EFFECT_DECISION_REQUEST,
		"windowId": window_id,
		"kind": kind,
		"ownerSide": owner_net_side,
		"payload": payload,
	})


func broadcast_effect_result(window_id: int, changes: Array) -> void:
	if not _is_online() or not _is_authoritative():
		return
	_session().broadcast_event({
		"type": NetworkConstants.EVENT_EFFECT_RESULT,
		"windowId": window_id,
		"changes": changes,
	})


## Presenter: EFFECT_WINDOW_START — 공개만 하고 발동 FX는 ACTIVATE op에서 재생한다.
func _apply_network_effect_window_start(event: Dictionary) -> void:
	if effect_manager:
		await effect_manager.present_window_start(event)


func _apply_network_effect_window_end(event: Dictionary) -> void:
	if effect_manager:
		effect_manager.present_window_end(event)


func _apply_network_effect_decision_request(event: Dictionary) -> void:
	if effect_manager:
		await effect_manager.handle_decision_request(event)


func _apply_network_effect_result(event: Dictionary) -> void:
	var window_id := int(event.get("windowId", 0))
	var changes: Array = event.get("changes", [])
	if effect_manager:
		await effect_manager.apply_result_changes(changes, window_id)


func can_drag_card(card: Node2D) -> bool:
	if not is_match_ready():
		return false
	if _awaiting_turn_sync:
		return false
	if card == null or not card.has_method("init_from_data"):
		return false
	if _processing or _awaiting_remote_place_ack:
		return false
	if effect_manager and effect_manager.is_busy:
		return false
	if card.get("is_interactive") == false:
		return false
	if card.get("is_locked"):
		return false
	if current_phase != GameConstants.Phase.SETTING:
		return false
	if active_side != GameConstants.Side.PLAYER:
		return false
	if card.owner_side != GameConstants.Side.PLAYER:
		return false
	if card.card_slot_card_is_in != null:
		var is_pending := card == player_pending_card or (_is_rules_mode() and card in pending_cards)
		if not is_pending:
			return false
		if card.reveal_state != GameConstants.RevealState.SETTING_PREVIEW:
			return false
	return true


func can_return_to_hand(card: Node2D) -> bool:
	if not can_drag_card(card):
		return false
	if _is_rules_mode():
		return card in pending_cards
	return card == player_pending_card


## card 인자: 새 룰 모드에서 비용·라인 체크에 사용. 기존 경로는 null 가능.
func can_drop_on_slot(slot: CardSlot, card: Node2D = null) -> bool:
	if not is_match_ready():
		return false
	if current_phase != GameConstants.Phase.SETTING:
		return false
	if active_side != GameConstants.Side.PLAYER:
		return false
	if slot.side != GameConstants.Side.PLAYER:
		return false

	if _is_rules_mode() and card != null:
		var is_re_drag := card in pending_cards
		if is_re_drag:
			# 재배치: 빈 슬롯 또는 자신의 슬롯, + 라인 제약(다른 pending 기준)
			if not (slot.is_empty() or slot.card_in_slot == card):
				return false
			return _rules_check_line_for_slot(slot, card, card)
		else:
			# 새 카드: 슬롯 비어 있어야 함
			if not slot.is_empty():
				return false
			# 최대 장수 초과 확인
			if pending_cards.size() >= rules.max_cards_per_turn:
				return false
			# 비용 확인
			if not _rules_can_afford(card):
				return false
			# 라인 확인
			if not _rules_check_line_for_slot(slot, card):
				return false
			return true

	return slot.is_empty() or slot.card_in_slot == player_pending_card


func is_player_setting_turn() -> bool:
	return (
		is_match_ready()
		and not _awaiting_turn_sync
		and current_phase == GameConstants.Phase.SETTING
		and active_side == GameConstants.Side.PLAYER
	)


func wait(wait_time: float) -> void:
	battle_timer.wait_time = wait_time
	battle_timer.start()
	await battle_timer.timeout


## Dedicated/headless는 로컬 토스트 UI 없음 — 대기 스킵.
func _skips_phase_toast_ui() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	if _session() is ServerAuthoritySession:
		return true
	return false


## GameUILayer 페이즈 토스트. UI 없으면 no-op.
func _show_phase_toast(message: String) -> void:
	if _skips_phase_toast_ui():
		return
	var game_ui := get_node_or_null("../GameUILayer")
	if game_ui == null or not game_ui.has_method("show_phase_toast"):
		return
	await game_ui.show_phase_toast(message)


## 로컬 플레이어 SETTING 턴 시작 토스트. 동일 n/turns 중복 스킵(TURN 이중 송신).
func _show_own_setting_phase_toast() -> void:
	if active_side != GameConstants.Side.PLAYER:
		return
	var turns := rules.setting_turns_per_player if rules else GameConstants.SETTING_PLACEMENTS
	var remaining := int(placements_remaining.get(GameConstants.Side.PLAYER, 0))
	var n := clampi(turns - remaining + 1, 1, turns)
	var key := "%d/%d" % [n, turns]
	if key == _last_setting_toast_key:
		return
	_last_setting_toast_key = key
	await _show_phase_toast("~ Setting phase - %d/%d ~" % [n, turns])


func _phase_button_label() -> String:
	match current_phase:
		GameConstants.Phase.DRAW:
			return "Draw phase"
		GameConstants.Phase.SETTING:
			var turns := rules.setting_turns_per_player if rules else GameConstants.SETTING_PLACEMENTS
			var remaining := int(placements_remaining.get(active_side, 0))
			var n := turns - remaining + 1
			n = clampi(n, 1, turns)
			var base := "Setting phase %d/%d" % [n, turns]
			#if _is_rules_mode():
				#var perm := int(placement_permission.get(active_side, 0))
				#var used := _rules_pending_cost()
				#var pending_count := pending_cards.size()
				#base += "  [권:%d  사용:%d  배치:%d장]" % [perm, used, pending_count]
			return base
		GameConstants.Phase.BATTLE:
			return "Battle phase"
		GameConstants.Phase.CLEAN:
			return "Clean phase"
		GameConstants.Phase.GAME_OVER:
			return "Game over"
		_:
			return ""


func _update_phase_button() -> void:
	if phase_button == null:
		return
	if not is_match_ready():
		phase_button.visible = false
		phase_button.disabled = true
	else:
		phase_button.visible = true
		var can_confirm: bool
		if _is_rules_mode():
			# 새 룰: 패스 포함이므로 플레이어 턴이면 항상 활성
			can_confirm = (
				current_phase == GameConstants.Phase.SETTING
				and active_side == GameConstants.Side.PLAYER
				and not _processing
			)
		else:
			can_confirm = (
				current_phase == GameConstants.Phase.SETTING
				and active_side == GameConstants.Side.PLAYER
				and player_pending_card != null
			)
		phase_button.disabled = not can_confirm
		# 카드 올려둔 확정 가능 시 "턴 종료", 그 외(비활성·패스만 가능)는 페이즈 텍스트.
		if can_confirm and _has_pending_placement():
			phase_button.text = "턴 종료"
		else:
			phase_button.text = _phase_button_label()

	_refresh_placement_permission_display()

	var game_ui := $"../GameUILayer"
	if game_ui and game_ui.has_method("refresh_turn_indicators"):
		game_ui.refresh_turn_indicators()


## 세팅에서 아직 확정하지 않은 배치가 있으면 true.
func _has_pending_placement() -> bool:
	if _is_rules_mode():
		return not pending_cards.is_empty()
	return player_pending_card != null


## 플레이어 배치권 바 갱신. rules 없거나 매치 전이면 숨김.
func _refresh_placement_permission_display() -> void:
	if placement_permission_display == null:
		return
	if rules == null or not is_match_ready():
		placement_permission_display.visible = false
		placement_permission_display.clear_permission()
		return
	placement_permission_display.visible = true
	var filled := int(placement_permission.get(GameConstants.Side.PLAYER, 0))
	var reserved := 0
	if (
		current_phase == GameConstants.Phase.SETTING
		and active_side == GameConstants.Side.PLAYER
	):
		reserved = _rules_pending_cost()
	var slots := rules.permission_max_stored
	placement_permission_display.set_permission(filled, reserved, slots)


## 효과·presenter 경로용 공개 UI 동기화. LP 표시 + SETTING 라인 파워 라벨을 갱신한다.
## 왜: EM이 `_update_life_ui` / `_update_line_power_labels` private를 duck-call하지 않게 (S4 / B-EM-09).
func refresh_match_ui() -> void:
	_update_life_ui()
	_update_line_power_labels()


## LifeContainerDisplay를 양측 refresh한다. 내부·`refresh_match_ui` 전용.
func _update_life_ui() -> void:
	if player_life_display:
		player_life_display.refresh()
	if opponent_life_display:
		opponent_life_display.refresh()


## SETTING에서만 라인 파워 +/- 라벨을 갱신한다. 다른 페이즈는 no-op.
func _update_line_power_labels() -> void:
	if current_phase != GameConstants.Phase.SETTING:
		return
	var diffs: Dictionary = field_manager.get_line_power_diffs()
	_apply_power_label(left_power_label, int(diffs[GameConstants.Line.LEFT]))
	_apply_power_label(center_power_label, int(diffs[GameConstants.Line.CENTER]))
	_apply_power_label(right_power_label, int(diffs[GameConstants.Line.RIGHT]))


func _reset_line_power_labels() -> void:
	_apply_power_label(left_power_label, 0)
	_apply_power_label(center_power_label, 0)
	_apply_power_label(right_power_label, 0)


func _apply_power_label(label: Label, diff: int) -> void:
	if label == null:
		return
	if diff > 0:
		label.text = "+%d" % diff
		label.add_theme_color_override("font_color", COLOR_POWER_POSITIVE)
	elif diff < 0:
		label.text = str(diff)
		label.add_theme_color_override("font_color", COLOR_POWER_NEGATIVE)
	else:
		if first_player == GameConstants.Side.PLAYER:
			label.add_theme_color_override("font_color", COLOR_POWER_POSITIVE)
		else:
			label.add_theme_color_override("font_color", COLOR_POWER_NEGATIVE)
		label.text = "0"
		#label.add_theme_color_override("font_color", COLOR_POWER_NEUTRAL)


func _log_battle_result(result: Dictionary) -> void:
	var line_names: Array[String] = ["Left", "Center", "Right"]
	for line_result: Dictionary in result.line_results:
		var line_idx: int = int(line_result["line"])
		var line_name: String = line_names[line_idx]
		print(
			"라인 %s: 플레이어 %d vs 상대 %d -> 승자: %d"
			% [line_name, line_result["player_power"], line_result["opponent_power"], line_result["winner"]]
		)
	print("라운드 승자: %d" % result.round_winner)
