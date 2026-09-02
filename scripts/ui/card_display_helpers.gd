class_name CardDisplayHelpers
extends RefCounted

const TRIGGER_COLOR := "#FFD700"
const BODY_FONT_SIZE := 12

const TRIGGER_FLAG_NAMES := {
	1: "오픈",
	2: "트래쉬",
	4: "라이프",
	8: "바인드",
	16: "스택",
	32: "패시브",
	64: "바닐라",
}


static func format_trigger_flags(trigger_type: int, once_per_turn: bool) -> String:
	var names: PackedStringArray = []
	for flag in TRIGGER_FLAG_NAMES:
		if trigger_type & flag:
			names.append(TRIGGER_FLAG_NAMES[flag])
	if once_per_turn:
		names.append("턴 1회")
	return " · ".join(names)


static func is_unit_card(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if not card.get("card_data") or card.card_data == null:
		return false
	return card.card_data.card_type == "Unit"


static func is_token_card(card: Node) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if not card.get("card_data") or card.card_data == null:
		return false
	return (card.card_data.trigger_type & 128) != 0


static func card_matches_type(card: Node, type_name: String) -> bool:
	if type_name.is_empty() or card == null or not card.card_data:
		return true
	return String(card.card_data.type) == type_name


static func card_matches_any_type(card: Node, type_names: PackedStringArray) -> bool:
	if type_names.is_empty():
		return true
	for type_name in type_names:
		if card_matches_type(card, type_name):
			return true
	return false


static func format_effect_text(card_data: CardData) -> String:
	return format_effect_text_bbcode(card_data)


static func format_effect_text_bbcode(card_data: CardData) -> String:
	
	if card_data == null:
		return ""
	# 앞뒤 공백 제거
	var text := card_data.effect_text.strip_edges() if card_data.effect_text else ""
	
	# 트리거 플래그 읽어와서 오픈 · 패시브 의 형태로 결합
	var trigger_label := format_trigger_flags(card_data.trigger_type, card_data.oncePerTurn)
	
	# 예외 처리
	if text.is_empty():
		if trigger_label.is_empty():
			return ""
		return "[color=%s]%s[/color]" % [TRIGGER_COLOR, trigger_label]
	if trigger_label.is_empty():
		return "[font_size=%d]%s[/font_size]" % [BODY_FONT_SIZE, _escape_bbcode(text.replace("$Trigger", "").strip_edges())]
	
	
	var parts: PackedStringArray = []
	var remainder := text
	while remainder.contains("$Trigger"):
		var idx := remainder.find("$Trigger")
		if idx > 0:
			var body := remainder.substr(0, idx).strip_edges()
			if not body.is_empty():
				parts.append("[font_size=%d]%s[/font_size]" % [BODY_FONT_SIZE, _escape_bbcode(body)])
		parts.append("[color=%s]%s[/color]" % [TRIGGER_COLOR, trigger_label])
		remainder = remainder.substr(idx + "$Trigger".length())
	remainder = remainder.strip_edges()
	if not remainder.is_empty():
		parts.append("[font_size=%d]%s[/font_size]" % [BODY_FONT_SIZE, _escape_bbcode(remainder)])
	return "\n".join(parts)


static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")
