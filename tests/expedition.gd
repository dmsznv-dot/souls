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
	for i in 8:
		if current_scene != null and current_scene.scene_file_path == RUINS_SCENE:
			break
		await process_frame
	if not _check(current_scene != null and current_scene.scene_file_path == RUINS_SCENE,
			"victory opens the transition to the outer ruins"):
		quit(1)
		return
	await _test_ruins()
	await _ticks(65)
	print("Expedition: %d/%d checks passed." % [_passed, _passed + _failed])
	quit(0 if _failed == 0 else 1)


func _test_ruins() -> void:
	var hero := current_scene.get_node("Player") as CharacterBody3D
	var actors := current_scene.get_node("Enemies").get_children()
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
	for enemy in actors:
		enemy.get_node("Combat").health = 1.0
		hero.global_position = enemy.global_position + Vector3.BACK * 1.5
		hero.get_node("Heading").rotation.y = 0.0
		enemy.get_node("Heading").rotation.y = 0.0
		await _ticks(22)
		_click(MOUSE_BUTTON_LEFT)
		await _ticks(47)
	_check(current_scene.remaining_enemies == 0 and current_scene.outcome == &"victory",
		"defeating all three completes the expedition")


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
