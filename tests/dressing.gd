extends SceneTree
## Set dressing in the Outer Ruins: props are built, solid where they should be, lit fires
## crackle, and foes still find their way around everything.

const RUINS := "res://scenes/expedition/outer_ruins.tscn"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file(RUINS)
	await scene_changed
	var area := current_scene.get_node("Area")
	var dressing := area.get_node("Environment/SetDressing")
	var kinds := {}
	for prop in dressing.get_children():
		kinds[String(prop.name).rstrip("0123456789")] = true
	_check(kinds.size() >= 9, "the ruins are dressed with many kinds of props (%s)" % ", ".join(kinds.keys()))
	_check(dressing.find_children("*", "CollisionShape3D", true, false).size() > 20, "carts, columns, walls and barrels are solid")
	var meshes := dressing.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() <= 20, "the dressing draws as a handful of merged meshes (%d)" % meshes.size())
	var fires := dressing.find_children("WatchFireCamp*", "OmniLight3D", true, false)
	_check(fires.size() == 2 and fires[0].has_node("Crackle") and fires[0].has_node("Flicker"), "campfires flicker and crackle")

	var region: NavigationRegion3D = area.get_node("Environment/AqueductWalk")
	var highest := -INF
	for polygon in region.navigation_mesh.get_polygon_count():
		for index in region.navigation_mesh.get_polygon(polygon):
			highest = maxf(highest, region.navigation_mesh.vertices[index].y)
	_check(highest < 0.3, "the rebaked navigation lies on the road (highest %.2f m)" % highest)
	await _ticks(10)
	var cart: Node3D = dressing.get_node("Cart4")
	var path := NavigationServer3D.map_get_path(region.get_navigation_map(), Vector3(5.0, 0, 0.5), Vector3(5.0, 0, -5.5), true)
	var detour := 0.0
	for i in range(1, path.size()):
		detour += path[i].distance_to(path[i - 1])
	_check(path.size() > 2 and detour > 6.2, "paths bend around the wrecked cart (%.1f m for 6 m)" % detour)
	_check(cart != null, "the wrecked cart stands where the camp is")

	# The brute at the far end hunts the player at the entrance, through column, carts and rubble.
	var hero := current_scene.get_node("Player") as CharacterBody3D
	hero.global_position = Vector3(0, 0.02, 5.0)
	var brute: CharacterBody3D
	for foe in area.enemies():
		foe.ai_enabled = foe.name == &"Brute"
		if foe.name == &"Brute":
			brute = foe
	brute.leash = 60.0
	brute.notice_distance = 50.0
	brute.hear_alarm(hero.global_position)
	var closest := INF
	for i in 1500:
		await physics_frame
		hero.get_node("Combat").health = 100.0
		closest = minf(closest, brute.global_position.distance_to(hero.global_position))
		if closest < 3.0:
			break
	_check(closest < 3.0, "the brute walks the whole dressed road to the player (closest %.1f m)" % closest)
	print("Dressing: %d/%d checks passed." % [_checks - _failures, _checks])
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
