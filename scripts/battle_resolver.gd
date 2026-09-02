class_name BattleResolver
extends RefCounted

static func get_card_power_from_node(
	card: Node,
	line: GameConstants.Line,
	side: GameConstants.Side
) -> int:
	if card == null or not is_instance_valid(card):
		return 0
	if not CardHelpers.contributes_field_power(card):
		return 0
	if card.has_method("get_power_for_line"):
		return card.get_power_for_line(line, side)
	return 0


static func sum_line_power_nodes(
	cards: Array,
	line: GameConstants.Line,
	side: GameConstants.Side
) -> int:
	var total := 0
	for card in cards:
		total += get_card_power_from_node(card, line, side)
	return total


static func resolve_line(
	player_cards: Array,
	opponent_cards: Array,
	line: GameConstants.Line,
	first_player: GameConstants.Side
) -> Dictionary:
	var player_power := sum_line_power_nodes(player_cards, line, GameConstants.Side.PLAYER)
	var opponent_power := sum_line_power_nodes(opponent_cards, line, GameConstants.Side.OPPONENT)

	var winner: GameConstants.Side
	if player_power > opponent_power:
		winner = GameConstants.Side.PLAYER
	elif opponent_power > player_power:
		winner = GameConstants.Side.OPPONENT
	else:
		winner = first_player

	return {
		"line": line,
		"winner": winner,
		"player_power": player_power,
		"opponent_power": opponent_power,
	}


static func resolve_round(
	player_cards_by_line: Dictionary,
	opponent_cards_by_line: Dictionary,
	first_player: GameConstants.Side
) -> Dictionary:
	var line_results: Array = []
	var player_line_wins := 0
	var opponent_line_wins := 0

	for line in [GameConstants.Line.LEFT, GameConstants.Line.CENTER, GameConstants.Line.RIGHT]:
		var player_cards: Array = player_cards_by_line.get(line, [])
		var opponent_cards: Array = opponent_cards_by_line.get(line, [])
		var result := resolve_line(player_cards, opponent_cards, line, first_player)
		line_results.append(result)

		if result.winner == GameConstants.Side.PLAYER:
			player_line_wins += 1
		elif result.winner == GameConstants.Side.OPPONENT:
			opponent_line_wins += 1

	var round_winner: GameConstants.Side
	if player_line_wins >= 2:
		round_winner = GameConstants.Side.PLAYER
	elif opponent_line_wins >= 2:
		round_winner = GameConstants.Side.OPPONENT
	else:
		round_winner = first_player

	return {
		"line_results": line_results,
		"round_winner": round_winner,
		"player_line_wins": player_line_wins,
		"opponent_line_wins": opponent_line_wins,
	}
