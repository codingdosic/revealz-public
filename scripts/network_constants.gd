class_name NetworkConstants
extends RefCounted

const EVENT_GAME_START := "GAME_START"
const EVENT_DRAW_RESULT := "DRAW_RESULT"
const EVENT_TURN_CHANGED := "TURN_CHANGED"
const EVENT_PLACE_CARD := "PLACE_CARD"
const EVENT_PLACE_FAILED := "PLACE_FAILED"
const EVENT_REVEAL_PAIR := "REVEAL_PAIR"
const EVENT_BATTLE_RESULT := "BATTLE_RESULT"
const EVENT_CLEAN_DONE := "CLEAN_DONE"
const EVENT_GAME_OVER := "GAME_OVER"

const EVENT_EFFECT_WINDOW_START := "EFFECT_WINDOW_START"
const EVENT_EFFECT_WINDOW_END := "EFFECT_WINDOW_END"
const EVENT_EFFECT_DECISION_REQUEST := "EFFECT_DECISION_REQUEST"
const EVENT_EFFECT_RESULT := "EFFECT_RESULT"

const INTENT_PLACE := "PLACE"
## PLACE payload (A1 확장, type 유지):
## - 레거시 1장: uuid, line, slotIndex
## - 다중/패스: pass:bool, placements:[{uuid,line,slotIndex}]
##   (placements 비고·pass=true → 패스. 레거시 필드만 있으면 1장으로 해석)
const INTENT_EFFECT_DECISION := "EFFECT_DECISION"
const INTENT_CLIENT_SCENE_READY := "CLIENT_SCENE_READY"
## 자발적 항복. payload 없음. 권위가 GAME_OVER(reason=surrender) 확정.
const INTENT_FORFEIT := "FORFEIT"
## G3b: 카드 이름 배열 전달. payload `cardIds: Array`(IdKey, 우선), `cardNames: Array`(compat 병기),
## 선택 `displayName: String`, `accountKey: String`(G3.1 owned 검증), `cardRarities: Array`.
const INTENT_DECK := "DECK"
## G3.1: 권위가 덱⊆owned 검증 실패 시 클라에 통지.
const EVENT_DECK_REJECTED := "DECK_REJECTED"
## 레거시(G1). G3b 이후 미사용 — 상수만 유지.
const INTENT_DECK_COLOR := "DECK_COLOR"

const EFFECT_KIND_CONFIRM := "CONFIRM"
const EFFECT_KIND_PRIORITY := "PRIORITY"
const EFFECT_KIND_SELECT_TARGETS := "SELECT_TARGETS"
const EFFECT_KIND_SELECT_SLOTS := "SELECT_SLOTS"

const BASE_PORT := 7700
## Dedicated server: 2 player clients. LAN Host still works with 1 join.
const MAX_CLIENTS := 2
const EVENT_FANOUT_PROBE := "FANOUT_PROBE"

## ENet peer timeout (ms). Lower = faster force-close forfeit; too low drops peers during slow loads.
const ENET_TIMEOUT_LIMIT := 32
const ENET_TIMEOUT_MIN_MS := 20000
const ENET_TIMEOUT_MAX_MS := 60000
## Wall-clock wait for CLIENT_SCENE_READY (Tailscale / slow first load).
const SCENE_READY_TIMEOUT_SEC := 90.0
