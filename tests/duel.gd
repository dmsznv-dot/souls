extends SceneTree

var _scene: Node3D
var _player: CharacterBody3D
var _guard: CharacterBody3D
var _hero_combat: Node
var _guard_combat: Node
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if not _check(main_path == "res://scenes/duel/courtyard_duel.tscn", "F5 opens the courtyard duel"):
		quit(1)
		return
	await _test_player_attacks()
	await _test_buffer()
	await _test_defenses()
	await _test_gamepad()
	await _test_guard_routes_around_cover()
	await _test_duel()
	await _ticks(80)
	print("Duel: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_player_attacks() -> void:
	await _arena()
	_press_mouse()
	_check(_hero_combat.action == &"", "attack waits for the physics tick")
	await _ticks(3)
	_check(_hero_combat.action == &"light" and _hero_combat.stamina == 85.0,
		"light attack consumes 15 stamina")
	_check(_guard_combat.health == 100.0, "windup causes zero damage")
	await _ticks(32)
	_check(_guard_combat.health == 82.0, "active light swing deals damage once")
	await _ticks(85)
	_check(_guard_combat.health == 82.0, "held attack does not repeat")
	_press_mouse(false)
	_key(KEY_R)
	await _ticks(5)
	_check(_hero_combat.action == &"heavy" and _hero_combat.stamina <= 70.0,
		"heavy attack enters a distinct and more expensive windup")
	await _ticks(45)
	_check(_guard_combat.health == 50.0, "heavy attack deals 32 damage")
	await _ticks(24)
	_hero_combat.stamina = 5.0
	_press_mouse()
	_press_mouse(false)
	await _ticks(3)
	_check(_hero_combat.action == &"", "insufficient stamina discards a press")
	_check(_guard_combat.health == 50.0, "rejected attack does not deal damage")


func _test_buffer() -> void:
	await _arena()
	_press_mouse()
	_press_mouse(false)
	await _ticks(28)
	_key(KEY_R)
	await _ticks(9)
	_check(_hero_combat.action == &"heavy", "press inside the 120 ms recovery buffer starts next action")
	await _arena()
	_press_mouse()
	_press_mouse(false)
	await _ticks(7)
	_key(KEY_R)
	await _ticks(34)
	_check(_hero_combat.action == &"", "press well before recovery expires")


func _test_defenses() -> void:
	await _arena()
	_press_mouse(true, MOUSE_BUTTON_RIGHT)
	await _ticks(2)
	_guard_combat.start_attack(_guard_combat.light_attack)
	await _ticks(41)
	_check(_hero_combat.health == 100.0 and _hero_combat.stamina < 100.0, "frontal block trades stamina for health")
	_press_mouse(false, MOUSE_BUTTON_RIGHT)

	await _arena()
	_guard.global_position.z = 1.55
	_guard.get_node("Heading").rotation.y = 0.0
	_press_mouse(true, MOUSE_BUTTON_RIGHT)
	await _ticks(2)
	_guard_combat.start_attack(_guard_combat.light_attack)
	await _ticks(41)
	_check(_hero_combat.health < 100.0, "block does not stop hits from behind")
	_press_mouse(false, MOUSE_BUTTON_RIGHT)

	await _arena()
	_hero_combat.stamina = 4.0
	_press_mouse(true, MOUSE_BUTTON_RIGHT)
	await _ticks(2)
	_guard_combat.start_attack(_guard_combat.light_attack)
	await _ticks(41)
	_check(_hero_combat.health < 100.0 and _hero_combat.action == &"stagger",
		"depleted guard breaks and staggers")
	_press_mouse(false, MOUSE_BUTTON_RIGHT)

	await _arena()
	_guard_combat.start_attack(_guard_combat.light_attack)
	await _ticks(28)
	_key(KEY_Q)
	await _ticks(13)
	_check(_hero_combat.health == 100.0 and _guard_combat.action == &"stagger",
		"timed frontal parry interrupts the guard")
	await _ticks(14)
	_press_mouse()
	_press_mouse(false)
	await _ticks(12)
	_check(_guard_combat.health == 73.0, "first hit after parry deals bonus damage")

	await _arena()
	_guard_combat.start_attack(_guard_combat.light_attack)
	await _ticks(27)
	_key(KEY_SPACE)
	await _ticks(15)
	_check(_hero_combat.action == &"roll" and _hero_combat.health == 100.0,
		"timed roll avoids an attack")
	_check(_player.global_position.z > 0.4, "neutral roll travels backwards")
	_check(_player.get_node("Heading").global_basis.z.z > 0.95, "neutral roll keeps the original facing")

	await _arena()
	_key(KEY_Q)
	_guard_combat.start_attack(_guard_combat.light_attack)
	await _ticks(41)
	_check(_hero_combat.health < 100.0, "a parry pressed too early does not prevent damage")


func _test_gamepad() -> void:
	await _arena()
	_joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.85)
	await _ticks(17)
	_check(_hero_combat.action == &"heavy" and _guard_combat.health == 100.0,
		"RT starts a heavy attack through the InputMap")
	for sample in [0.9, 0.95, 0.87, 1.0]:
		_joy_axis(JOY_AXIS_TRIGGER_RIGHT, sample)
		await _ticks(18)
	_check(_guard_combat.health == 68.0 and _hero_combat.action == &"",
		"a held or fluctuating trigger does not repeat a heavy attack")
	_joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_joy_axis(JOY_AXIS_TRIGGER_LEFT, 0.85)
	await _ticks(4)
	_check(_hero_combat.action == &"parry", "LT starts a parry through the InputMap")
	_joy_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)


func _test_guard_routes_around_cover() -> void:
	await _arena()
	_guard.global_position = Vector3(-4.0, 0.02, -2.2)
	_player.global_position = Vector3(-4.0, 0.02, 0.8)
	_guard.ai_enabled = true
	await _ticks(9)
	_guard.global_position = Vector3(-4.0, 0.02, -2.2)
	_player.global_position = Vector3(-8.0, 0.02, -2.2)
	await _ticks(265)
	_check(_guard.global_position.x < -6.6 and _hero_combat.health < 100.0,
		"alerted guard round the pier and reach a player behind it")


func _test_duel() -> void:
	await _arena()
	_guard.ai_enabled = true
	await _ticks(138)
	_check(_hero_combat.health < 100.0, "guard attacks an idle player in the playable scene")
	await _arena()
	_guard_combat.health = 15.0
	_press_mouse()
	_press_mouse(false)
	await _ticks(18)
	_check(_scene.outcome == &"victory" and not _guard.get_node("LockPoint").visible,
		"lethal hit wins the duel and removes the lock point")
	await _ticks(56)
	_check(absf(_guard.global_position.y) < 0.1, "defeated guard remains grounded")
	await _arena()
	_hero_combat.health = 5.0
	_guard_combat.start_attack(_guard_combat.light_attack)
	await _ticks(45)
	_check(_scene.outcome == &"defeat", "lethal guard attack ends the duel")
	_key(KEY_T)
	await process_frame
	await process_frame
	_check(current_scene != _scene and current_scene.get_node("Player/Combat").health == 100.0,
		"retry loads a fresh duel")


func _arena() -> void:
	change_scene_to_file("res://scenes/duel/courtyard_duel.tscn")
	await scene_changed
	_scene = current_scene
	_player = _scene.get_node("Player")
	_guard = _scene.get_node("Guard")
	_hero_combat = _player.get_node("Combat")
	_guard_combat = _guard.get_node("Combat")
	_guard.ai_enabled = false
	_player.global_position = Vector3(0.0, 0.02, 0.0)
	_guard.global_position = Vector3(0.0, 0.02, -1.55)
	_guard.get_node("Heading").rotation.y = PI
	await _ticks(6)


func _check(passed: bool, description: String) -> bool:
	_checks += 1
	if passed:
		print("PASS: ", description)
	else:
		_failures += 1
		printerr("FAIL: ", description)
	return passed


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _press_mouse(pressed: bool = true, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()
