extends "res://scenes/card_slot/card/card.gd"

func _ready() -> void:
	owner_side = GameConstants.Side.OPPONENT
	super._ready()
