class_name EffectTypes
extends RefCounted

enum Target { ALLY, OPPONENT, BOTH }
enum Location { DECK, HAND, FIELD, FIELD_L, FIELD_C, FIELD_R, GRAVE, BANISH, STACK, FIELD_ALL }
## banishzone — 묘지와 유사하되, 덱 고갈 시 셔플에 섞지 않음

## 발동 카드 “자신/상대” 진영. 존 쿼리 시 필드에 있으면 컨트롤러(slot.side), 아니면 owner_side.
enum RelativeSide { OWNER, OPPONENT }

enum EffectZone { HAND, GRAVE, FIELD, DECK, BANISH, STACK }

enum LineScope { ANY, SAME_AS_SOURCE, ALL_LINES, OTHER_THAN_SOURCE, EMPTY_ALLY_LINE }

enum CompareOp { LT, LE, EQ, GE, GT }

enum SelectionMode { PLAYER, RANDOM, AUTO }
