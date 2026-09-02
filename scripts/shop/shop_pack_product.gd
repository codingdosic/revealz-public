class_name ShopPackProduct
extends ShopProduct
## 카드팩 상품. 풀=카드 id 목록 하나. 개봉 시 등급 가중 → 풀 전체 id 균등(카피 등급 부여).
## 풀 해석 우선순위: pool_json → pool → pool_card_ids → 비토큰 전량.


@export_group("Pack")
## 팩 개봉 시 지급 장수.
@export_range(1, 30, 1) var pack_size: int = 5
## 출현 풀 JSON (`{ "id", "card_ids": [...] }`). 지정 시 최우선. 빈 card_ids면 다음 소스로 폴백.
@export_file("*.json") var pool_json: String = ""
## 출현 풀 Resource(.tres). pool_json이 비었을 때 사용.
@export var pool: ShopCardPool
## 인라인 출현 후보 CardData.id. 위 풀이 비었을 때 사용. 모두 비면 토큰 제외 전량.
@export var pool_card_ids: PackedInt32Array = PackedInt32Array()
## (미사용·레거시) 카드별 가중. 등급 확률은 weight_n~ur 사용.
@export var pool_weights: PackedInt32Array = PackedInt32Array()

@export_group("Rarity Odds")
## 등급 슬롯 가중(상대값, 합으로 나눔). 0이면 해당 등급은 안 나옴.
@export_range(0, 10000, 1) var weight_n: int = 70
@export_range(0, 10000, 1) var weight_r: int = 20
@export_range(0, 10000, 1) var weight_sr: int = 8
@export_range(0, 10000, 1) var weight_ur: int = 2
