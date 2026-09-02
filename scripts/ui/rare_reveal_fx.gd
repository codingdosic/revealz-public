class_name RareRevealFx
extends RefCounted
## 인게임 SR+ 공개 연출 진입점. presenter 교체로 연출을 바꿀 수 있다.
## 계약: presenter.play_on_card(card: Node2D, tier: int) -> void


static var _presenter: RefCounted = null


## 연출 구현체를 교체한다. null이면 다음 play 때 Default로 되돌린다.
static func set_presenter(presenter: RefCounted) -> void:
	_presenter = presenter


## 현재 presenter. 없으면 RareRevealFxDefault를 만든다.
static func get_presenter() -> RefCounted:
	if _presenter == null:
		_presenter = RareRevealFxDefault.new()
	return _presenter


## SR+ 카드면 등록된 presenter로 공개 연출을 재생한다.
static func play(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	var tier := CardRarity.Tier.N
	var raw: Variant = card.get("instance_rarity")
	if raw != null:
		tier = clampi(int(raw), CardRarity.Tier.N, CardRarity.Tier.UR)
	if not CardRarity.plays_reveal_fx(tier):
		return
	var presenter := get_presenter()
	if presenter == null or not presenter.has_method("play_on_card"):
		return
	presenter.play_on_card(card, tier)
