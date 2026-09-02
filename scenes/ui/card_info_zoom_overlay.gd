class_name CardInfoZoomOverlay
extends CanvasLayer
## 카드 정보 사이드바용 확대 오버레이.
## 딤 색·레이어·줌 이미지 최소 크기는 이 씬에서 조정한다.


signal dismiss_requested

const _TILT_SHADER_PATH := "res://shaders/card_rigid_tilt.gdshader"
const _MAX_TILT_DEG := 12.0
const _FOLLOW_STIFFNESS := 28.0
const _SETTLE_EPS := 0.04

@onready var zoom_root: Control = $ZoomRoot
@onready var zoom_image: TextureRect = $ZoomRoot/Center/ZoomImage

var _tilt_mat: ShaderMaterial
var _tilt_x: float = 0.0
var _tilt_y: float = 0.0
var _hovering: bool = false
var _rarity_tier: int = CardRarity.Tier.N


func _ready() -> void:
	layer = 90
	if zoom_root:
		zoom_root.visible = false
		if not zoom_root.gui_input.is_connected(_on_root_gui_input):
			zoom_root.gui_input.connect(_on_root_gui_input)
	if zoom_image:
		if not zoom_image.gui_input.is_connected(_on_image_gui_input):
			zoom_image.gui_input.connect(_on_image_gui_input)
		zoom_image.mouse_entered.connect(_on_image_mouse_entered)
		zoom_image.mouse_exited.connect(_on_image_mouse_exited)
		_setup_tilt_material()
	set_process(false)


func _process(delta: float) -> void:
	var target_x := 0.0
	var target_y := 0.0
	if _hovering and zoom_image != null:
		var img_size := zoom_image.size
		if img_size.x > 1.0 and img_size.y > 1.0:
			var local := zoom_image.get_local_mouse_position()
			var nx := clampf(local.x / (img_size.x * 0.5) - 1.0, -1.0, 1.0)
			var ny := clampf(local.y / (img_size.y * 0.5) - 1.0, -1.0, 1.0)
			target_y = nx * _MAX_TILT_DEG
			target_x = -ny * _MAX_TILT_DEG

	var t := 1.0 - exp(-_FOLLOW_STIFFNESS * delta)
	_tilt_x = lerpf(_tilt_x, target_x, t)
	_tilt_y = lerpf(_tilt_y, target_y, t)
	_apply_tilt(_tilt_x, _tilt_y)

	if not _hovering and absf(_tilt_x) < _SETTLE_EPS and absf(_tilt_y) < _SETTLE_EPS:
		_tilt_x = 0.0
		_tilt_y = 0.0
		_apply_tilt(0.0, 0.0)
		set_process(false)


## 텍스처·최소 크기·카피 등급을 넣고 오버레이를 표시한다.
func show_texture(
	tex: Texture2D,
	min_size: Vector2,
	p_rarity: int = CardRarity.Tier.N
) -> void:
	if zoom_image == null:
		zoom_image = get_node_or_null("ZoomRoot/Center/ZoomImage") as TextureRect
	if zoom_root == null:
		zoom_root = get_node_or_null("ZoomRoot") as Control
	if zoom_image:
		zoom_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		zoom_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		zoom_image.texture = tex
		zoom_image.custom_minimum_size = min_size
		zoom_image.size = min_size
		if _tilt_mat == null:
			_setup_tilt_material()
	if zoom_root:
		zoom_root.visible = true
	_tilt_x = 0.0
	_tilt_y = 0.0
	_apply_tilt(0.0, 0.0)
	_apply_rarity(p_rarity)


## 오버레이를 숨긴다.
func hide_overlay() -> void:
	if zoom_root and is_instance_valid(zoom_root):
		zoom_root.visible = false
	_hovering = false
	set_process(false)


## 현재 표시 중인지.
func is_overlay_visible() -> bool:
	return zoom_root != null and is_instance_valid(zoom_root) and zoom_root.visible


func _on_image_mouse_entered() -> void:
	_hovering = true
	set_process(true)


func _on_image_mouse_exited() -> void:
	_hovering = false


func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dismiss_requested.emit()
			zoom_root.accept_event()


func _on_image_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss_requested.emit()
		zoom_image.accept_event()


func _setup_tilt_material() -> void:
	var shader := load(_TILT_SHADER_PATH) as Shader
	if shader == null:
		push_error("CardInfoZoomOverlay: failed to load tilt shader")
		return
	_tilt_mat = ShaderMaterial.new()
	_tilt_mat.shader = shader
	_tilt_mat.set_shader_parameter("corner_origin", 1.0)
	CardRarityFoil.bind_holo_maps(_tilt_mat)
	zoom_image.material = _tilt_mat
	# card_half_size는 실제 렌더 크기 기준 — 레이아웃 후 갱신.
	zoom_image.resized.connect(_on_zoom_image_resized)


func _on_zoom_image_resized() -> void:
	if _tilt_mat == null:
		return
	_tilt_mat.set_shader_parameter("card_half_size", zoom_image.size * 0.5)


func _apply_tilt(tx: float, ty: float) -> void:
	if _tilt_mat == null:
		return
	_tilt_mat.set_shader_parameter("tilt_x_deg", tx)
	_tilt_mat.set_shader_parameter("tilt_y_deg", ty)


## instance_rarity를 ZoomImage material에 반영 (아웃라인, 힌트 글로우 없음).
func _apply_rarity(tier: int) -> void:
	_rarity_tier = clampi(tier, CardRarity.Tier.N, CardRarity.Tier.UR)
	if _tilt_mat == null:
		return
	var show_fx := CardRarity.shows_display(_rarity_tier)
	_tilt_mat.set_shader_parameter(
		"rarity_tier",
		float(_rarity_tier if show_fx else CardRarity.Tier.N)
	)
	_tilt_mat.set_shader_parameter("rarity_hint", 0.0)
	var accent := CardRarity.accent_of(_rarity_tier)
	_tilt_mat.set_shader_parameter(
		"rarity_accent",
		Vector4(accent.r, accent.g, accent.b, accent.a)
	)
