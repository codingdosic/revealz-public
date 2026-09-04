class_name MailboxClaimPopup
extends Control
## 선물 수령 결과 팝업. 제목 · 골드 또는 카드 칩 1장 · 하단 확인.
## 동일 카드 n장은 제목(xN). 서버 claim 연동은 이후.


signal confirmed

const SCENE_PATH := "res://scenes/ui/mailbox_claim_popup.tscn"
const CHIP_W := 96.0

@export var chrome_style: UiChromeStyle

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: PanelContainer = $Panel
@onready var _title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var _rewards: HBoxContainer = $Panel/Margin/VBox/RewardsScroll/Rewards
@onready var _empty_label: Label = $Panel/Margin/VBox/EmptyLabel
@onready var _confirm_button: Button = $Panel/Margin/VBox/ConfirmButton


static func instantiate_popup() -> MailboxClaimPopup:
	var packed := load(SCENE_PATH) as PackedScene
	return packed.instantiate() as MailboxClaimPopup


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _confirm_button and not _confirm_button.pressed.is_connected(_on_confirm_pressed):
		_confirm_button.pressed.connect(_on_confirm_pressed)
	_apply_chrome()


func apply_chrome(style: UiChromeStyle = null) -> void:
	chrome_style = UiChromeStyle.resolve(style if style else chrome_style)
	_apply_chrome()


## title + payload. 골드 또는 카드 한쪽만 표시. 동일 카드 n장은 칩 1장(장수는 제목).
func present(title: String, payload: Dictionary, style: UiChromeStyle = null) -> void:
	if style:
		apply_chrome(style)
	else:
		_apply_chrome()
	_title_label.text = title if not title.is_empty() else "획득"
	_clear_rewards()
	var gold := int(payload.get("gold", 0))
	var cards: Array = payload.get("cards", []) as Array
	var has_gold := gold > 0
	var has_card := not cards.is_empty()
	_empty_label.visible = not has_gold and not has_card
	if has_gold:
		var gold_label := Label.new()
		gold_label.text = "%d G" % gold
		gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		gold_label.custom_minimum_size = Vector2(88, 72)
		if chrome_style:
			chrome_style.apply_title_label(gold_label)
		_rewards.add_child(gold_label)
	elif has_card:
		CardRegistry.ensure_loaded()
		var chip_size := Vector2(CHIP_W, CHIP_W / DeckCardChip.CARD_ASPECT)
		for entry in cards:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var card: Dictionary = entry
			var card_name := String(card.get("name", ""))
			if card_name.is_empty():
				card_name = CardRegistry.id_to_name(int(card.get("id", 0)))
			if card_name.is_empty():
				continue
			var rarity := clampi(int(card.get("rarity", 0)), CardRarity.Tier.N, CardRarity.Tier.UR)
			var chip := DeckCardChip.instantiate_chip()
			chip.setup(card_name, false, -1, chip_size, rarity)
			chip.set_owned_count(-1)
			_rewards.add_child(chip)
			break
	visible = true
	move_to_front()
	if _confirm_button:
		_confirm_button.grab_focus()


func close() -> void:
	visible = false
	_clear_rewards()


func _apply_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	if _panel:
		chrome_style.apply_panel(_panel)
	if _title_label:
		chrome_style.apply_title_label(_title_label)
	if _empty_label:
		chrome_style.apply_muted_label(_empty_label)
	if _confirm_button:
		chrome_style.apply_buttons([_confirm_button])
		var copy := chrome_style.get_copy()
		_confirm_button.text = copy.confirm if not copy.confirm.is_empty() else "확인"


func _clear_rewards() -> void:
	if _rewards == null:
		return
	for child in _rewards.get_children():
		_rewards.remove_child(child)
		child.queue_free()


func _on_confirm_pressed() -> void:
	confirmed.emit()
	close()
