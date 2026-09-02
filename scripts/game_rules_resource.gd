extends Resource
class_name GameRulesResource

## 세팅 페이즈 룰 리소스.
## PhaseManager @export rules 에 연결 (싱글·MP). null 이면 레거시 1장/턴 (default 자동 폴백 없음).
## MP PLACE A1 · 효과 sheet 는 MULTIPLAYER_HANDOFF §11.6 / effect.txt.

enum FlipMode { SIMULTANEOUS, SEQUENTIAL }

@export_group("배치권")
## 자신 턴 시작 시 자동으로 부여되는 배치권 수
@export var permission_gain_per_turn: int = 2
## 배치권 최대 저장 상한 (초과분 소멸)
@export var permission_max_stored: int = 4

@export_group("턴 구성")
## 각 플레이어의 세팅 턴 수 (기존 SETTING_PLACEMENTS 대체)
@export var setting_turns_per_player: int = 5
## 한 턴에 배치 가능한 최대 카드 장수
@export var max_cards_per_turn: int = 2
## 패스(0장 배치) 허용 여부
@export var allow_pass: bool = true

@export_group("라인 규칙")
## Unit 카드 동일 라인 강제
@export var require_same_line_unit: bool = true
## Spell 카드 동일 라인 강제
@export var require_same_line_spell: bool = false

@export_group("효과")
## 세팅 페이즈 중 OPEN 효과 발동 여부 (false = 1차 코스트/배치 테스트용)
@export var setting_effects_enabled: bool = false
## 플립 방식: SIMULTANEOUS(동시) or SEQUENTIAL(순차)
@export var flip_mode: FlipMode = FlipMode.SIMULTANEOUS
