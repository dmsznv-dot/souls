extends Node
## Living fire for the parent light: the one owner of its light_energy. Visible flame, the glow
## of the source (lantern glass, embers) and the light on the surroundings share one envelope:
## a slow swell (0.4-0.9 Hz) and a small unevenness (1.2-2.2 Hz) with their own phase per
## source, a quick dip on each gust that eases back over half a second, and for lanterns the odd
## gutter. The hot point drifts a few centimetres downwind from where the light was placed and
## the flames lean with the wind. Sheltered fires (lanterns) feel the wind less.
##
## Profiles: lantern (closed glass), torch (open flame), bonfire. A bonfire's tween changes
## ignition (0..1); the energy written each frame is base_energy x ignition x envelope.

const PROFILES := {
	# [swell amplitude, unevenness amplitude, drift m, gust dip, wind share, flame lean degrees, gutters]
	&"lantern": [0.05, 0.03, 0.02, 0.10, 0.3, 0.0, true],
	&"torch": [0.1, 0.06, 0.06, 0.18, 1.0, 22.0, false],
	&"bonfire": [0.08, 0.05, 0.07, 0.12, 0.6, 14.0, false],
}

var profile: StringName = &"lantern"
var base_energy: float
## 0..1, how far a fire has caught. Multiplies the energy and the source glow.
var ignition: float = 1.0
var _origin: Vector3
var _seed: float
var _clock: float
var _swell_hz: float
var _jitter_hz: float
var _gutter: float
var _gust_dip: float
var _flames: Array[CPUParticles3D] = []
var _glows: Array[BaseMaterial3D] = []
var _glow_base: Array[float] = []
var _flame_base: Array[Vector3] = []


func _ready() -> void:
	var light := get_parent() as Light3D
	base_energy = light.light_energy
	_origin = light.position
	if profile == &"lantern" and light.name.begins_with("WatchFire"):
		profile = &"torch"
	_seed = float(hash(str(light.get_path())) % 10000) / 10000.0
	_clock = _seed * 100.0
	_swell_hz = lerpf(0.4, 0.9, fposmod(_seed * 7.13, 1.0))
	_jitter_hz = lerpf(1.2, 2.2, fposmod(_seed * 3.71, 1.0))
	_find_parts(light.get_parent())


## Sets the light's resting energy (colour and range are set before, by the caller).
func set_base_energy(energy: float) -> void:
	base_energy = energy


## The flames and glowing parts that belong to this fire: siblings of the light named Flames,
## Glass or Embers. Each glow gets its own material copy so fires do not pulse in unison.
func _find_parts(holder: Node) -> void:
	if holder == null:
		return
	for child in holder.get_children():
		if child is CPUParticles3D and (String(child.name).contains("Flames") or child.name == &"Sparks"):
			_flames.append(child)
			_flame_base.append((child as CPUParticles3D).direction)
		elif child is MeshInstance3D and (child.name == &"Glass" or child.name == &"Embers"):
			var material := (child as MeshInstance3D).material_override as BaseMaterial3D
			if material != null:
				material = material.duplicate()
				(child as MeshInstance3D).material_override = material
				_glows.append(material)
				_glow_base.append(material.albedo_color.v)
		elif child is Node3D and child.name == &"Fire":
			_find_parts(child)


func _process(delta: float) -> void:
	var light := get_parent() as Light3D
	var shape: Array = PROFILES.get(profile, PROFILES[&"lantern"])
	_clock += delta
	var weather := get_node_or_null(^"/root/Weather")
	var gust: float = weather.gust if weather != null else 0.0
	var wind: float = weather.wind if weather != null else 0.0
	var wind_dir: Vector3 = weather.wind_direction if weather != null else Vector3.ZERO
	var share: float = shape[4]
	# A gust drops the energy quickly and lets it recover over 0.3-0.7 s.
	var dip_target: float = gust * share
	_gust_dip = lerpf(_gust_dip, dip_target, 1.0 - exp(-(14.0 if dip_target > _gust_dip else 2.2) * delta))
	if shape[6] and _gutter <= 0.0 and randf() < delta * 0.18:
		_gutter = randf_range(0.3, 0.6)
	_gutter = maxf(0.0, _gutter - delta)
	var swell := sin(_clock * TAU * _swell_hz)
	var jitter := sin(_clock * TAU * _jitter_hz + _seed * 9.0) * 0.6 + sin(_clock * TAU * _jitter_hz * 1.7 + 2.0) * 0.4
	var envelope := 1.0 + float(shape[0]) * swell + float(shape[1]) * jitter - float(shape[3]) * _gust_dip
	if _gutter > 0.0:
		envelope -= 0.3 * sin(PI * _gutter / 0.6)
	light.light_energy = base_energy * ignition * maxf(envelope, 0.2)
	# The hot point drifts downwind of where it was placed, never wandering off.
	var local_wind := Vector3.ZERO
	if light.get_parent() is Node3D and wind_dir != Vector3.ZERO:
		local_wind = (light.get_parent() as Node3D).global_basis.inverse() * wind_dir
		local_wind.y = 0.0
	var drift: float = shape[2]
	var wobble := Vector3(sin(_clock * 3.1 + _seed * 5.0), 0.0, cos(_clock * 2.7 + _seed * 3.0)) * 0.3
	light.position = _origin + (local_wind * (wind * share + _gust_dip) + wobble * 0.2) * drift * 2.0
	# Flames lean with the wind, fixed at their base.
	var lean := deg_to_rad(float(shape[5])) * clampf(wind * share + _gust_dip, 0.0, 1.0)
	for i in _flames.size():
		var flame := _flames[i]
		if not is_instance_valid(flame):
			continue
		var tilt := local_wind * tan(lean) if local_wind != Vector3.ZERO else Vector3.ZERO
		flame.direction = (_flame_base[i] + tilt).normalized()
		flame.gravity = Vector3(tilt.x * 2.0, 1.8, tilt.z * 2.0)
		flame.emitting = ignition > 0.3
	# Glass and embers glow with a smaller swing.
	for i in _glows.size():
		var glow := _glows[i]
		var level := _glow_base[i] * clampf(0.75 + 0.25 * ignition, 0.0, 1.0) * (1.0 + 0.4 * (envelope - 1.0))
		glow.albedo_color = Color.from_hsv(glow.albedo_color.h, glow.albedo_color.s, clampf(level, 0.0, 1.0))
