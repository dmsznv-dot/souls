extends SceneTree
## Shared wind and rain: presets per area, gusts, wet stone, storms, the cape in the wind.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var weather := root.get_node("Weather")
	change_scene_to_file("res://scenes/expedition/outer_ruins.tscn")
	await scene_changed
	for foe in current_scene.get_node("Area").enemies():
		foe.ai_enabled = false
	await _ticks(5)
	_check(weather._target == weather.PRESETS[&"ruins"], "the ruins set the storm preset")
	weather._gust_timer = 0.0
	await _ticks(60)
	_check(weather.gust > 0.3 and weather.wind > weather._base_wind, "a gust lifts the wind")
	var material: BaseMaterial3D = weather._wet_materials[0]
	var dry: float = weather._dry_roughness[0]
	weather.rain = 1.0
	weather.wet = 1.0
	await _ticks(2)
	_check(material.roughness < dry - 0.3, "rain makes stone glossy")
	weather._lightning_timer = 0.0
	await _ticks(3)
	_check(weather._flash > 0.5 and weather._thunder_delay > 0.0, "a storm flashes, then thunders")
	var rig := current_scene.get_node("Player/Heading/Rig")
	var cape: int = rig.skeleton.find_bone("Cape")
	weather._target = {"wind": 0.0, "gusts": 0.0, "rain": 0.0, "storm": 0.0, "debris": 0.0}
	weather._base_wind = 0.0
	weather._gust_age = 99.0
	await _ticks(3)
	var calm := Quaternion(rig.skeleton.get_bone_pose_rotation(cape))
	weather._target = {"wind": 1.0, "gusts": 1.0, "rain": 0.0, "storm": 0.0, "debris": 0.0}
	weather._base_wind = 1.0
	await _ticks(3)
	_check(calm.angle_to(rig.skeleton.get_bone_pose_rotation(cape)) > 0.05, "the wind moves the cape")
	weather.set_preset(&"court")
	_check(weather._target == weather.PRESETS[&"court"], "areas switch presets")
	print("Weather: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _check(passed: bool, description: String) -> bool:
	_checks += 1
	if passed:
		print("PASS: ", description)
	else:
		_failures += 1
		printerr("FAIL: ", description)
	return passed
