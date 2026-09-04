class_name ShopService
extends RefCounted
## 상점 구매 — 서버 권위. Meta TX만 (로컬 fallback 없음).
## body: product_id + pack_count. 가격·풀은 서버 DB.


## 구매 결과 키.
const KEY_OK := "ok"
const KEY_ERROR := "error"
const KEY_PRODUCT_ID := "product_id"
const KEY_SPENT := "spent"
const KEY_PACK_COUNT := "pack_count"
const KEY_GRANTED_IDS := "granted_card_ids"
const KEY_GRANTED_NAMES := "granted_names"
const KEY_GRANTED_RARITIES := "granted_rarities"
const KEY_GRANTED_ACCESSORY_TYPE := "granted_accessory_type"
const KEY_GRANTED_ACCESSORY_ID := "granted_accessory_id"


## 상품 구매(비동기). pack_count는 팩 개수(기본 1). 성공 시 ok=true · granted_* 채움.
static func purchase_async(product: ShopProduct, pack_count: int = 1) -> Dictionary:
	if product == null:
		return _fail("상품이 없습니다")
	if product.product_id.strip_edges().is_empty():
		return _fail("상품 ID가 없습니다")
	var sync := _meta_sync_node()
	if sync == null or not bool(sync.get("meta_available")):
		return _fail("서버 연결이 필요합니다")
	var count := 1
	if product is ShopPackProduct:
		count = maxi(1, pack_count)
	var body := {
		"product_id": product.product_id.strip_edges(),
		"pack_count": count,
	}
	var remote: Dictionary = await sync.purchase_product_async(body)
	if remote.is_empty():
		return _fail("서버 연결이 필요합니다")
	if not bool(remote.get(KEY_OK, false)):
		return _fail(String(remote.get("error", "구매 실패")))
	var out := {
		KEY_OK: true,
		KEY_PRODUCT_ID: String(remote.get("product_id", product.product_id)),
		KEY_SPENT: int(remote.get("spent", 0)),
		KEY_PACK_COUNT: int(remote.get("pack_count", count)),
	}
	if product is ShopPackProduct:
		out[KEY_GRANTED_IDS] = remote.get("granted_card_ids", [])
		out[KEY_GRANTED_NAMES] = remote.get("granted_names", [])
		out[KEY_GRANTED_RARITIES] = remote.get("granted_rarities", [])
	elif product is ShopAccessoryProduct:
		out[KEY_GRANTED_ACCESSORY_TYPE] = String(remote.get("granted_accessory_type", ""))
		out[KEY_GRANTED_ACCESSORY_ID] = String(remote.get("granted_accessory_id", ""))
	return out


## 동기 래퍼(레거시) — 서버 권위 이후 사용 금지. purchase_async를 쓸 것.
static func purchase(product: ShopProduct, pack_count: int = 1) -> Dictionary:
	return _fail("서버 구매만 지원합니다. purchase_async를 사용하세요.")


## Autoload MetaSync.
static func _meta_sync_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/MetaSync")


## 실패 결과 Dictionary.
static func _fail(message: String) -> Dictionary:
	return {KEY_OK: false, KEY_ERROR: message}
