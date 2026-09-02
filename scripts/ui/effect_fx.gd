class_name EffectFx
extends RefCounted
## 효과 결과 연출 (스탯 modify 등). ActivationFx(발동)·MatchVfx(이동)와 분리.
## 계약: await_modify_stat / await_line_wave(..., apply_cb) — 기류 시작 직전에 apply_cb(스탯).
## 복수 지정: 투사체·기류 동시. 자동 광역: await_line_wave(라인별 곡선 파면).
## Dedicated/headless no-op(+apply_cb만 실행).


static var _presenter: RefCounted = null


## 연출 구현체를 교체한다. null이면 다음 play 때 Default로 되돌린다.
static func set_presenter(presenter: RefCounted) -> void:
	_presenter = presenter


## 현재 presenter. 없으면 EffectFxDefault를 만든다.
static func get_presenter() -> RefCounted:
	if _presenter == null:
		_presenter = EffectFxDefault.new()
	return _presenter


## headless·미표시면 연출 생략.
static func is_active() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return true


## 스탯 연출. apply_cb는 기류 시작 직전에 호출(스탯 적용 통일).
## opts: color · particle_count · skip_hit · self_cast
static func await_modify_stat(
	source: Node,
	targets: Array,
	delta: int,
	opts: Dictionary = {},
	apply_cb: Callable = Callable()
) -> void:
	var valid := _filter_targets(targets)
	if delta == 0 or valid.is_empty():
		if apply_cb.is_valid():
			apply_cb.call()
		return
	if not is_active():
		if apply_cb.is_valid():
			apply_cb.call()
		return
	var presenter := get_presenter()
	if presenter == null or not presenter.has_method("await_modify_stat"):
		if apply_cb.is_valid():
			apply_cb.call()
		return
	await presenter.await_modify_stat(source, valid, delta, opts, apply_cb)


## 기류만 동시 재생. delta 부호로 상승/하강.
static func await_aura_batch(
	targets: Array,
	delta: int,
	opts: Dictionary = {},
	apply_cb: Callable = Callable()
) -> void:
	var valid := _filter_targets(targets)
	if delta == 0 or valid.is_empty():
		if apply_cb.is_valid():
			apply_cb.call()
		return
	if not is_active():
		if apply_cb.is_valid():
			apply_cb.call()
		return
	var presenter := get_presenter()
	if presenter == null or not presenter.has_method("await_aura_batch"):
		if apply_cb.is_valid():
			apply_cb.call()
		return
	await presenter.await_aura_batch(valid, delta, opts, apply_cb)


## 광역 라인 웨이브(시전자→라인 그룹) 후 기류. apply_cb는 기류 직전.
## opts: wave_color · wave_width · wave_sec · wave_aperture_rad · …
static func await_line_wave(
	source: Node,
	targets: Array,
	delta: int,
	opts: Dictionary = {},
	apply_cb: Callable = Callable()
) -> void:
	var valid := _filter_targets(targets)
	if delta == 0 or valid.is_empty():
		if apply_cb.is_valid():
			apply_cb.call()
		return
	if not is_active():
		if apply_cb.is_valid():
			apply_cb.call()
		return
	var presenter := get_presenter()
	if presenter == null or not presenter.has_method("await_line_wave"):
		if apply_cb.is_valid():
			apply_cb.call()
		return
	await presenter.await_line_wave(source, valid, delta, opts, apply_cb)


## Node2D 유효 타겟만.
static func _filter_targets(targets: Array) -> Array:
	var valid: Array = []
	for t in targets:
		if t != null and is_instance_valid(t) and t is Node2D:
			valid.append(t)
	return valid
