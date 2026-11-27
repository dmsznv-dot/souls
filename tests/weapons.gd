extends SceneTree
## Weapons strike with their blades: reach, chains, cancels, weight and switching.

const ARENA := "res://scenes/duel/courtyard_duel.tscn"

var _player: CharacterBody3D
var _guard: CharacterBody3D
var _hero: Node
var _foe: Node
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_reach()
	await _test_blade_crosses_front()
	await _test_chain_and_cancels()
	await _test_weight()
	await _test_switching()
	print("Weapons: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_reach() -> void:
	# Weapon order on the player: longsword, shortsword, greatsword.
	await _arena(2.3, 1)
	_hero.start_light()
	await _ticks(80)
	_check(_foe.health == 100.0, "shortsword cannot reach a foe 2.3 m away")
	await _arena(2.3, 0)
	_hero.start_heavy()
	await _ticks(90)
	_check(_foe.health == 100.0 - 32.0, "longsword heavy reaches 2.3 m")
	await _arena(2.75, 2)
	_hero.start_light()
	await _ticks(90)
	_check(_foe.health < 100.0, "greatsword reaches 2.75 m")
	await _arena(1.4, 0)
	_player.get_node("Heading").rotation.y = PI
	_hero.start_light()
	await _ticks(60)
	_check(_foe.health == 100.0, "a swing facing away does not hit a foe behind")


func _test_blade_crosses_front() -> void:
	await _arena(3.5, 0)
	_hero.start_light()
	var crossed := false
	for i in 40:
		await physics_frame
		var segment: PackedVector3Array = _hero.rig.blade_segment()
		if _hero.phase_name().ends_with("active") and segment.size() == 2:
			var local: Vector3 = _player.global_transform.affine_inverse() * segment[1]
			if local.z < -1.2 and absf(local.x) < 0.4 and local.y > 0.7 and local.y < 1.6:
				crossed = true
	_check(crossed, "the light swing's point passes in front of the chest while active")


func _test_chain_and_cancels() -> void:
	await _arena(4.0, 0)
	_press(MOUSE_BUTTON_LEFT)
	await _ticks(14)
	_press(MOUSE_BUTTON_LEFT)
	await _ticks(28)
	_check(_hero.action == &"light_b", "a second press chains into the return cut")
	await _arena(4.0, 0)
	_press(MOUSE_BUTTON_LEFT)
	await _ticks(20)
	var before: float = _hero.action_age
	_key(KEY_SPACE)
	await _ticks(3)
	_check(_hero.action == &"light" and _hero.action_age > before, "a roll cannot cut the active part of a swing")
	await _ticks(16)
	_check(_hero.action == &"roll", "a buffered roll cancels late recovery")
	await _arena(4.0, 2)
	_press(MOUSE_BUTTON_LEFT)
	await _ticks(28)
	_key(KEY_SPACE)
	await _ticks(3)
	_check(_hero.action == &"light", "a greatsword swing stays committed through early recovery")


func _test_weight() -> void:
	await _arena(1.6, 0)
	_hero.start_light()
	var frozen_light := await _count_frozen()
	await _arena(2.0, 2)
	_hero.start_heavy()
	var frozen_heavy := await _count_frozen()
	_check(frozen_heavy > frozen_light + 2, "a greatsword heavy holds contact longer than a longsword light (%d vs %d ticks)" % [frozen_heavy, frozen_light])
	await _arena(1.6, 2)
	var start := _guard.global_position
	_hero.start_heavy()
	await _ticks(70)
	_check(_guard.global_position.distance_to(start) > 0.15, "a full-weight blow shoves the defender back")
	await _arena(6.0, 0)
	var long_walk := await _walk_distance()
	await _arena(6.0, 2)
	var great_walk := await _walk_distance()
	_check(great_walk < long_walk, "carrying the greatsword slows walking (%.2f vs %.2f m)" % [great_walk, long_walk])


func _test_switching() -> void:
	await _arena(4.0, 0)
	_key(KEY_TAB)
	await _ticks(2)
	_check(_hero.weapon.form == SoulsWeapon.Form.SHORTSWORD, "Tab switches to the next weapon")
	_hero.start_light()
	await _ticks(2)
	_key(KEY_TAB)
	await _ticks(2)
	_check(_hero.weapon.form == SoulsWeapon.Form.SHORTSWORD, "no switching in the middle of a swing")
	_check(_hero.rig.weapon == _hero.weapon, "the rig holds the equipped weapon")


func _count_frozen() -> int:
	var frozen := 0
	for i in 90:
		await physics_frame
		if _hero.contact_frozen:
			frozen += 1
	return frozen


func _walk_distance() -> float:
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _ticks(40)
	Input.action_release(&"move_forward")
	return _player.global_position.distance_to(start)


func _arena(distance: float, weapon_index: int) -> void:
	change_scene_to_file(ARENA)
	await scene_changed
	_player = current_scene.get_node("Player")
	_guard = current_scene.get_node("Guard")
	_hero = _player.get_node("Combat")
	_foe = _guard.get_node("Combat")
	_guard.ai_enabled = false
	_player.global_position = Vector3(0.0, 0.02, 0.0)
	_guard.global_position = Vector3(0.0, 0.02, -distance)
	_guard.get_node("Heading").rotation.y = PI
	await _ticks(4)
	for i in weapon_index:
		_player.cycle_weapon()
	await _ticks(2)


func _press(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.physical_keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)


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
