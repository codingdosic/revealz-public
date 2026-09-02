extends DeckZone

const CARD_SCENE := preload("uid://c2ad0j2453lap")


func _ready() -> void:
	owner_side = GameConstants.Side.PLAYER
	super._ready()


## Initialises a fresh match; delegates to DeckZone with id arrays.
func init_match(deck_ids: Array[int] = [], deck_rarities: Array[int] = []) -> void:
	super.init_match(deck_ids, deck_rarities)
	#pin_card_after_life(CardRegistry.name_to_id("흑-흑마 바브"))


func get_card_scene() -> PackedScene:
	return CARD_SCENE


func get_hand_manager() -> Node:
	var found := FieldBoardBuilder.find_under_field(self, "PlayerHand")
	return found if found else get_node_or_null("../PlayerHand")


func get_tooltip_area() -> Area2D:
	return get_node_or_null("Area2D")
