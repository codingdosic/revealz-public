class_name PackGridCell
extends Control
## 팩 오픈 다팩 그리드용 축소 셀.
## 최소 크기·Art·레어 프레임은 이 씬에서 조정한다.


@onready var _art: TextureRect = $Art
@onready var _rarity_frame: Panel = $RarityFrame


## 팩 텍스처·힌트 레어 티어(-1이면 프레임 숨김)·셀 크기를 세팅한다.
func configure(pack_tex: Texture2D, hint_tier: int, cell_size: Vector2) -> void:
	custom_minimum_size = cell_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _art == null:
		_art = get_node_or_null("Art") as TextureRect
	if _rarity_frame == null:
		_rarity_frame = get_node_or_null("RarityFrame") as Panel
	if _art:
		_art.texture = pack_tex
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if CardRarity.shows_display(hint_tier):
			CardRarityFoil.apply(_art, hint_tier, true)
		else:
			CardRarityFoil.clear(_art)
	if _rarity_frame == null:
		return
	_rarity_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if CardRarity.ENABLE_STYLEBOX_FRAME and hint_tier >= 0:
		_rarity_frame.visible = true
		_rarity_frame.add_theme_stylebox_override(
			"panel",
			CardRarity.make_frame_style(hint_tier, 2.5)
		)
	else:
		_rarity_frame.visible = false
