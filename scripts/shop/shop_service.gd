class_name ShopService
extends RefCounted
## 상점 구매. Meta 가능 시 서버 트랜잭션, 아니면 로컬 롤·차감·가산.
## 장당: 등급 가중 롤 → 풀 전체에서 카드 균등 (같은 id·다른 등급 가능).


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
	if product is ShopAccessoryProduct:
		return _purchase_accessory_async(product as ShopAccessoryProduct)
	if product is ShopPackProduct:
		return await _purchase_pack_async(product as ShopPackProduct, pack_count)
	return _fail("지원하지 않는 상품 유형")


## 동기 래퍼(레거시). 메타 활성 시에는 로컬만 수행하지 말고 purchase_async를 쓸 것.
static func purchase(product: ShopProduct, pack_count: int = 1) -> Dictionary:
	if product == null:
		return _fail("상품이 없습니다")
	if product is ShopAccessoryProduct:
		return _purchase_accessory_local(product as ShopAccessoryProduct)
	if product is ShopPackProduct:
		return _purchase_pack_local(product as ShopPackProduct, pack_count)
	return _fail("지원하지 않는 상품 유형")


## 치장품 구매(비동기). 현재는 로컬 지급 · MetaSync는 owned push로 동기화.
static func _purchase_accessory_async(acc: ShopAccessoryProduct) -> Dictionary:
	return _purchase_accessory_local(acc)


## 치장품 구매(로컬): 보유 확인 → 골드 차감 → AccessoryStore.grant.
static func _purchase_accessory_local(acc: ShopAccessoryProduct) -> Dictionary:
	if acc == null:
		return _fail("상품이 없습니다")
	var acc_type := acc.get_accessory_type()
	var acc_id := acc.get_accessory_id()
	if acc_type.is_empty() or acc_id.is_empty():
		return _fail("잘못된 치장품 상품")
	AccessoryStore.ensure_loaded()
	if AccessoryStore.owns(acc_type, acc_id):
		return _fail("이미 보유 중입니다")
	var price := maxi(0, int(acc.price_gold))
	if WalletStore.get_gold() < price:
		return _fail("골드가 부족합니다")
	if not WalletStore.try_spend(price):
		return _fail("골드가 부족합니다")
	if not AccessoryStore.grant(acc_type, acc_id):
		WalletStore.add_gold(price)
		return _fail("지급 실패")
	return {
		KEY_OK: true,
		KEY_PRODUCT_ID: acc.product_id,
		KEY_SPENT: price,
		KEY_PACK_COUNT: 1,
		KEY_GRANTED_ACCESSORY_TYPE: acc_type,
		KEY_GRANTED_ACCESSORY_ID: acc_id,
	}


## 팩 구매: Meta 있으면 서버, 없으면 로컬.
static func _purchase_pack_async(pack: ShopPackProduct, pack_count: int) -> Dictionary:
	var sync := _meta_sync_node()
	if sync != null and bool(sync.get("meta_available")):
		var body := _build_purchase_body(pack, pack_count)
		if body.is_empty():
			return _fail("출현 풀이 비어 있습니다")
		var remote: Dictionary = await sync.purchase_pack_async(body)
		if remote.is_empty():
			return _purchase_pack_local(pack, pack_count)
		if bool(remote.get(KEY_OK, false)):
			return {
				KEY_OK: true,
				KEY_PRODUCT_ID: String(remote.get("product_id", pack.product_id)),
				KEY_SPENT: int(remote.get("spent", 0)),
				KEY_PACK_COUNT: int(remote.get("pack_count", pack_count)),
				KEY_GRANTED_IDS: remote.get("granted_card_ids", []),
				KEY_GRANTED_NAMES: remote.get("granted_names", []),
				KEY_GRANTED_RARITIES: remote.get("granted_rarities", []),
			}
		return _fail(String(remote.get("error", "구매 실패")))
	return _purchase_pack_local(pack, pack_count)


## 서버로 보낼 구매 body. 풀이 비면 {}.
static func _build_purchase_body(pack: ShopPackProduct, pack_count: int) -> Dictionary:
	var count := maxi(1, pack_count)
	var pool := _resolve_pool(pack)
	if pool.is_empty():
		return {}
	var pool_variant: Array = []
	for id in pool:
		pool_variant.append(id)
	return {
		"product_id": pack.product_id,
		"pack_count": count,
		"price_gold": maxi(0, int(pack.price_gold)),
		"pack_size": maxi(1, int(pack.pack_size)),
		"weight_n": maxi(0, int(pack.weight_n)),
		"weight_r": maxi(0, int(pack.weight_r)),
		"weight_sr": maxi(0, int(pack.weight_sr)),
		"weight_ur": maxi(0, int(pack.weight_ur)),
		"pool": pool_variant,
	}


## 카드팩 구매(로컬): 가격×횟수 확인 → 롤 → 차감 → 보유 가산.
static func _purchase_pack_local(pack: ShopPackProduct, pack_count: int) -> Dictionary:
	var count := maxi(1, pack_count)
	var unit_price := maxi(0, int(pack.price_gold))
	var total_price := unit_price * count
	var size := maxi(1, int(pack.pack_size))
	if WalletStore.get_gold() < total_price:
		return _fail("골드가 부족합니다")
	var pool := _resolve_pool(pack)
	if pool.is_empty():
		return _fail("출현 풀이 비어 있습니다")
	var granted_ids: Array[int] = []
	var granted_names: Array[String] = []
	var granted_rarities: Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total_cards := size * count
	for _i in total_cards:
		var rarity := _roll_rarity_tier(pack, rng)
		var card_id := pool[rng.randi_range(0, pool.size() - 1)]
		granted_ids.append(card_id)
		granted_rarities.append(rarity)
		var data := CardRegistry.get_by_id(card_id)
		granted_names.append(data.card_name if data else str(card_id))
	if not WalletStore.try_spend(total_price):
		return _fail("골드가 부족합니다")
	for i in granted_ids.size():
		CollectionStore.add(granted_ids[i], granted_rarities[i], 1)
	return {
		KEY_OK: true,
		KEY_PRODUCT_ID: pack.product_id,
		KEY_SPENT: total_price,
		KEY_PACK_COUNT: count,
		KEY_GRANTED_IDS: granted_ids,
		KEY_GRANTED_NAMES: granted_names,
		KEY_GRANTED_RARITIES: granted_rarities,
	}


## Autoload MetaSync.
static func _meta_sync_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/MetaSync")


## weight_n~ur 상대 가중으로 등급을 뽑는다. 전부 0이면 N.
static func _roll_rarity_tier(pack: ShopPackProduct, rng: RandomNumberGenerator) -> int:
	var weights: Array[int] = [
		maxi(0, int(pack.weight_n)),
		maxi(0, int(pack.weight_r)),
		maxi(0, int(pack.weight_sr)),
		maxi(0, int(pack.weight_ur)),
	]
	var total := 0
	for w in weights:
		total += w
	if total <= 0:
		return CardRarity.Tier.N
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for tier in range(weights.size()):
		acc += weights[tier]
		if roll < acc:
			return tier
	return CardRarity.Tier.N


## 팩 출현 풀 CardData.id 배열. pool_json → pool → pool_card_ids → 비토큰 전량.
static func _resolve_pool(pack: ShopPackProduct) -> Array[int]:
	CardRegistry.ensure_loaded()
	var from_json := _ids_from_pool_json(pack.pool_json)
	if not from_json.is_empty():
		return _sanitize_pool_ids(from_json)
	if pack.pool != null:
		var from_res := pack.pool.to_id_array()
		if not from_res.is_empty():
			return _sanitize_pool_ids(from_res)
	if pack.pool_card_ids != null and pack.pool_card_ids.size() > 0:
		var inline: Array[int] = []
		for raw_id in pack.pool_card_ids:
			inline.append(int(raw_id))
		var cleaned := _sanitize_pool_ids(inline)
		if not cleaned.is_empty():
			return cleaned
	return _all_non_token_ids()


## pool_json 경로에서 card_ids를 읽는다. 없거나 비면 빈 배열.
static func _ids_from_pool_json(path: String) -> Array[int]:
	var pool := ShopCardPool.load_json_path(path)
	if pool == null:
		return []
	return pool.to_id_array()


## 등록·비토큰 id만 남긴다. 순서 유지, 중복 허용(균등 롤용 가중치로 쓰지 않음).
static func _sanitize_pool_ids(raw_ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for id in raw_ids:
		if id <= 0 or CollectionStore.is_token_id(id):
			continue
		if CardRegistry.get_by_id(id) == null:
			continue
		out.append(id)
	return out


## 토큰을 제외한 카탈로그 전 id.
static func _all_non_token_ids() -> Array[int]:
	var out: Array[int] = []
	for card_name in CardRegistry.list_card_names_for_filter("all", true):
		var data := CardRegistry.get_by_name(String(card_name))
		if data == null:
			continue
		var id := int(data.id)
		if id <= 0 or CollectionStore.is_token_id(id):
			continue
		out.append(id)
	return out


## 실패 결과 Dictionary.
static func _fail(message: String) -> Dictionary:
	return {KEY_OK: false, KEY_ERROR: message}
