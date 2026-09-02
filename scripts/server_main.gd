extends Node
## Headless dedicated listen (M0+) + ServerAuthoritySession (M2+).
## G4e-L1: listen first; card load is deck∪token after both INTENT_DECK (not boot full 8-A).
## Usage (lobby / G4):
##   godot --headless --path . res://scenes/server/server_main.tscn -- --port 7723 --room-code AB12
## Usage (dev fallback):
##   godot --headless --path . res://scenes/server/server_main.tscn -- --room 1001

const DEFAULT_ROOM := "1001"
const LOG_PREFIX := "[MP-SERVER]"


## 부팅: Dedicated 세션 → UDP listen 선행. 카드는 INTENT_DECK 후 세션에서 스코프 로드.
## G4: 방 비면 워커 quit — 이 씬으로의 “reused listen” 재진입은 레거시 안전망만.
func _ready() -> void:
	# Legacy: if somehow re-entered while already listening (pre-G4 room reset).
	if NetworkManager.dedicated_server and NetworkManager.is_online():
		if not (GameSession.get_active() is ServerAuthoritySession):
			GameSession.start_dedicated_server()
		print("%s ready (reused listen) room=%s port=%d" % [
			LOG_PREFIX,
			NetworkManager.room_code,
			NetworkManager.listen_port,
		])
		return

	var cfg := _parse_listen_config()
	NetworkManager.dedicated_server = true
	GameSession.start_dedicated_server()
	# 가벼운 경로 스캔만 — 전량 Resource load 없음 (export/DirAccess 회귀 감지).
	var card_paths := CardRegistry.list_card_paths()
	if card_paths.is_empty():
		push_error("%s CardRegistry paths empty — check cards export / DirAccess" % LOG_PREFIX)
		get_tree().quit(1)
		return
	var err: Error
	if cfg["explicit_port"]:
		err = NetworkManager.host_game(int(cfg["port"]), String(cfg["room"]))
	else:
		err = NetworkManager.host_room(String(cfg["room"]))
	if err != OK:
		push_error("%s host failed room=%s port=%s err=%s" % [
			LOG_PREFIX,
			String(cfg["room"]),
			str(cfg["port"]),
			error_string(err),
		])
		get_tree().quit(1)
		return
	var port := NetworkManager.listen_port
	print("%s listening room=%s port=%d max_clients=%d card_paths=%d card_scope=deferred" % [
		LOG_PREFIX,
		NetworkManager.room_code,
		port,
		NetworkConstants.MAX_CLIENTS,
		card_paths.size(),
	])
	print("%s Join×2 from clients: code=%s address=127.0.0.1 (do not press Host)" % [
		LOG_PREFIX,
		NetworkManager.room_code,
	])


## CLI: --port/--room-code (로비) 또는 레거시 --room. port<=0 이면 code%200 폴백.
func _parse_listen_config() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var port := -1
	var room := ""
	var room_code_meta := ""
	var i := 0
	while i < args.size():
		var a := String(args[i])
		if a == "--port" and i + 1 < args.size():
			port = String(args[i + 1]).strip_edges().to_int()
			i += 2
			continue
		if a.begins_with("--port="):
			port = a.substr("--port=".length()).strip_edges().to_int()
			i += 1
			continue
		if a == "--room-code" and i + 1 < args.size():
			room_code_meta = String(args[i + 1]).strip_edges()
			i += 2
			continue
		if a.begins_with("--room-code="):
			room_code_meta = a.substr("--room-code=".length()).strip_edges()
			i += 1
			continue
		if a == "--room" and i + 1 < args.size():
			room = String(args[i + 1]).strip_edges()
			i += 2
			continue
		if a.begins_with("--room="):
			room = a.substr("--room=".length()).strip_edges()
			i += 1
			continue
		i += 1
	var explicit := port > 0
	if room.is_empty():
		room = room_code_meta if not room_code_meta.is_empty() else DEFAULT_ROOM
	elif not room_code_meta.is_empty():
		# --port path: prefer --room-code as display/meta when both present.
		if explicit:
			room = room_code_meta
	return {
		"explicit_port": explicit,
		"port": port,
		"room": room,
	}
