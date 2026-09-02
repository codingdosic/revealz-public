class_name CardInfoRules
extends RefCounted

## 덱에서 공개해 선택하는 카드(뤼트 등). EffectContext.register_reveal_select_card가 설정.
const META_REVEAL_SELECT := &"reveal_select_sidebar"


static func is_reveal_select_card(card: Node) -> bool:
	return card != null and is_instance_valid(card) and card.has_meta(META_REVEAL_SELECT)


static func is_sidebar_eligible(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if not card.get("card_data") or card.card_data == null:
		return false

	var zone: int = card.get("zone") if card.get("zone") != null else -1
	var owner: int = card.get("owner_side") if card.get("owner_side") != null else 0

	# 덱 프라이버시 예외: 효과로 공개된 선택 후보는 사이드바 허용.
	if zone == EffectTypes.Location.DECK and is_reveal_select_card(card):
		return true

	if zone == EffectTypes.Location.HAND:
		return owner == GameConstants.Side.PLAYER

	if zone == EffectTypes.Location.GRAVE:
		return true

	if zone == EffectTypes.Location.BANISH:
		return true

	if zone == EffectTypes.Location.STACK:
		return true

	if card.get("card_slot_card_is_in") != null or zone == EffectTypes.Location.FIELD:
		if bool(card.get("effect_set")):
			return false
		var state: int = card.get("reveal_state")
		if state == GameConstants.RevealState.SETTING_HIDDEN:
			return owner == GameConstants.Side.PLAYER
		return true

	return false
