class_name ShopProduct
extends Resource
## 상점 상품 공용 베이스. 트랜잭션·Inspector·상세 UI가 이 필드를 본다.
## 구체 타입(팩 등)은 이 클래스를 상속한다.
## icon = 격자 셀만. DetailRoot 갤러리 = detail_main + detail_sample_1~5.


@export var product_id: String = ""
@export var display_name: String = ""
@export var price_gold: int = 0
@export_multiline var description: String = ""
## 상점 격자(Detail 진입 전) 썸네일. DetailRoot에서는 쓰지 않음.
@export var icon: Texture2D

@export_group("Detail Gallery")
## 상세 메인(슬라이드 0번). MainImage 초기·순환 포함.
@export var detail_main: Texture2D
## 상세 썸네일·슬라이드 1~5. 비어 있으면 슬라이드에서 건너뜀.
@export var detail_sample_1: Texture2D
@export var detail_sample_2: Texture2D
@export var detail_sample_3: Texture2D
@export var detail_sample_4: Texture2D
@export var detail_sample_5: Texture2D


## 갤러리 슬라이드용 텍스처 배열 [main, s1..s5]. null 슬롯 포함(호출측에서 스킵).
func get_gallery_textures() -> Array[Texture2D]:
	return [
		detail_main,
		detail_sample_1,
		detail_sample_2,
		detail_sample_3,
		detail_sample_4,
		detail_sample_5,
	]
