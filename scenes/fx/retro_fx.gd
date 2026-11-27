extends CanvasLayer
## Autoload. Draws the retro post-process between the 3D frame and the HUD (HUD layers are 1+).
## F3 toggles the effect. flash() tints the frame for heavy impacts without strobing.

const SHADER := preload("res://scenes/fx/retro.gdshader")
const MAX_FLASHES_PER_SECOND := 3.0

var enabled: bool = true:
	set(value):
		enabled = value
		if _rect != null:
			_rect.visible = value

var _rect: ColorRect
var _material: ShaderMaterial
var _flash: float
var _last_flash_ms: int = -100000
var _veil: ColorRect


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "RetroScreen"
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		enabled = not enabled


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / maxf(Engine.time_scale, 0.05) * 5.0)
		_material.set_shader_parameter(&"flash", _flash)


## Fades the screen to a colour, runs midpoint (a teleport or a scene change) while covered,
## then fades back. A slow fade, not a flash: safe for photosensitive players.
func pass_through(color: Color, midpoint: Callable, half: float = 0.45) -> void:
	if _veil == null:
		_veil = ColorRect.new()
		_veil.name = "Veil"
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_veil)
	_veil.color = Color(color, 0.0)
	var tween := create_tween()
	tween.tween_property(_veil, ^"color:a", 1.0, half).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(midpoint)
	tween.tween_interval(0.2)
	tween.tween_property(_veil, ^"color:a", 0.0, half * 1.6).set_trans(Tween.TRANS_SINE)


## Brief full-screen tint. Rate-limited to stay under three flashes per second (WCAG 2.3.1).
func flash(strength: float, color: Color = Color(1.0, 0.55, 0.3)) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_flash_ms < 1000.0 / MAX_FLASHES_PER_SECOND:
		return
	_last_flash_ms = now
	_flash = clampf(strength, 0.0, 0.35)
	_material.set_shader_parameter(&"flash_color", color)
	_material.set_shader_parameter(&"flash", _flash)


func set_parameter(parameter: StringName, value: Variant) -> void:
	_material.set_shader_parameter(parameter, value)


## Puff of grey-violet dust cells at a world position (feet on a skid, landing, roll end).
func dust(at: Vector3, amount: int = 10, spread: float = 0.35) -> void:
	_mark(&"fx:dust")
	var particles := _burst(_dust_mesh(), amount, 0.55, spread)
	if particles == null:
		return
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.gravity = Vector3(0, -1.5, 0)
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 1.4
	particles.damping_min = 2.0
	particles.damping_max = 3.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.3
	_place(particles, at + Vector3.UP * 0.08, 0.8)


## Bright cells thrown from a blade's contact point.
func sparks(at: Vector3, color: Color, count: int) -> void:
	_mark(&"fx:sparks")
	var particles := _burst(_spark_mesh(color), count, 0.31, 0.0)
	if particles == null:
		return
	particles.explosiveness = 0.98
	particles.spread = 130.0
	particles.direction = Vector3.UP
	particles.gravity = Vector3(0.0, -8.0, 0.0)
	particles.initial_velocity_min = 2.3
	particles.initial_velocity_max = 4.8
	_place(particles, at, 0.42)


## Flat ring that races outward from a slam or a nova, then fades.
func shockwave(at: Vector3, radius: float, color: Color = Color(1.0, 0.62, 0.3)) -> void:
	_mark(&"fx:shockwave")
	var scene := get_tree().current_scene as Node3D
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh()
	var mat := _ring_material(color).duplicate() as StandardMaterial3D
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tweened every rendered frame, so it must not be physics-interpolated.
	ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(ring)
	ring.global_position = Vector3(at.x, at.y + 0.1, at.z)
	ring.scale = Vector3(0.2, 0.25, 0.2)
	var tween := ring.create_tween()
	tween.tween_property(ring, ^"scale", Vector3(radius, 0.25, radius), 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(mat, ^"albedo_color:a", 0.0, 0.4)
	tween.tween_callback(ring.queue_free)
	dust(at, 18, radius * 0.5)


## Draws each effect once, just in front of the camera, while a level loads: the renderer
## builds their shader and pipeline state then, not during the first jump or hit.
func prewarm(camera: Camera3D) -> void:
	if camera == null:
		return
	var at := camera.global_position - camera.global_basis.z * 2.5 + Vector3.DOWN * 0.6
	dust(at, 1)
	sparks(at, Color(1.0, 0.64, 0.42), 1)
	shockwave(at, 0.3)


var _dust_mesh_cache: BoxMesh
var _spark_meshes: Dictionary = {}
var _ring_mesh_cache: TorusMesh
var _ring_materials: Dictionary = {}


func _dust_mesh() -> BoxMesh:
	if _dust_mesh_cache == null:
		_dust_mesh_cache = BoxMesh.new()
		_dust_mesh_cache.size = Vector3(0.07, 0.07, 0.07)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.5, 0.58, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mesh_cache.material = mat
	return _dust_mesh_cache


func _spark_mesh(color: Color) -> BoxMesh:
	var key := color.to_html()
	if not _spark_meshes.has(key):
		var dot := BoxMesh.new()
		dot.size = Vector3(0.045, 0.072, 0.045)
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = color
		dot.material = glow
		_spark_meshes[key] = dot
	return _spark_meshes[key]


func _ring_mesh() -> TorusMesh:
	if _ring_mesh_cache == null:
		_ring_mesh_cache = TorusMesh.new()
		_ring_mesh_cache.inner_radius = 0.82
		_ring_mesh_cache.outer_radius = 1.0
		_ring_mesh_cache.rings = 24
		_ring_mesh_cache.ring_segments = 4
	return _ring_mesh_cache


func _ring_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _ring_materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color
		_ring_materials[key] = mat
	return _ring_materials[key]


func _burst(mesh: Mesh, amount: int, lifetime: float, spread: float) -> CPUParticles3D:
	if get_tree().current_scene == null:
		return null
	var particles := CPUParticles3D.new()
	particles.mesh = mesh
	particles.amount = maxi(amount, 1)
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.9
	if spread > 0.0:
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = spread
	particles.emitting = false
	particles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return particles


func _place(particles: CPUParticles3D, at: Vector3, life: float) -> void:
	get_tree().current_scene.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(life).timeout.connect(particles.queue_free)


func _mark(label: StringName) -> void:
	var perf := get_node_or_null(^"/root/Perf")
	if perf != null:
		perf.mark(label)
