class_name EffectChangeRecorder
extends RefCounted

var _changes: Array = []
var _recording: bool = false
## EffectContext.begin_move_vfx가 설정. MOVE/DESTROY/STACK_ATTACH/SWAP_FIELD에 복사.
var pending_vfx: Dictionary = {}
## EffectContext.begin_stat_fx가 설정. STAT op에 fx로 복사 (클라 배치 재생용).
var pending_stat_fx: Dictionary = {}


func begin() -> void:
	_changes.clear()
	_recording = true
	pending_stat_fx.clear()


func end() -> Array:
	_recording = false
	pending_stat_fx.clear()
	return _changes.duplicate(true)


func peek() -> Array:
	return _changes.duplicate(true)


func is_recording() -> bool:
	return _recording


func record(change: Dictionary) -> void:
	if not _recording:
		return
	var payload := change.duplicate(true)
	var op := String(payload.get("op", ""))
	if not pending_vfx.is_empty():
		if op in ["MOVE", "DESTROY", "STACK_ATTACH", "SWAP_FIELD"]:
			payload["vfx"] = pending_vfx.duplicate(true)
	if not pending_stat_fx.is_empty() and op == "STAT":
		payload["fx"] = pending_stat_fx.duplicate(true)
	_changes.append(payload)


func record_reveal(uuid: int) -> void:
	if uuid <= 0:
		return
	record({"op": "REVEAL", "uuid": uuid})


func record_move(
	uuid: int,
	name: String,
	from_zone: String,
	to_zone: String,
	side: int,
	reveal: bool = false,
	line: int = -1,
	slot_index: int = -1,
	rarity: int = -1,
	card_id: int = 0
) -> void:
	if uuid <= 0 and card_id <= 0 and name.is_empty():
		return
	var payload := {
		"op": "MOVE",
		"uuid": uuid,
		"name": name,
		"fromZone": from_zone,
		"toZone": to_zone,
		"side": side,
		"reveal": reveal,
	}
	if card_id > 0:
		payload["cardId"] = card_id
	if line >= 0:
		payload["line"] = line
	if slot_index >= 0:
		payload["slotIndex"] = slot_index
	if rarity >= 0:
		payload["rarity"] = rarity
	record(payload)


func record_destroy(
	uuid: int,
	name: String,
	side: int,
	suppress_trash: bool = false,
	card_id: int = 0
) -> void:
	if uuid <= 0 and card_id <= 0:
		return
	var payload := {
		"op": "DESTROY",
		"uuid": uuid,
		"name": name,
		"side": side,
		"suppressTrash": suppress_trash,
	}
	if card_id > 0:
		payload["cardId"] = card_id
	record(payload)


func record_stat(uuid: int, stats: Dictionary, source_uuid: int = 0) -> void:
	if uuid <= 0:
		return
	var payload := {"op": "STAT", "uuid": uuid, "stats": stats.duplicate(true)}
	if source_uuid > 0:
		payload["sourceUuid"] = source_uuid
	record(payload)


func record_spawn(
	uuid: int,
	name: String,
	zone: String,
	side: int,
	reveal: bool = false,
	rarity: int = -1,
	card_id: int = 0
) -> void:
	if uuid <= 0 and card_id <= 0 and name.is_empty():
		return
	var payload := {
		"op": "SPAWN",
		"uuid": uuid,
		"name": name,
		"zone": zone,
		"side": side,
		"reveal": reveal,
	}
	if card_id > 0:
		payload["cardId"] = card_id
	if rarity >= 0:
		payload["rarity"] = rarity
	record(payload)


func record_spawn_to_field(
	uuid: int,
	name: String,
	side: int,
	line: int,
	slot_index: int,
	reveal: bool = true,
	rarity: int = -1,
	card_id: int = 0
) -> void:
	if uuid <= 0 and card_id <= 0 and name.is_empty():
		return
	var payload := {
		"op": "SPAWN",
		"uuid": uuid,
		"name": name,
		"zone": "field",
		"side": side,
		"reveal": reveal,
		"line": line,
		"slotIndex": slot_index,
	}
	if card_id > 0:
		payload["cardId"] = card_id
	if rarity >= 0:
		payload["rarity"] = rarity
	record(payload)


func record_stack_attach(
	attached_uuid: int,
	host_uuid: int,
	from_zone: String,
	side: int,
	name: String = "",
	rarity: int = -1,
	card_id: int = 0
) -> void:
	if attached_uuid <= 0 or host_uuid <= 0:
		return
	var payload := {
		"op": "STACK_ATTACH",
		"attachedUuid": attached_uuid,
		"hostUuid": host_uuid,
		"fromZone": from_zone,
		"side": side,
	}
	if not name.is_empty():
		payload["name"] = name
	if card_id > 0:
		payload["cardId"] = card_id
	if rarity >= 0:
		payload["rarity"] = rarity
	record(payload)


func record_effect_set(uuid: int, value: bool = true) -> void:
	if uuid <= 0:
		return
	record({"op": "EFFECT_SET", "uuid": uuid, "value": value})


## 발동 확정 직후 클라 ActivationFx용. EVENT 타입은 EFFECT_RESULT 유지.
func record_activate(uuid: int, trigger: String) -> void:
	if uuid <= 0:
		return
	record({"op": "ACTIVATE", "uuid": uuid, "trigger": trigger})


func record_swap_field(
	uuid_a: int,
	uuid_b: int,
	dest_a: Dictionary,
	dest_b: Dictionary
) -> void:
	if uuid_a <= 0 or uuid_b <= 0:
		return
	record({
		"op": "SWAP_FIELD",
		"uuidA": uuid_a,
		"uuidB": uuid_b,
		"destA": dest_a.duplicate(true),
		"destB": dest_b.duplicate(true),
	})


func record_zone_snapshot(side: int, deck: DeckZone) -> void:
	if deck == null:
		return
	record({
		"op": "ZONE_SNAPSHOT",
		"side": side,
		"handLimit": deck.hand_limit,
		"deckRemaining": deck._pack_deck_remaining(),
		"graveyardRemaining": deck._pack_graveyard_remaining(),
		"banishRemaining": deck._pack_banishzone_remaining(),
		"lifeRemaining": deck._pack_life_remaining(),
	})
