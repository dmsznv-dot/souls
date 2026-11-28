extends SceneTree
## Thornwood's living details and the zones beyond it: fire, wind, breakable props, the portal
## contract, the Flooded Crossing and the Belfry under the Roots.

const FOREST := "res://scenes/forest/forest.tscn"
const CROSSING := "res://scenes/zones/crossing.tscn"
const BELFRY := "res://scenes/zones/belfry.tscn"
const Breakable = preload("res://scenes/environment/breakable_prop.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_fire_and_wind()
	await _test_breakables()
	await _test_forest_compositions()
	await _test_crossing()
	await _test_belfry()
	await _test_walk_on()
	_test_portal_contract()
	print("Zones: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_fire_and_wind() -> void:
	change_scene_to_file(FOREST)
	await scene_changed
	var area := current_scene.get_node("Area")
	while not area.built:
		await physics_frame
	var torches := area.find_children("WatchFireTorch*", "OmniLight3D", true, false)
	var a: OmniLight3D = torches[0]
	var b: OmniLight3D = torches[1]
	var a_energy := []
	var b_energy := []
	var origin := a.position
	var moved := 0.0
	for i in 60:
		await process_frame
		a_energy.append(a.light_energy)
		b_energy.append(b.light_energy)
		moved = maxf(moved, a.position.distance_to(origin))
	_check(a_energy.max() - a_energy.min() > 0.3, "a torch's light lives (%.2f..%.2f)" % [a_energy.min(), a_energy.max()])
	var same := true
	for i in 60:
		if absf(a_energy[i] / a.get_node("Flicker").base_energy - b_energy[i] / b.get_node("Flicker").base_energy) > 0.01:
			same = false
	_check(not same, "neighbouring torches flicker out of phase")
	_check(moved > 0.0 and moved < 0.25, "the hot point drifts a few centimetres, never wanders (%.3f m)" % moved)
	var weather := root.get_node("Weather")
	weather.wind_override = 2
	await _ticks(30)
	var sent: Vector2 = weather._wind_xz
	_check(sent.length() > 0.3 and weather._sent_wind.z > 0.9, "a strong gust reaches the crowns (%.2f)" % sent.length())
	weather.wind_override = 1
	await _ticks(240)
	sent = weather._wind_xz
	_check(sent.length() < 0.05, "still air stills them (%.3f)" % sent.length())
	weather.wind_override = 0
	var wind_batches := 0
	for batch in area.find_children("*", "MultiMeshInstance3D", true, false):
		if batch.material_override is ShaderMaterial:
			wind_batches += 1
			if not batch.multimesh.use_custom_data:
				wind_batches = -1000
	_check(wind_batches > 20, "firs, oaks and ferns sway with a per-instance phase (%d batches)" % wind_batches)


func _strike(hero: CharacterBody3D, prop: Node3D, heavy: bool) -> void:
	var combat := hero.get_node("Combat")
	var offset: Vector3 = prop.global_position - hero.global_position
	hero.get_node("Heading").rotation.y = atan2(-offset.x, -offset.z)
	if heavy:
		combat.start_heavy()
	else:
		combat.start_light()
	for i in 90:
		await physics_frame
		if combat.action == &"":
			break


func _test_breakables() -> void:
	change_scene_to_file(CROSSING)
	await scene_changed
	var area := current_scene.get_node("Area")
	await _ticks(10)
	for foe in area.enemies():
		foe.queue_free()
	var hero := current_scene.get_node("Player") as CharacterBody3D
	var barrel := Breakable.new()
	barrel.kind = &"barrel"
	barrel.prop_id = "test/barrel"
	area.add_child(barrel)
	barrel.global_position = hero.global_position + Vector3(0, 0, -1.4)
	await _ticks(3)
	await _strike(hero, barrel, false)
	_check(not barrel.is_broken and barrel._blows > 0.4 and barrel._blows < 0.6, "one light swing counts once on a barrel, however many sub-steps touch it")
	await _strike(hero, barrel, false)
	_check(barrel.is_broken, "a second light swing breaks it")
	var pieces := Breakable.live_fragments()
	_check(pieces > 0 and pieces <= Breakable.MAX_FRAGMENTS, "it throws a few fragments (%d)" % pieces)
	await _strike(hero, barrel, false)
	_check(Breakable.live_fragments() <= pieces, "hitting the wreck does nothing more")
	await _ticks(160)
	_check(Breakable.live_fragments() == 0, "fragments vanish after a couple of seconds")
	barrel.reset()
	await _ticks(3)
	_check(not barrel.is_broken, "resting puts the barrel back")

	var crate := Breakable.new()
	crate.kind = &"crate"
	area.add_child(crate)
	crate.global_position = hero.global_position + Vector3(0, 0, -2.2)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	area.add_child(wall)
	wall.global_position = hero.global_position + Vector3(0, 1.5, -0.9)
	await _ticks(3)
	await _strike(hero, crate, true)
	_check(not crate.is_broken, "a blow does not break a crate behind a wall")
	wall.queue_free()

	var grate := Breakable.new()
	grate.kind = &"grate"
	area.add_child(grate)
	grate.global_position = hero.global_position + Vector3(-3.0, 0, 0)
	await _ticks(3)
	grate.receive_hit(hero.get_node("Combat"), 9001, true)
	grate.reset()
	_check(grate.is_broken, "an opened grate stays open after a rest")


func _test_forest_compositions() -> void:
	change_scene_to_file(FOREST)
	await scene_changed
	var area := current_scene.get_node("Area")
	while not area.built:
		await physics_frame
	var ids := {}
	var unique := true
	for prop in area.props:
		unique = unique and not ids.has(prop.prop_id)
		ids[prop.prop_id] = true
	_check(area.props.size() >= 6 and unique, "the road's breakables have unique ids (%d)" % area.props.size())
	var compositions: Node = area.get_node("Compositions")
	for group in ["Arrival", "PatrolTrail", "DeadOak", "Lowland", "Convoy", "ClearingTraces"]:
		_check(compositions.has_node(group), "the %s group is in place" % group)
	var near_landing := false
	for ambush: Array in area.AMBUSHES:
		for spec: Array in ambush[1]:
			var landing: Vector3 = area.world.road[int(ambush[0] + spec[2])]
			for prop in area.props:
				if Vector2(prop.position.x - landing.x, prop.position.z - landing.z).length() < 3.0:
					near_landing = true
	_check(not near_landing, "no prop stands within 3 m of an ambush landing")
	var bonfire: Vector3 = area.world.point(area.world.CLEARING.x, area.world.CLEARING.z)
	var crowding := false
	for body in compositions.find_children("*", "StaticBody3D", true, false):
		if Vector2(body.global_position.x - area.to_global(bonfire).x, body.global_position.z - area.to_global(bonfire).z).length() < 3.5:
			crowding = true
	_check(not crowding, "the 3.5 m round the bonfire stays clear")


func _test_crossing() -> void:
	change_scene_to_file(CROSSING)
	await scene_changed
	var area := current_scene.get_node("Area")
	await _ticks(20)
	var nav: NavigationRegion3D = area.get_node("Content/Navigation")
	var path := NavigationServer3D.map_get_path(nav.get_navigation_map(), area.to_global(area.entry_local), area.to_global(area.EXIT + Vector3(0, 0, 1.5)), true)
	_check(path.size() > 2 and path[-1].distance_to(area.to_global(area.EXIT + Vector3(0, 0, 1.5))) < 1.0, "the crossing can be walked from the slope to the stone steps")
	var ford := NavigationServer3D.map_get_path(nav.get_navigation_map(), area.to_global(Vector3(-7.0, -3.0, -50.0)), area.to_global(Vector3(-8.5, -3.0, -78.0)), true)
	# Through the water: some of the way runs below the walks' level, on the ford's bed.
	var ford_wet := ford.size() > 2 and Array(ford).any(func(p: Vector3) -> bool: return area.to_local(p).y < -3.15 and area.to_local(p).x < -6.5)
	_check(ford_wet, "the shallow ford loops from the islet to the far bank")
	var hero := current_scene.get_node("Player") as CharacterBody3D
	hero.global_position = area.to_global(Vector3(8.0, -3.0, -32.0))
	for i in 120:
		await physics_frame
		if current_scene.fallen:
			break
	_check(current_scene.fallen, "deep water takes the hero")
	current_scene.rise()
	await _ticks(3)
	_check(hero.global_position.distance_to(area.respawn_transform().origin) < 1.0, "who rises at the respawn point")


func _test_belfry() -> void:
	change_scene_to_file(BELFRY)
	await scene_changed
	var area := current_scene.get_node("Area")
	await _ticks(20)
	var nav: NavigationRegion3D = area.get_node("Content/Navigation")
	var map := nav.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map, area.to_global(area.entry_local), area.to_global(area.EXIT + Vector3(0, 0, -1)), true)
	_check(path.size() > 2 and path[-1].distance_to(area.to_global(area.EXIT + Vector3(0, 0, -1))) < 1.0, "the belfry leads from the gorge down, through the arch and up to the exit")
	var gallery := NavigationServer3D.map_get_path(map, area.to_global(Vector3(6.6, -4, -20)), area.to_global(Vector3(6.6, -1, -40)), true)
	_check(gallery.size() > 2 and gallery[-1].distance_to(area.to_global(Vector3(6.6, -1, -40))) < 1.0, "the gallery climbs to the bell hall")
	var grate: Node3D = area.get_node("Content/niche_grate")
	_check(grate != null and not grate.is_broken, "a rotten grate closes the niche")
	var weather := root.get_node("Weather")
	weather.gust = 1.0
	area._bell_rest = 0.0
	area.activate()
	await _ticks(2)
	_check(area.rings == 1, "a gust rings the bell")
	await _ticks(10)
	_check(area.rings == 1, "and it rests before ringing again")


## From the clearing the road goes on foot: through the gap, down to the crossing, on to the
## belfry, whose mouth becomes the place to rise.
func _test_walk_on() -> void:
	change_scene_to_file(FOREST)
	await scene_changed
	var area := current_scene.get_node("Area")
	while not area.built:
		await physics_frame
	var hero := current_scene.get_node("Player") as CharacterBody3D
	await _ticks(10)
	var gap_center: Vector3 = area.to_global(area.world.point(area.world.CLEARING.x, area.world.MIN.y + 2.0))
	var space := hero.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(gap_center + Vector3(0, 1.0, 3.0), gap_center + Vector3(0, 1.0, -3.0), 1)
	_check(space.intersect_ray(ray).is_empty(), "the clearing's south edge is open")
	# Zones are built as the player nears them and freed when far behind.
	_check(not area.crossing.prepared and not area.belfry.prepared, "the zones beyond wait unbuilt while the player is far")
	var clearing: Vector3 = area.to_global(area.world.point(area.world.CLEARING.x, area.world.CLEARING.z)) + Vector3(0, 0.3, 0)
	hero.global_position = clearing
	await _until(func() -> bool: return area.crossing.prepared)
	_check(area.crossing.prepared, "the crossing is built as the player nears it")
	hero.global_position = area.crossing.to_global(area.crossing.entry_local) + Vector3(0, 0.2, 0)
	await _ticks(20)
	_check(area.zone == &"crossing" and area.crossing.active, "walking south enters the Flooded Crossing")
	_check(hero.is_on_floor(), "on solid ground where the forest ends")
	await _until(func() -> bool: return area.belfry.prepared)
	hero.global_position = area.entrance_transform().origin + Vector3(0, 0.3, 0)
	await _until(func() -> bool: return not area.crossing.prepared and not area.belfry.prepared)
	_check(not area.crossing.prepared and not area.belfry.prepared and area.crossing.get_child_count() == 0,
		"walking back to the forest's edge frees both zones")
	hero.global_position = clearing
	await _until(func() -> bool: return area.crossing.prepared)
	hero.global_position = area.crossing.to_global(area.crossing.entry_local) + Vector3(0, 0.2, 0)
	await _until(func() -> bool: return area.belfry.prepared)
	_check(area.crossing.prepared and area.belfry.prepared, "and coming back builds them again")
	hero.global_position = area.belfry.to_global(area.belfry.entry_local) + Vector3(0, 0.2, 0)
	await _ticks(5)
	_check(area.zone == &"belfry" and area.checkpoint == &"belfry", "the belfry's mouth becomes the place to rise")
	_check(area.respawn_transform().origin.distance_to(area.belfry.respawn_transform().origin) < 0.01, "and the hero would rise there")


func _until(done: Callable, limit: int = 900) -> void:
	var waited := 0
	while not done.call() and waited < limit:
		await physics_frame
		waited += 1


func _test_portal_contract() -> void:
	var portal := preload("res://scenes/expedition/eclipse_portal.gd").new()
	root.add_child(portal)
	var ready := [false]
	portal.destination_ready = func() -> bool: return ready[0]
	portal.is_open = true
	portal.amount = 1.0
	var hero := Node3D.new()
	root.add_child(hero)
	hero.global_position = portal.to_global(portal.THRESHOLD)
	portal.player = hero
	_check(not portal.can_enter(), "the portal refuses while the far side is not ready")
	ready[0] = true
	_check(portal.can_enter(), "and takes the player once it is")
	portal.locked = true
	_check(not portal.can_enter(), "a crossing in progress refuses a second press")
	portal.unlock()
	_check(portal.can_enter(), "a cancelled crossing frees the portal")
	portal.queue_free()
	hero.queue_free()


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
