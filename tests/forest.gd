extends SceneTree
## The Thornwood and the way there: forest generation, guiding lights, ambushes, the bonfire,
## and the eclipse ring that leads from the cleared ruins into the forest without a load.

const FOREST := "res://scenes/forest/forest.tscn"
const EXPEDITION := "res://scenes/expedition/boss_court.tscn"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_forest()
	await _test_ambush_and_bonfire()
	await _test_portal_journey()
	print("Forest: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_forest() -> void:
	change_scene_to_file(FOREST)
	await scene_changed
	var area := current_scene.get_node("Area")
	var hero := current_scene.get_node("Player") as CharacterBody3D
	_check(area.built and area.world.road.size() > 200, "the road winds over two hundred metres (%d m)" % area.world.road.size())
	_check(area.world.trunks.size() > 1500, "the forest is dense (%d trunks and rocks)" % area.world.trunks.size())
	var lamps := area.find_children("Lamp*", "OmniLight3D", true, false)
	var torches := area.find_children("WatchFire*", "OmniLight3D", true, false)
	_check(lamps.size() >= 12 and torches.size() >= 10, "lanterns and torches light the way (%d lanterns, %d torches)" % [lamps.size(), torches.size()])
	var nearest := INF
	for trunk in area.world.trunks:
		nearest = minf(nearest, area.world.road_distance(trunk.x, trunk.z))
	_check(nearest > area.world.ROAD_HALF + 0.5, "no tree or rock stands on the road (closest %.1f m from its centre)" % nearest)
	await _ticks(30)
	_check(hero.is_on_floor() and absf(hero.global_position.y - area.world.height(hero.global_position.x, hero.global_position.z)) < 0.3,
			"the hero stands on the forest floor at the entrance")
	var growth := area.find_children("*", "MultiMeshInstance3D", true, false)
	_check(growth.size() < 260, "growth is batched into few draw calls (%d multimeshes)" % growth.size())
	var waited := 0
	while not area.has_meta(&"navigation_ready") and waited < 600:
		await physics_frame
		waited += 1
	var nav: NavigationRegion3D = area.get_node("Navigation")
	_check(nav.navigation_mesh != null and nav.navigation_mesh.get_polygon_count() > 1000, "foes can find their way among the trees")
	await _ticks(5)
	var start: Vector3 = area.world.road[10]
	var end: Vector3 = area.world.road[150]
	var path := NavigationServer3D.map_get_path(nav.get_navigation_map(), start, end, true)
	_check(path.size() > 2 and path[-1].distance_to(end) < 1.5, "a path runs along the road for 140 m")


func _test_ambush_and_bonfire() -> void:
	change_scene_to_file(FOREST)
	await scene_changed
	var area := current_scene.get_node("Area")
	var hero := current_scene.get_node("Player") as CharacterBody3D
	var first: Array = area._ambush_state[0][1]
	_check(not first[0].visible and not first[0].is_in_group(&"foes"), "foes wait hidden in the trees")
	var trigger: float = area.AMBUSHES[0][0]
	var spot: Vector3 = area.world.road[int(trigger) + 1]
	hero.global_position = area.to_global(spot) + Vector3.UP * 0.2
	await _ticks(3)
	_check(area._ambush_state[0][0], "walking the road springs the ambush")
	await _ticks(90)
	var landed := 0
	for foe: CharacterBody3D in first:
		if foe.visible and foe.is_on_floor() and area.world.road_distance(area.to_local(foe.global_position).x, area.to_local(foe.global_position).z) < 4.0:
			landed += 1
	_check(landed == first.size(), "the foes leap out of the trees onto the road (%d of %d)" % [landed, first.size()])
	_check(first.all(func(foe: Node) -> bool: return foe.mode == foe.Mode.HUNT), "and hunt the player")

	var combat := hero.get_node("Combat")
	combat.health = 20.0
	hero.global_position = area.bonfire_transform().origin
	area.player = hero
	await _ticks(3)
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.parse_input_event(press)
	await _ticks(3)
	_check(area.bonfire_lit and combat.health == combat.max_health, "resting kindles the bonfire and restores the hero")
	_check(not area._ambush_state[0][0] and not area._ambush_state[0][1][0].visible, "and the forest's foes return to their hiding places")
	combat.health = 1.0
	combat.receive_attack(combat, load("res://scenes/duel/combat/heavy.tres"), Vector3.BACK)
	await _ticks(5)
	current_scene.rise()
	await _ticks(3)
	_check(hero.global_position.distance_to(area.bonfire_transform().origin) < 1.0, "after a death the hero rises at the bonfire")


## The full road: court cleared, ruins cleared, the eclipse ring opens, the forest is there.
func _test_portal_journey() -> void:
	change_scene_to_file(EXPEDITION)
	await scene_changed
	var host := current_scene
	var hero := host.get_node("Player") as CharacterBody3D
	await _ticks(10)
	host._finish(&"victory")
	host.open_gate()
	var waited := 0
	while (host.forest == null or not host.forest.built) and waited < 900:
		await process_frame
		waited += 1
	_check(host.forest != null and host.forest.built and not host.forest.visible, "the forest builds in the background while the player is in the ruins (%d frames)" % waited)
	for enemy in host.ruins.enemies():
		enemy.get_node("Combat").health = 0.0
		enemy.get_node("Combat").defeated.emit()
	await create_timer(4.2).timeout
	var portal: Node3D = host.ruins.portal
	_check(portal.is_open, "the cleared ruins open the eclipse ring")
	await create_timer(3.5).timeout
	hero.global_position = portal.to_global(portal.THRESHOLD) + Vector3(0, 0.1, 0.5)
	await _ticks(3)
	_check(portal.can_enter(), "the player can step into it from the shrine's foot")
	portal.entered.emit()
	await create_timer(1.2).timeout
	_check(host.zone == &"forest" and host.forest.visible, "stepping through arrives in the Thornwood without a load")
	_check(hero.global_position.distance_to(host.forest.entrance_transform().origin) < 1.5, "at the forest's edge, by the standing stones")
	_check(root.get_node("Music").area == &"forest", "the forest's own score plays")


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
