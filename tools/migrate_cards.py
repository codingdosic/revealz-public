import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "old", "Res", "Cards", "Black")
DST = os.path.join(ROOT, "resources", "cards", "black")
os.makedirs(DST, exist_ok=True)

NAME_MAP = {
    "그레이브": "흑-그레이브",
    "말살의 기사 리리스": "흑-말살의 기사 리리스",
    "망각의 군주 모르두스": "흑-망각의 군주 모르두스",
    "반역의 대군주 벨리알": "흑-반역의 대군주 벨리알",
    "반전의 흑마술사": "흑-반전의 흑마술사",
    "새침한 악마 소녀": "흑-새침한 악마 소녀",
    "선봉의 흑기사": "흑-선봉의 흑기사",
    "소울 이터": "흑-소울 이터",
    "영혼 수집가 랑": "흑-영혼 수집가 랑",
    "영혼길잡이 세나토스": "흑-영혼 길잡이 세나토스",
    "원한에 잠식된 늑대 무리": "흑-원한에 잠식된 늑대 무리",
    "은밀한 발걸음 캐스퍼": "흑-은밀한 발걸음 캐스퍼",
    "타락한 공주 키르나쥬": "흑-타락한 공주 키르나쥬",
    "해방된 거대 죄수": "흑-해방된 거대 죄수",
    "흑마 바브": "흑-흑마 바브",
}

PATH_REPLACEMENTS = [
    ("res://old/Res/Cards/cardData.gd", "res://resources/cards/card_data.gd"),
    ("res://Res/Cards/cardData.gd", "res://resources/cards/card_data.gd"),
    ("res://resources/Cards/cardData.gd", "res://resources/cards/card_data.gd"),
    ("res://old/Res/scripts/effectDefault/effectBundle.gd", "res://resources/effects/default/effect_bundle.gd"),
    ("res://Res/scripts/effectDefault/effectBundle.gd", "res://resources/effects/default/effect_bundle.gd"),
    ("res://resources/scripts/effectDefault/effectBundle.gd", "res://resources/effects/default/effect_bundle.gd"),
    ("res://Res/scripts/effectCustom/action/action_draw.gd", "res://resources/effects/custom/action/action_draw.gd"),
    ("res://Res/scripts/effectCustom/action/action_trashCard.gd", "res://resources/effects/custom/action/action_trash_card.gd"),
    ("res://Res/scripts/effectCustom/action/action_killCard.gd", "res://resources/effects/custom/action/action_kill_card.gd"),
    ("res://Res/scripts/effectCustom/action/action_changeStat.gd", "res://resources/effects/custom/action/action_change_stat.gd"),
    ("res://Res/scripts/effectCustom/action/action_changeAllStats.gd", "res://resources/effects/custom/action/action_change_all_stats.gd"),
    ("res://Res/scripts/effectCustom/action/action_trashDeck.gd", "res://resources/effects/custom/action/action_trash_deck.gd"),
    ("res://Res/scripts/effectCustom/action/action_trashOpponentDeck.gd", "res://resources/effects/custom/action/action_trash_opponent_deck.gd"),
    ("res://Res/scripts/effectCustom/action/action_salvageCard.gd", "res://resources/effects/custom/action/action_salvage_card.gd"),
    ("res://Res/scripts/effectCustom/action/action_reborn.gd", "res://resources/effects/custom/action/action_reborn.gd"),
    ("res://Res/scripts/effectCustom/condition/condition_cardOnAllyField.gd", "res://resources/effects/custom/condition/condition_card_on_ally_field.gd"),
    ("res://Res/scripts/effectCustom/condition/condition_cardOnOpponentField.gd", "res://resources/effects/custom/condition/condition_card_on_opponent_field.gd"),
    ("res://Res/scripts/effectCustom/condition/condition_cardOnAllyGraveyard.gd", "res://resources/effects/custom/condition/condition_card_on_ally_graveyard.gd"),
    ("res://Res/scripts/effectCustom/condition/condition_cardOnOpponentGraveyard.gd", "res://resources/effects/custom/condition/condition_card_on_opponent_graveyard.gd"),
    ("res://Res/scripts/effectCustom/condition/condition_graveCount.gd", "res://resources/effects/custom/condition/condition_grave_count.gd"),
    ("res://Res/scripts/effectCustom/condition/condition_handCount.gd", "res://resources/effects/custom/condition/condition_hand_count.gd"),
    ("res://Res/scripts/effectCustom/target/target_selectOneField.gd", "res://resources/effects/custom/target/target_select_one_field.gd"),
    ("res://Res/scripts/effectCustom/target/target_selectOneGraveyard.gd", "res://resources/effects/custom/target/target_select_one_graveyard.gd"),
    ("res://Res/scripts/effectCustom/target/target_self.gd", "res://resources/effects/custom/target/target_self.gd"),
    ("res://Assets/Images/Black/", "res://assets/Black/"),
    ("res://Assets/Images/newBack.png", "res://assets/리빌즈 카드뒷면.png"),
]

for fname in os.listdir(SRC):
    if not fname.endswith(".tres"):
        continue
    with open(os.path.join(SRC, fname), "r", encoding="utf-8") as f:
        text = f.read()
    for old, new in PATH_REPLACEMENTS:
        text = text.replace(old, new)
    for old_name, new_name in NAME_MAP.items():
        text = text.replace(f'card_name = "{old_name}"', f'card_name = "{new_name}"')
    text = re.sub(r' uid="uid://[^"]+"', "", text)
    with open(os.path.join(DST, fname), "w", encoding="utf-8") as f:
        f.write(text)
    print("Wrote", fname)

print("Done", len(os.listdir(DST)), "files")
