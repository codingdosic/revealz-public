extends Control
## 매치 진입: VS 연출 → 카드 로드 → 페이드아웃 → game.tscn.
## 자식: MatchVersusOverlay · LoadingGate (씬 인스턴스). 페이드는 SceneTransition autoload.

const GAME_SCENE := "res://scenes/game/game.tscn"
const FADE_TO_BLACK_SEC := 0.4
const FADE_IN_RADIAL_SEC := 0.7

@export var chrome_style: UiChromeStyle

@onready var _versus: MatchVersusOverlay = $MatchVersusOverlay
@onready var _gate: LoadingGate = $LoadingGate


func _ready() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_background(self)
	if _versus:
		_versus.apply_chrome(chrome_style)
	if _gate:
		_gate.apply_chrome(chrome_style)
		_gate.hide_gate()
	await get_tree().process_frame
	await _run_entry_flow()


func _run_entry_flow() -> void:
	if _should_play_intro():
		await _versus.play_entry_intro(_resolve_intro_first_player())
	await _run_loading()
	await SceneTransition.fade_to_black(FADE_TO_BLACK_SEC)
	SceneTransition.arm_fade_in_after_scene_change(
		FADE_IN_RADIAL_SEC,
		SceneTransition.FadeInStyle.RADIAL_CENTER
	)
	get_tree().change_scene_to_file(GAME_SCENE)


func _should_play_intro() -> bool:
	return GameSession.get_active() != null


## VS 코인토스용 로컬 선공. 싱글은 여기서 롤하고 PM은 session.first_player를 재사용.
func _resolve_intro_first_player() -> GameConstants.Side:
	var session := GameSession.get_active()
	if session == null:
		return GameConstants.Side.PLAYER
	if session.play_mode == GameSessionBase.PlayMode.LOCAL_SINGLE:
		return session.roll_first_player()
	return session.first_player


func _run_loading() -> void:
	_gate.show_gate("카드를 불러오는 중…", false, false)
	var ids: Array[int] = GameSession.take_pending_card_ids()
	var names: Array[String] = GameSession.take_pending_card_names()
	if ids.is_empty():
		ids = CardRegistry.names_to_ids(names)
	if ids.is_empty():
		push_warning("MatchLoadingScreen: no pending card ids — safety-net ensure_loaded")
		_gate.update_message("카드 준비 중…")
		CardRegistry.ensure_loaded()
	else:
		await CardRegistry.ensure_deck_union_tokens_loaded_ids(ids, _on_load_progress)
	_gate.update_message("게임 시작…")
	await get_tree().process_frame


func _on_load_progress(done: int, total: int, _label: String) -> void:
	var t := maxi(total, 1)
	var pct := int(round((100.0 * float(done)) / float(t)))
	_gate.update_message("카드를 불러오는 중… %d%%" % pct)
