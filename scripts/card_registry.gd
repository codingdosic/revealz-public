class_name CardRegistry
extends RefCounted
## CardData .tres 레지스트리. `resources/cards/` 이하를 재귀 스캔해 로드한다.
## 색 판별 SSOT는 CardData.color 플래그 (이름 접두·폴더명은 사용하지 않음).


## 카드 리소스 루트. 하위 폴더(black/…/colorless 및 추가 폴더)를 재귀 스캔.
const CARDS_ROOT := "res://resources/cards/"

## CardData.color `@export_flags("BLACK","WHITE","GREEN","RED","BLUE","COLORLESS")` 비트.
const COLOR_FLAG_BLACK := 1
const COLOR_FLAG_WHITE := 2
const COLOR_FLAG_GREEN := 4
const COLOR_FLAG_RED := 8
const COLOR_FLAG_BLUE := 16
const COLOR_FLAG_COLORLESS := 32

static var _by_id: Dictionary = {}
static var _by_name: Dictionary = {}
static var _loaded: bool = false
## `_list_all_card_paths` 결과 캐시 (루트 재스캔 생략).
static var _path_list_cache: Array[String] = []

enum DeckColor { BLACK, RED, BLUE, GREEN, WHITE }

const DEFAULT_DECK_BLACK: Array[String] = [
	"그레이브",
	"그레이브",
	"선봉의 흑기사",
	"선봉의 흑기사",
	"해방된 거대 죄수",
	"해방된 거대 죄수",
	"말살의 기사 리리스",
	"말살의 기사 리리스",
	"망각의 기사 모르두스",
	"망각의 기사 모르두스",
	"반역의 군주 벨리알",
	"반역의 군주 벨리알",
	"반전의 흑마술사",
	"반전의 흑마술사",
	"새침한 악마 소녀",
	"새침한 악마 소녀",
	"소울 이터",
	"소울 이터",
	"영혼 길잡이 세나토스",
	"영혼 길잡이 세나토스",
	"영혼 수집가 랑",
	"영혼 수집가 랑",
	"영혼에 잠식된 늑대",
	"영혼에 잠식된 늑대",
	"은밀한 발걸음 캐스퍼",
	"은밀한 발걸음 캐스퍼",
	"타락한 공주 키르나쥬",
	"타락한 공주 키르나쥬",
	"흑마 바브",
	"흑마 바브",
]

const DEFAULT_DECK_RED: Array[String] = [
	"굶주린 라바 케르베로스",
	"굶주린 라바 케르베로스",
	"대담한 용녀 피로",
	"대담한 용녀 피로",
	"드라그나의 권속",
	"드라그나의 권속",
	"드래그하트 스칼론",
	"드래그하트 스칼론",
	"드래그하트 진",
	"드래그하트 진",
	"라그나 드래곤",
	"라그나 드래곤",
	"라바 스네이크",
	"라바 스네이크",
	"라바의 문지기",
	"라바의 문지기",
	"블러드 본 리저드",
	"블러드 본 리저드",
	"비룡 브레시아",
	"비룡 브레시아",
	"용암에서 깨어난 악마",
	"용암에서 깨어난 악마",
	"자이언트 리저드",
	"자이언트 리저드",
	"종언의 불꽃 드라그나",
	"종언의 불꽃 드라그나",
	"천공룡 지오빌란",
	"천공룡 지오빌란",
	"황혼의 무녀 키이나",
	"황혼의 무녀 키이나",

]

const DEFAULT_DECK_WHITE: Array[String] = [
	"격려의 기사 잔다르",
	"격려의 기사 잔다르",
	"결속의 화음 요한",
	"결속의 화음 요한",
	"기사단장 룩스",
	"기사단장 룩스",
	"불굴의 기사 베르트",
	"불굴의 기사 베르트",
	"성기사단의 궁수",
	"성기사단의 궁수",
	"성석의 백마법사",
	"성석의 백마법사",
	"시스터 마리안",
	"시스터 마리안",
	"신성수 콘도르",
	"신성수 콘도르",
	"신성수 페가시스",
	"신성수 페가시스",
	"신성한 날개 이즈라엘",
	"신성한 날개 이즈라엘",
	"전파자 P-534",
	"전파자 P-534",
	"자유의 성기사 세르무스",
	"자유의 성기사 세르무스",
	"지혜의 천사 라파엘",
	"지혜의 천사 라파엘",
	"집념의 기사 조슈아",
	"집념의 기사 조슈아",
	"평화의 대주교",
	"평화의 대주교",
]

const DEFAULT_DECK_GREEN: Array[String] = [
	"숲속의 바위술사",
	"숲속의 바위술사",
	"관찰자 드루이어드",
	"관찰자 드루이어드",
	"머쉬룸 골렘",
	"머쉬룸 골렘",
	"바위술사의 걸작",
	"바위술사의 걸작",
	"비취 날개",
	"비취 날개",
	"세계수의 씨앗",
	"세계수의 씨앗",
	"숲속의 방랑자 엘리나",
	"숲속의 방랑자 엘리나",
	"숲속의 요정",
	"숲속의 요정",
	"숲속의 음유시인",
	"숲속의 음유시인",
	"숲속의 중재자 루인",
	"숲속의 중재자 루인",
	"숲지기 실피드",
	"숲지기 실피드",
	"원한의 다크엘프",
	"원한의 다크엘프",
	"자연의 분노 바쿠",
	"자연의 분노 바쿠",
	"자이언트 가드너",
	"자이언트 가드너",
	"혼란의 독날개",
	"혼란의 독날개",
]

const DEFAULT_DECK_BLUE: Array[String] = [
	"거울의 마녀 미요",
	"거울의 마녀 미요",
	"공간의 마술사 로스톰",
	"공간의 마술사 로스톰",
	"깜짝 마술사 이스텔",
	"깜짝 마술사 이스텔",
	"돌연변이 마괴수",
	"돌연변이 마괴수",
	"마공학 꿈 장치",
	"마공학 꿈 장치",
	"마공학 병기",
	"마공학 병기",
	"마녀의 사역마",
	"마녀의 사역마",
	"마녀의 조수 밀리아",
	"마녀의 조수 밀리아",
	"마도구 상인",
	"마도구 상인",
	"마술사 지도 교수",
	"마술사 지도 교수",
	"선택의 마술사 뤼트",
	"선택의 마술사 뤼트",
	"신참 마술사",
	"신참 마술사",
	"장전의 마술사 슈티",
	"장전의 마술사 슈티",
	"전이 마술사 아스트로",
	"전이 마술사 아스트로",
	"제약의 마술사 제노",
	"제약의 마술사 제노",
]

## 덱 상수 배열을 복제한다 (호출측 수정이 원본을 건드리지 않게).
static func _copy_deck_names(source: Array[String]) -> Array[String]:
	var deck: Array[String] = []
	for card_name in source:
		deck.append(card_name)
	return deck


## 이름 목록에서 중복을 제거한 새 배열을 반환한다.
static func unique_card_names(names: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for card_name in names:
		if card_name.is_empty() or seen.has(card_name):
			continue
		seen[card_name] = true
		out.append(card_name)
	return out


## 여러 색 기본 덱 이름을 합쳐 중복 없이 반환한다.
static func names_for_colors(colors: Array) -> Array[String]:
	var merged: Array[String] = []
	for color_variant in colors:
		merged.append_array(build_deck_for_color(color_variant as DeckColor))
	return unique_card_names(merged)


## 카드 파일 경로 목록(캐시). Resource 전량 로드 없이 export/DirAccess 헬스체크용.
static func list_card_paths() -> Array[String]:
	return _list_all_card_paths()


## `CARDS_ROOT` 이하 .tres/.res 경로를 재귀 수집한다 (캐시).
static func _list_all_card_paths() -> Array[String]:
	if not _path_list_cache.is_empty():
		return _path_list_cache
	_path_list_cache = _list_card_paths_recursive(CARDS_ROOT)
	return _path_list_cache


## Export-safe 재귀 스캔. 하위 폴더·`.tres.remap` 복원 포함. card_data.gd 등은 제외.
static func _list_card_paths_recursive(base_dir: String) -> Array[String]:
	var paths: Array[String] = []
	var file_names: PackedStringArray = ResourceLoader.list_directory(base_dir)
	if file_names.is_empty():
		var dir := DirAccess.open(base_dir)
		if dir == null:
			push_warning("CardRegistry: cannot open %s" % base_dir)
			return paths
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry == "." or entry == "..":
				entry = dir.get_next()
				continue
			if dir.current_is_dir():
				file_names.append(entry + "/")
			else:
				file_names.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()

	for file_name in file_names:
		if file_name.ends_with("/"):
			var sub := base_dir.path_join(file_name.trim_suffix("/")) + "/"
			paths.append_array(_list_card_paths_recursive(sub))
			continue
		var resource_name := file_name
		if resource_name.ends_with(".remap"):
			resource_name = resource_name.trim_suffix(".remap")
		if resource_name.ends_with(".import"):
			continue
		var ext := resource_name.get_extension()
		if ext != "tres" and ext != "res":
			continue
		# 스크립트·비카드 리소스 제외 (이름은 card_data 등).
		if resource_name.get_basename() == "card_data":
			continue
		paths.append(base_dir.path_join(resource_name))
	return paths


## path의 CardData를 레지스트리에 넣는다. CardData가 아니면 null.
static func _load_card_at_path(path: String) -> CardData:
	var data: CardData = load(path) as CardData
	if data == null:
		# 함정: 폴더에 비-CardData .tres가 있어도 스캔에 잡힐 수 있음 — 조용히 스킵.
		return null
	if data.card_name.is_empty():
		push_warning("CardRegistry: empty card_name at %s" % path)
		return null
	if data.color == 0:
		push_warning("CardRegistry: color unset on '%s' (%s)" % [data.card_name, path])
	if _by_id.has(data.id) and _by_id[data.id] != data:
		push_warning(
			"CardRegistry: duplicate id %d ('%s' vs '%s') at %s"
			% [data.id, (_by_id[data.id] as CardData).card_name, data.card_name, path]
		)
	if _by_name.has(data.card_name) and (_by_name[data.card_name] as CardData).id != data.id:
		push_warning(
			"CardRegistry: duplicate card_name '%s' (id %d overwritten by %d) at %s"
			% [data.card_name, (_by_name[data.card_name] as CardData).id, data.id, path]
		)
	_by_id[data.id] = data
	_by_name[data.card_name] = data
	return data


## 등록된 고유 card_name 수. ensure_loaded 전이거나 실패면 0.
static func catalog_count() -> int:
	return _by_name.size()


## Dedicated(8-A) 등: cards 루트 전량 동기 로드. 이미 끝났으면 no-op.
## on_progress(done, total, label) 선택 — 서버 로그용. UI await 없음(헤드리스).
static func ensure_loaded(on_progress: Callable = Callable()) -> void:
	if _loaded:
		if on_progress.is_valid():
			on_progress.call(1, 1, "")
		return
	_loaded = true
	var paths := _list_all_card_paths()
	if paths.is_empty():
		push_error("CardRegistry: no cards loaded (export DirAccess/remap?)")
		return
	var total: int = paths.size()
	var done := 0
	for path in paths:
		_load_card_at_path(path)
		done += 1
		if on_progress.is_valid():
			on_progress.call(done, total, path.get_file())
	if _by_name.is_empty():
		push_error("CardRegistry: no cards loaded after path scan")


## 전량 로드(프레임 양보). 덱 에디터 등 UI 게이트용. 이미 끝났으면 no-op.
## on_progress(done, total, label) 선택.
static func ensure_loaded_async(on_progress: Callable = Callable()) -> void:
	if _loaded:
		if on_progress.is_valid():
			on_progress.call(1, 1, "")
		return
	_loaded = true
	var paths := _list_all_card_paths()
	if paths.is_empty():
		push_error("CardRegistry: no cards loaded (export DirAccess/remap?)")
		return
	var total: int = paths.size()
	var done := 0
	var tree := Engine.get_main_loop() as SceneTree
	for path in paths:
		_load_card_at_path(path)
		done += 1
		if on_progress.is_valid():
			on_progress.call(done, total, path.get_file())
		if tree != null:
			await tree.process_frame
	if _by_name.is_empty():
		push_error("CardRegistry: no cards loaded after path scan")
	if on_progress.is_valid():
		on_progress.call(total, total, "")


## 필요한 card_name만 로드. cards 루트를 순회하며 파일마다 process_frame 양보.
## on_progress(done: int, total: int, label: String) 선택.
static func ensure_names_loaded(
	names: Array[String],
	on_progress: Callable = Callable()
) -> void:
	var needed: Dictionary = {}
	for card_name in unique_card_names(names):
		if not _by_name.has(card_name):
			needed[card_name] = true
	if needed.is_empty():
		if on_progress.is_valid():
			on_progress.call(1, 1, "")
		return

	var paths := _list_all_card_paths()
	var total: int = maxi(paths.size(), 1)
	var done := 0
	var tree := Engine.get_main_loop() as SceneTree
	for path in paths:
		if needed.is_empty():
			break
		var data := _load_card_at_path(path)
		if data != null and needed.has(data.card_name):
			needed.erase(data.card_name)
		done += 1
		if on_progress.is_valid():
			on_progress.call(done, total, path.get_file())
		if tree != null:
			await tree.process_frame

	if not needed.is_empty():
		push_warning(
			"CardRegistry: ensure_names_loaded missing %s" % str(needed.keys())
		)
	if on_progress.is_valid():
		on_progress.call(total, total, "")


## 이미 로드된 카드의 pipelines에서 StepSpawnToken 토큰 이름을 모은다 (token_card_id 우선→name).
static func collect_token_names_from_loaded(card_names: Array[String]) -> Array[String]:
	var ids := names_to_ids(card_names)
	return ids_to_names(collect_token_ids_from_loaded(ids))


## 이미 로드된 카드 pipelines에서 StepSpawnToken 토큰 id를 모은다. token_card_id>0 우선, else name→id.
static func collect_token_ids_from_loaded(card_ids: Array[int]) -> Array[int]:
	var seen: Dictionary = {}
	var out: Array[int] = []
	for card_id in unique_card_ids(card_ids):
		if not _by_id.has(card_id):
			continue
		var data: CardData = _by_id[card_id] as CardData
		if data == null:
			continue
		for pipeline in data.pipelines:
			if pipeline == null:
				continue
			for step in pipeline.steps:
				if not (step is StepSpawnToken):
					continue
				var tok_step := step as StepSpawnToken
				var tok_id := int(tok_step.token_card_id)
				if tok_id <= 0:
					var tok_name := String(tok_step.token_card_name).strip_edges()
					tok_id = name_to_id(tok_name)
				if tok_id <= 0 or seen.has(tok_id):
					continue
				seen[tok_id] = true
				out.append(tok_id)
	return out


## 덱 이름 ∪ 토큰 클로저까지 ensure_names_loaded (G4e-L1). 반환: 최종 스코프 고유 이름.
static func ensure_deck_union_tokens_loaded(
	deck_names: Array[String],
	on_progress: Callable = Callable()
) -> Array[String]:
	var scope_ids: Array[int] = await ensure_deck_union_tokens_loaded_ids(
		names_to_ids(deck_names),
		on_progress
	)
	return ids_to_names(scope_ids)


## 덱 id ∪ StepSpawnToken 토큰 클로저까지 ensure_ids_loaded. 반환: 최종 스코프 고유 id.
static func ensure_deck_union_tokens_loaded_ids(
	deck_ids: Array[int],
	on_progress: Callable = Callable()
) -> Array[int]:
	var pending: Array[int] = unique_card_ids(deck_ids)
	var scope_seen: Dictionary = {}
	var scope: Array[int] = []
	while not pending.is_empty():
		await ensure_ids_loaded(pending, on_progress)
		for card_id in pending:
			if scope_seen.has(card_id):
				continue
			scope_seen[card_id] = true
			scope.append(card_id)
		var next: Array[int] = []
		for tok_id in collect_token_ids_from_loaded(pending):
			if scope_seen.has(tok_id):
				continue
			next.append(tok_id)
		pending = unique_card_ids(next)
	return scope


## 단일 이름을 동기 로드한다 (안전망). cards 루트 순회.
static func _load_name_sync(card_name: String) -> void:
	if _by_name.has(card_name):
		return
	for path in _list_all_card_paths():
		var data := _load_card_at_path(path)
		if data != null and data.card_name == card_name:
			return


## 단일 id를 동기 로드한다 (안전망).
static func _load_id_sync(card_id: int) -> void:
	if card_id <= 0 or _by_id.has(card_id):
		return
	for path in _list_all_card_paths():
		var data := _load_card_at_path(path)
		if data != null and data.id == card_id:
			return


## id로 CardData 조회. 없으면 전량 로드 폴백 후 재조회.
static func get_by_id(id: int) -> CardData:
	if id <= 0:
		return null
	if _by_id.has(id):
		return _by_id[id] as CardData
	push_warning("CardRegistry: get_by_id miss %d — safety-net ensure_loaded" % id)
	_load_id_sync(id)
	if _by_id.has(id):
		return _by_id[id] as CardData
	ensure_loaded()
	return _by_id.get(id)


## 이름으로 CardData 조회. 미로드면 경고 후 해당 이름만 동기 로드.
static func get_by_name(name: String) -> CardData:
	if _by_name.has(name):
		return _by_name[name] as CardData
	push_warning("CardRegistry: get_by_name miss '%s' — safety-net load" % name)
	_load_name_sync(name)
	if _by_name.has(name):
		return _by_name[name] as CardData
	ensure_loaded()
	return _by_name.get(name)


## id → card_name. miss면 "".
static func id_to_name(card_id: int) -> String:
	var data := get_by_id(card_id)
	if data == null:
		return ""
	return String(data.card_name)


## card_name → id. miss면 0.
static func name_to_id(card_name: String) -> int:
	if card_name.is_empty():
		return 0
	var data := get_by_name(card_name)
	if data == null:
		return 0
	return int(data.id)


## 이름 배열 → id 배열 (순서 유지, miss는 스킵).
static func names_to_ids(card_names: Array) -> Array[int]:
	var out: Array[int] = []
	for item in card_names:
		var card_id := name_to_id(String(item))
		if card_id > 0:
			out.append(card_id)
	return out


## id 배열 → 이름 배열 (순서 유지, miss는 스킵).
static func ids_to_names(card_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for item in card_ids:
		var card_name := id_to_name(int(item))
		if not card_name.is_empty():
			out.append(card_name)
	return out


## id 목록에서 중복·비양수를 제거한 새 배열.
static func unique_card_ids(ids: Array) -> Array[int]:
	var seen: Dictionary = {}
	var out: Array[int] = []
	for item in ids:
		var card_id := int(item)
		if card_id <= 0 or seen.has(card_id):
			continue
		seen[card_id] = true
		out.append(card_id)
	return out


## 필요한 card id만 로드. 파일마다 process_frame 양보. on_progress(done,total,label) 선택.
static func ensure_ids_loaded(
	ids: Array[int],
	on_progress: Callable = Callable()
) -> void:
	var needed: Dictionary = {}
	for card_id in unique_card_ids(ids):
		if not _by_id.has(card_id):
			needed[card_id] = true
	if needed.is_empty():
		if on_progress.is_valid():
			on_progress.call(1, 1, "")
		return

	var paths := _list_all_card_paths()
	var total: int = maxi(paths.size(), 1)
	var done := 0
	var tree := Engine.get_main_loop() as SceneTree
	for path in paths:
		if needed.is_empty():
			break
		var data := _load_card_at_path(path)
		if data != null and needed.has(data.id):
			needed.erase(data.id)
		done += 1
		if on_progress.is_valid():
			on_progress.call(done, total, path.get_file())
		if tree != null:
			await tree.process_frame

	if not needed.is_empty():
		push_warning("CardRegistry: ensure_ids_loaded missing %s" % str(needed.keys()))
	if on_progress.is_valid():
		on_progress.call(total, total, "")


## 흑 기본 덱 이름 배열.
static func build_default_deck() -> Array[String]:
	return build_deck_for_color(DeckColor.BLACK)


## 흑 기본 덱 id 배열.
static func build_default_deck_ids() -> Array[int]:
	return build_deck_ids_for_color(DeckColor.BLACK)


## OptionButton 인덱스(0..4)를 DeckColor로 변환한다.
static func deck_color_from_option_index(index: int) -> DeckColor:
	match index:
		0:
			return DeckColor.BLACK
		1:
			return DeckColor.RED
		2:
			return DeckColor.BLUE
		3:
			return DeckColor.GREEN
		4:
			return DeckColor.WHITE
		_:
			return DeckColor.BLACK


## 색별 기본 덱 이름 배열을 복제해 반환한다.
static func build_deck_for_color(color: DeckColor) -> Array[String]:
	match color:
		DeckColor.BLACK:
			return _copy_deck_names(DEFAULT_DECK_BLACK)
		DeckColor.RED:
			return _copy_deck_names(DEFAULT_DECK_RED)
		DeckColor.WHITE:
			return _copy_deck_names(DEFAULT_DECK_WHITE)
		DeckColor.GREEN:
			return _copy_deck_names(DEFAULT_DECK_GREEN)
		DeckColor.BLUE:
			return _copy_deck_names(DEFAULT_DECK_BLUE)
		_:
			push_warning(
				"CardRegistry: deck color %s not implemented yet — using BLACK default deck"
				% DeckColor.keys()[color]
			)
			return _copy_deck_names(DEFAULT_DECK_BLACK)


## 색별 기본 덱 id 배열. 이름 상수를 id로 변환한다.
static func build_deck_ids_for_color(color: DeckColor) -> Array[int]:
	return names_to_ids(build_deck_for_color(color))


## "black"|"red"|… → DeckColor. 모르면 BLACK.
static func deck_color_from_key(key: String) -> DeckColor:
	match key.strip_edges().to_lower():
		"black":
			return DeckColor.BLACK
		"red":
			return DeckColor.RED
		"blue":
			return DeckColor.BLUE
		"green":
			return DeckColor.GREEN
		"white":
			return DeckColor.WHITE
		_:
			return DeckColor.BLACK


## DeckColor → "black" 등 소문자 키.
static func deck_color_key(color: DeckColor) -> String:
	match color:
		DeckColor.BLACK:
			return "black"
		DeckColor.RED:
			return "red"
		DeckColor.BLUE:
			return "blue"
		DeckColor.GREEN:
			return "green"
		DeckColor.WHITE:
			return "white"
		_:
			return "black"


## "black" 등 → CardData.color 비트. 모르면 0.
static func color_flag_for_key(key: String) -> int:
	match key.strip_edges().to_lower():
		"black":
			return COLOR_FLAG_BLACK
		"white":
			return COLOR_FLAG_WHITE
		"green":
			return COLOR_FLAG_GREEN
		"red":
			return COLOR_FLAG_RED
		"blue":
			return COLOR_FLAG_BLUE
		"colorless":
			return COLOR_FLAG_COLORLESS
		_:
			return 0


## CardData.color 비트. null/미기입이면 0.
static func _color_flags_of(data: CardData) -> int:
	if data == null:
		return 0
	return data.color


## 카드의 대표 색 키. COLORLESS만·미기입이면 "". 필요 시 로드.
static func color_key_for_card_name(card_name: String) -> String:
	var data := get_by_name(card_name)
	var flags := _color_flags_of(data)
	var chromatic := flags & ~COLOR_FLAG_COLORLESS
	if chromatic == 0:
		return ""
	for key in ["black", "white", "green", "red", "blue"]:
		if (chromatic & color_flag_for_key(key)) != 0:
			return key
	return ""


## COLORLESS 플래그 여부. 필요 시 로드.
static func is_colorless_name(card_name: String) -> bool:
	var data := get_by_name(card_name)
	return (_color_flags_of(data) & COLOR_FLAG_COLORLESS) != 0


## mono 덱에 넣을 수 있는지: base 색 비트 또는 COLORLESS.
static func card_allowed_in_mono(card_name: String, base_color_key: String) -> bool:
	var data := get_by_name(card_name)
	var flags := _color_flags_of(data)
	if (flags & COLOR_FLAG_COLORLESS) != 0:
		return true
	var base_flag := color_flag_for_key(base_color_key)
	if base_flag == 0:
		return false
	return (flags & base_flag) != 0


## 해당 색(+optional COLORLESS) 카드 이름을 모은다. 색은 CardData.color 기준.
static func list_card_names_for_filter(color_key: String, include_colorless: bool = true) -> Array[String]:
	var want := color_key.strip_edges().to_lower()
	# 플래그로 분류하려면 전량 로드가 필요 (폴더≠색일 수 있음).
	ensure_loaded()
	var want_flag := color_flag_for_key(want)
	var out: Array[String] = []
	for card_name in _by_name.keys():
		var name := String(card_name)
		var data: CardData = _by_name[name] as CardData
		var flags := _color_flags_of(data)
		if want == "all" or want.is_empty():
			out.append(name)
			continue
		if want == "colorless":
			if (flags & COLOR_FLAG_COLORLESS) != 0:
				out.append(name)
			continue
		if want_flag != 0 and (flags & want_flag) != 0:
			out.append(name)
		elif include_colorless and (flags & COLOR_FLAG_COLORLESS) != 0:
			out.append(name)
	out.sort()
	return out


## black|red|…|colorless 키인지.
static func _is_known_color_key(key: String) -> bool:
	return key in ["black", "red", "blue", "green", "white", "colorless"]
