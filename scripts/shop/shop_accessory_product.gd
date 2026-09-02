class_name ShopAccessoryProduct
extends ShopProduct
## 치장품(아이콘·카드 뒷면·필드) 상점 상품. 구매 시 AccessoryStore에 지급.


@export var accessory_type: String = ""
@export var accessory_id: String = ""


func get_accessory_type() -> String:
	return accessory_type.strip_edges()


func get_accessory_id() -> String:
	return AccessoryCatalog.migrate_accessory_id(accessory_id.strip_edges())


## 보유 여부.
func is_owned() -> bool:
	var t := get_accessory_type()
	var id := get_accessory_id()
	if t.is_empty() or id.is_empty():
		return false
	AccessoryStore.ensure_loaded()
	return AccessoryStore.owns(t, id)


## 격자/상세용 아이콘 — 상품 icon 없으면 카탈로그 preview.
func resolve_icon() -> Texture2D:
	if icon != null:
		return icon
	return AccessoryCatalog.preview_for_id(get_accessory_id())
