class_name ShopSubcategory
extends Resource
## 상점 탭 아래 소분류(세로 목록). products에 ShopProduct 파생을 넣는다.


@export var id: String = ""
@export var display_name: String = ""
@export var products: Array[ShopProduct] = []
