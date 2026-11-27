extends SceneTree

const BOSS_SCENE := "res://scenes/expedition/boss_court.tscn"
const RUINS_SCENE := "res://scenes/expedition/outer_ruins.tscn"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _check(ProjectSettings.get_setting("application/run/main_scene") == BOSS_SCENE,
			"F5 starts the expedition at the gate"):
		quit(1)
		return
	if change_scene_to_file(BOSS_SCENE) != OK:
		printerr("Cannot load the boss arena")
		quit(1)
		return
	await scene_changed
	await _ticks(8)
	var hero := current_scene.get_node("Player") as CharacterBody3D
	var boss := current_scene.get_node("Guard")
	var boss_combat := boss.get_node("Combat")
	boss.ai_enabled = false
	_key(KEY_E)
	await _ticks(5)
	_check(current_scene.scene_file_path == BOSS_SCENE, "gate stays closed before victory")
	boss_combat.health = 80
	boss_combat.start_attack(boss_combat.light_attack)
	boss_combat.health = 60
	await _ticks(5)
	_check(boss.boss_phase == 1, "boss finishes an ongoing attack before the transition")
	await _ticks(80)
	_check(boss.boss_phase == 2 and boss_combat.action == &"boss_phase",
		"boss transitions below half health")
	await _ticks(95)
	_check(boss.boss_phase == 2 and boss_combat.action != &"boss_phase", "transition does not repeat")
	_key(KEY_F)
	await _ticks(12)
	_check(hero.global_position.y > 0.3 and hero.get_node("Combat").action == &"jump",
		"jump leaves the floor with a dedicated movement state")
	await _ticks(45)
	_check(hero.is_on_floor() and hero.get_node("Combat").action == &"", "jump lands and releases locomotion")
	boss_combat.health = 8
	hero.global_position = Vector3(0.0, 0.02, -2.4)
	_click(MOUSE_BUTTON_LEFT)
	await _ticks(26)
	_check(current_scene.outcome == &"victory" and hero.can_fight, "boss victory leaves the hero mobile")
	_key(KEY_E)
	await _ticks(5)
	_check(current_scene.scene_file_path == BOSS_SCENE, "gate can only be used in reach")
	hero.global_position = Vector3(0.0, 0.02, -10.45)
	await _ticks(5)
	_key(KEY_E)
	await _ticks(3)
	var world := current_scene
	_check(world.scene_file_path == BOSS_SCENE and world.get_node("AshGate").is_open,
		"the seal opens in place without loading another scene")
	_check(world.ruins != null and world.ruins.is_inside_tree() and world.ruins.position.z < -20.0,
		"the outer ruins stream in behind the gate")
	_check(world.ruins.enemies()[0].player == hero, "ruins enemies hunt the same player")
	_key(KEY_E)
	await _ticks(160)
	for i in 420:
		Input.action_press(&"move_forward")
		await physics_frame
		if hero.global_position.z < -19.0:
			break
	Input.action_release(&"move_forward")
	_check(hero.global_position.z < -19.0, "the hero walks through the archway and across the bridge")
	_check(world.zone == &"ruins" and root.get_node("Music").area == &"ruins",
		"crossing the bridge switches the zone and crossfades the score")
	_check(not world.get_node("Environment/Court/AshHills").visible, "court backdrop hides once inside the ruins")
	await _test_ruins(world)
	await _ticks(65)
	await _test_standalone_ruins()
	print("Expedition: %d/%d checks passed." % [_passed, _passed + _failed])
	quit(0 if _failed == 0 else 1)


func _test_ruins(world: Node3D) -> void:
	var hero := world.get_node("Player") as CharacterBody3D
	var actors: Array = world.ruins.enemies()
	_check(actors.size() == 3, "three enemies are placed beyond the gate")
	var roles: Array[StringName] = []
	for enemy in actors:
		roles.append(enemy.role)
		enemy.ai_enabled = false
	_check(roles == [&"spearman", &"shield", &"thrower"], "all three enemies have different roles")
	await _ticks(6)
	var shield: CharacterBody3D = actors[1]
	hero.global_position = shield.global_position + Vector3.FORWARD * 1.6
	hero.get_node("Heading").rotation.y = PI
	shield.get_node("Heading").rotation.y = 0.0
	await _ticks(3)
	_click(MOUSE_BUTTON_LEFT)
	await _ticks(35)
	var shield_combat := shield.get_node("Combat")
	_check(shield_combat.health == shield_combat.max_health and shield_combat.stamina < 100.0,
		"shieldbearer blocks a frontal strike")
	var thrower: CharacterBody3D = actors[2]
	thrower.global_position.x = 0.0
	hero.global_position = thrower.global_position + Vector3.BACK * 4.8
	thrower.get_node("Heading").rotation.y = PI
	var thrower_combat := thrower.get_node("Combat")
	thrower_combat.start_attack(thrower_combat.light_attack)
	await _ticks(49)
	_check(hero.get_node("Combat").health == 100.0, "ranged attack has travel time after release")
	await _ticks(24)
	_check(hero.get_node("Combat").health < 100.0, "projectile hits beyond melee reach")
	await _ticks(40)
	hero.global_position.x = 0.37
	hero.get_node("Heading").rotation.y = 0.0
	_set_mouse(MOUSE_BUTTON_RIGHT, true)
	await _ticks(3)
	var health_before: float = hero.get_node("Combat").health
	thrower_combat.start_attack(thrower_combat.light_attack)
	await _ticks(73)
	_check(hero.get_node("Combat").health == health_before and hero.get_node("Combat").stamina < 100.0,
		"frontal shield catches a bolt grazing the side of the capsule")
	_set_mouse(MOUSE_BUTTON_RIGHT, false)

	# Falling in the ruins resets them at their entrance; the Gatekeeper stays defeated.
	var hero_combat := hero.get_node("Combat")
	var old_area: Node3D = world.ruins
	shield_combat.health = 1.0
	hero_combat.health = 1.0
	hero_combat.receive_attack(thrower_combat, thrower_combat.light_attack, Vector3.BACK)
	await _ticks(40)
	_check(world.ruins_outcome == &"defeat" and not hero.can_fight, "a fall in the ruins ends the attempt")
	_key(KEY_T)
	await _ticks(6)
	_check(world.scene_file_path == BOSS_SCENE and world.outcome == &"victory",
		"retry keeps the world and the Gatekeeper's defeat")
	_check(world.ruins != old_area and world.ruins.remaining == 3
			and world.ruins.enemies()[1].get_node("Combat").health == world.ruins.enemies()[1].get_node("Combat").max_health,
		"retry restores all three ruins guards")
	_check(hero_combat.health == hero_combat.max_health and hero.can_fight
			and hero.global_position.distance_to(world.ruins.entrance_transform().origin) < 0.5,
		"the hero rises at the ruins' entrance")

	actors = world.ruins.enemies()
	for enemy in actors:
		enemy.ai_enabled = false
	for enemy in actors:
		enemy.get_node("Combat").health = 1.0
		hero.global_position = enemy.global_position + Vector3.BACK * 1.5
		hero.get_node("Heading").rotation.y = 0.0
		enemy.get_node("Heading").rotation.y = 0.0
		await _ticks(22)
		_click(MOUSE_BUTTON_LEFT)
		await _ticks(47)
	_check(world.ruins.remaining == 0 and world.ruins_outcome == &"victory",
		"defeating all three completes the expedition")


func _test_standalone_ruins() -> void:
	change_scene_to_file(RUINS_SCENE)
	await scene_changed
	await _ticks(4)
	var area := current_scene.get_node("Area")
	_check(area.enemies().size() == 3 and area.enemies()[0].player == current_scene.get_node("Player"),
		"the ruins remain playable as a standalone scene")


func _check(passed: bool, description: String) -> bool:
	if passed:
		_passed += 1
		print("PASS: ", description)
	else:
		_failed += 1
		printerr("FAIL: ", description)
	return passed


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _click(button: MouseButton) -> void:
	for pressed in [true, false]:
		_set_mouse(button, pressed)


func _set_mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
