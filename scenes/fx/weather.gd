extends Node
## Autoload "Weather". One wind and rain model shared by everything that reacts to it.
##
## Wind blows from a base direction with gusts every few seconds. Gusts drive leaves, twigs
## and ash around the camera, swell the wind sound, flap the hero's cape and now and then send
## a branch tumbling through the view. Rain falls slanted by the wind with splashes around the
## player, makes stone glossy so lanterns glint off it, and storms bring lightning followed by
## thunder. Each area picks a preset; changing area eases from one to the other.

const PRESETS := {
	&"clear": {"wind": 0.25, "gusts": 0.4, "rain": 0.0, "storm": 0.0, "debris": 0.4},
	&"court": {"wind": 0.45, "gusts": 0.8, "rain": 0.25, "storm": 0.0, "debris": 1.0},
	&"ruins": {"wind": 0.65, "gusts": 1.0, "rain": 0.85, "storm": 1.0, "debris": 0.8},
}
const RAIN_LOOP := "res://assets/audio/ambience/rain.ogg"
const THUNDER := ["res://assets/audio/ambience/thunder_0.ogg", "res://assets/audio/ambience/thunder_1.ogg"]
const GUST := "res://assets/audio/ambience/gust.ogg"
const BOX := Vector3(26.0, 9.0, 26.0)

## Horizontal wind direction (unit) and current strength 0..1 including gusts.
var wind_direction := Vector3(0.8, 0.0, -0.6).normalized()
var wind: float
## 0..1 strength of the gust in progress, for cloth and sound.
var gust: float
var rain: float
## 0..1 wetness of surfaces; lags the rain.
var wet: float
var enabled: bool = true

var _target: Dictionary = PRESETS[&"clear"]
var _base_wind: float = 0.25
var _gust_timer: float = 4.0
var _gust_length: float
var _gust_age: float = 99.0
var _rain_phase: float
var _lightning_timer: float = 14.0
var _flash: float
var _thunder_delay: float = -1.0
var _debris: CPUParticles3D
var _ash: CPUParticles3D
var _rain_drops: CPUParticles3D
var _splashes: CPUParticles3D
var _rain_player: AudioStreamPlayer
var _gust_player: AudioStreamPlayer
var _thunder_player: AudioStreamPlayer
var _wet_materials: Array[BaseMaterial3D] = []
var _dry_roughness: Array[float] = []
var _moon: DirectionalLight3D
var _moon_energy: float


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_debris = _emitter("Debris", 70, 5.0, _debris_mesh())
	_ash = _emitter("Ash", 120, 6.0, _ash_mesh())
	_rain_drops = _emitter("Rain", 900, 0.9, _drop_mesh())
	_rain_drops.emission_box_extents = Vector3(BOX.x * 0.5, 0.5, BOX.z * 0.5)
	_rain_drops.angular_velocity_min = 0.0
	_rain_drops.angular_velocity_max = 0.0
	_rain_drops.particle_flag_rotate_y = false
	_rain_drops.particle_flag_align_y = true
	_splashes = _emitter("Splashes", 160, 0.25, _splash_mesh())
	_splashes.emission_box_extents = Vector3(7.0, 0.05, 7.0)
	_splashes.gravity = Vector3(0, -6, 0)
	_splashes.direction = Vector3.UP
	_splashes.spread = 70.0
	_splashes.initial_velocity_min = 0.8
	_splashes.initial_velocity_max = 1.6
	_rain_player = _loop(RAIN_LOOP, &"Ambience")
	_gust_player = _loop(GUST, &"Ambience")
	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.bus = &"Ambience"
	add_child(_thunder_player)


## Eases toward an area's weather. Rain and wetness follow over several seconds.
func set_preset(name: StringName) -> void:
	_target = PRESETS.get(name, PRESETS[&"clear"])
	_rain_phase = randf() * TAU


## Area controllers hand over the moon and the materials that get glossy in the rain.
func bind_area(root: Node) -> void:
	_wet_materials.clear()
	_dry_roughness.clear()
	_moon = null
	for light in root.get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
		_moon = light
		_moon_energy = light.light_energy
		break
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and not _wet_materials.has(material) and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				_wet_materials.append(material)
				_dry_roughness.append(material.roughness)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var show := enabled and camera != null
	for emitter in [_debris, _ash, _rain_drops, _splashes]:
		emitter.visible = show
	if not show:
		_rain_player.volume_db = -80.0
		_gust_player.volume_db = -80.0
		return
	_update_wind(delta)
	_update_rain(delta)
	_update_storm(delta)
	var center := camera.global_position
	_debris.global_position = center + Vector3(0, 1.0, 0) - wind_direction * 6.0
	_ash.global_position = center + Vector3(0, 2.0, 0) - wind_direction * 6.0
	_rain_drops.global_position = center + Vector3(0, 8.0, 0) - wind_direction * wind * 3.0
	var ground := camera.global_position
	ground.y = 0.06
	_splashes.global_position = ground - camera.global_basis.z * 4.0
	var push := wind_direction * (2.0 + wind * 9.0)
	_debris.gravity = Vector3(0, -1.2, 0) + push * 0.9
	_ash.gravity = Vector3(0, -0.25, 0) + push * 0.6
	# CPUParticles3D has no amount ratio: intensity is emission on/off plus particle opacity.
	var leaves := float(_target["debris"]) * (0.25 + gust)
	_debris.emitting = leaves > 0.2
	_debris.speed_scale = 0.7 + gust * 0.8
	_ash.emitting = true
	_ash.speed_scale = 0.6 + wind * 0.8
	_rain_drops.emitting = rain > 0.04
	_splashes.emitting = rain > 0.2
	_set_alpha(_rain_drops, 0.15 + 0.4 * rain)
	_set_alpha(_splashes, 0.2 + 0.45 * rain)
	_rain_drops.gravity = Vector3(0, -22.0, 0) + wind_direction * (4.0 + wind * 10.0)
	_rain_player.volume_db = linear_to_db(maxf(rain * 0.9, 0.0005))
	_gust_player.volume_db = linear_to_db(maxf(gust * 0.85 + wind * 0.2, 0.0005)) - 3.0


func _update_wind(delta: float) -> void:
	_base_wind = move_toward(_base_wind, _target["wind"], delta * 0.1)
	_gust_timer -= delta
	if _gust_timer <= 0.0:
		_gust_timer = randf_range(6.0, 14.0)
		_gust_length = randf_range(1.8, 3.4)
		_gust_age = 0.0
		wind_direction = wind_direction.rotated(Vector3.UP, randf_range(-0.35, 0.35))
		if float(_target["gusts"]) > 0.6 and randf() < 0.6:
			_send_branch.call_deferred()
	_gust_age += delta
	var envelope := 0.0
	if _gust_age < _gust_length:
		envelope = sin(PI * _gust_age / _gust_length)
	gust = envelope * float(_target["gusts"])
	wind = clampf(_base_wind + gust * 0.6 + 0.05 * sin(Time.get_ticks_msec() * 0.0013), 0.0, 1.0)


func _update_rain(delta: float) -> void:
	# Showers come and go around the preset's level.
	_rain_phase += delta * 0.03
	var level := float(_target["rain"]) * clampf(0.55 + 0.6 * sin(_rain_phase), 0.0, 1.0)
	rain = move_toward(rain, level, delta * 0.08)
	wet = move_toward(wet, 1.0 if rain > 0.15 else 0.0, delta * (0.06 if rain > 0.15 else 0.02))
	for i in _wet_materials.size():
		_wet_materials[i].roughness = lerpf(_dry_roughness[i], 0.28, wet * 0.85)


func _update_storm(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		if is_instance_valid(_moon):
			_moon.light_energy = _moon_energy * (1.0 + _flash * 3.5)
	if _thunder_delay >= 0.0:
		_thunder_delay -= delta
		if _thunder_delay < 0.0:
			_thunder_player.stream = load(THUNDER[randi() % THUNDER.size()])
			_thunder_player.volume_db = randf_range(-4.0, 0.0)
			_thunder_player.play()
	if float(_target["storm"]) <= 0.0 or rain < 0.4:
		return
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = randf_range(11.0, 26.0)
		_flash = 1.0
		RetroFX.flash(0.22, Color(0.75, 0.8, 1.0))
		_thunder_delay = randf_range(0.5, 2.4)


## A broken branch tumbles across the view on a strong gust.
func _send_branch() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or get_tree().current_scene == null:
		return
	var branch := MeshInstance3D.new()
	branch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var stick := BoxMesh.new()
	stick.size = Vector3(0.06, 0.06, randf_range(0.6, 1.1))
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.16, 0.11, 0.1)
	stick.material = bark
	branch.mesh = stick
	for k in 2:
		var twig := MeshInstance3D.new()
		var twig_mesh := BoxMesh.new()
		twig_mesh.size = Vector3(0.03, 0.03, 0.35)
		twig_mesh.material = bark
		twig.mesh = twig_mesh
		branch.add_child(twig)
		twig.position = Vector3(0, 0, -0.2 + k * 0.35)
		twig.rotation = Vector3(0.6 - k * 1.2, 0.7, 0)
	get_tree().current_scene.add_child(branch)
	var side := camera.global_basis.x * (1.0 if wind_direction.dot(camera.global_basis.x) < 0.0 else -1.0)
	var start := camera.global_position - camera.global_basis.z * randf_range(5.0, 9.0) + side * 7.0 + Vector3.UP * randf_range(0.5, 2.5)
	branch.global_position = start
	var end := start - side * 14.0 + wind_direction * 3.0 + Vector3.DOWN * 1.5
	var tween := branch.create_tween()
	tween.tween_property(branch, ^"global_position", end, 2.2).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(branch, ^"rotation", Vector3(randf_range(8, 14), randf_range(4, 9), 3.0), 2.2)
	tween.tween_callback(branch.queue_free)


func _emitter(label: String, amount: int, lifetime: float, mesh: Mesh) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = label
	particles.mesh = mesh
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = BOX * 0.5
	particles.direction = Vector3(0, -1, 0)
	particles.spread = 25.0
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 2.0
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	particles.particle_flag_rotate_y = true
	particles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	particles.emitting = false
	add_child(particles)
	return particles


func _set_alpha(particles: CPUParticles3D, alpha: float) -> void:
	var material := particles.mesh.surface_get_material(0) as StandardMaterial3D
	if material != null:
		material.albedo_color.a = alpha


func _loop(path: String, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := load(path)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	player.stream = stream
	player.bus = bus
	player.volume_db = -80.0
	player.autoplay = false
	add_child(player)
	player.play()
	return player


func _unlit(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _debris_mesh() -> Mesh:
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.09, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.2, 0.14)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	leaf.material = mat
	return leaf


func _ash_mesh() -> Mesh:
	var flake := BoxMesh.new()
	flake.size = Vector3(0.025, 0.025, 0.025)
	flake.material = _unlit(Color(0.72, 0.66, 0.78, 0.8))
	return flake


func _drop_mesh() -> Mesh:
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.42, 0.012)
	drop.material = _unlit(Color(0.62, 0.72, 0.95, 0.45))
	return drop


func _splash_mesh() -> Mesh:
	var splash := BoxMesh.new()
	splash.size = Vector3(0.03, 0.03, 0.03)
	splash.material = _unlit(Color(0.7, 0.8, 1.0, 0.6))
	return splash
