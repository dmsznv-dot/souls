extends SceneTree
## Movement and feel acceptance checks from the movement and combat specification:
## M1 acceleration and analog speed, M2 skid, D1 roll window and distance, T2 buffer expiry,
## C2 lock ranges.

const ARENA := "res://scenes/duel/courtyard_duel.tscn"
const CommandBuffer = preload("res://scenes/player/command_buffer.gd")

var _checks := 0
var _failures := 0
var _player: CharacterBody3D
var _combat: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_acceleration()
	await _test_analog_walk()
	await _test_skid()
	await _test_roll()
	_test_buffer()
	await _test_lock_ranges()
	print("Movement: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _arena() -> void:
	change_scene_to_file(ARENA)
	await scene_changed
	var guard := current_scene.get_node("Guard") as CharacterBody3D
	guard.ai_enabled = false
	guard.global_position = Vector3(8.0, 0.02, 7.0)
	_player = current_scene.get_node("Player")
	_combat = _player.get_node("Combat")
	_player.global_position = Vector3(0, 0.02, 2.0)
	_player.get_node("CameraRig").rotation.y = 0.0
	await _ticks(10)


func _flat_speed() -> float:
	var v := _player.get_real_velocity()
	return Vector2(v.x, v.z).length()


## M1: 90 % of run speed in 8 +-1 ticks from a standstill, a stop in 8 +-1 ticks.
func _test_acceleration() -> void:
	await _arena()
	Input.action_press(&"move_forward")
	var reached := -1
	for i in 30:
		await physics_frame
		if reached < 0 and _flat_speed() >= 4.5 * 0.9:
			reached = i + 1
	_check(reached >= 7 and reached <= 10, "a run reaches 90 %% speed in about 8 ticks (%d)" % reached)
	Input.action_release(&"move_forward")
	var stopped := -1
	for i in 30:
		await physics_frame
		if stopped < 0 and _flat_speed() <= 0.45:
			stopped = i + 1
	_check(stopped >= 7 and stopped <= 10, "and stops in about 8 ticks (%d)" % stopped)


func _test_analog_walk() -> void:
	await _arena()
	Input.action_press(&"move_forward", 0.55)
	await _ticks(40)
	var walk := _flat_speed()
	Input.action_release(&"move_forward")
	_check(absf(walk - 2.0) < 0.25, "0.55 of stick travel walks at about 2 m/s (%.2f)" % walk)


## M2: reversing at a run skids for at most 8 ticks; at a walk it does not; a roll takes over.
func _test_skid() -> void:
	await _arena()
	Input.action_press(&"move_forward")
	await _ticks(30)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	var skid_ticks := 0
	for i in 20:
		await physics_frame
		if _player._skid_time > 0.0:
			skid_ticks += 1
	Input.action_release(&"move_back")
	_check(skid_ticks >= 1 and skid_ticks <= 8, "a reversal at a run skids briefly (%d ticks)" % skid_ticks)

	await _arena()
	Input.action_press(&"move_forward", 0.5)
	await _ticks(30)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back", 0.5)
	var walked_skid := false
	for i in 12:
		await physics_frame
		walked_skid = walked_skid or _player._skid_time > 0.0
	Input.action_release(&"move_back")
	_check(not walked_skid, "a reversal at a walk does not skid")

	await _arena()
	Input.action_press(&"move_forward")
	await _ticks(30)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	await _ticks(2)
	var was_skidding: bool = _player._skid_time > 0.0
	_player.commands.offer(&"roll", Engine.get_physics_frames())
	await _ticks(1)
	Input.action_release(&"move_back")
	_check(was_skidding and _combat.action == &"roll" and _player._skid_time <= 0.0, "a roll takes over a skid at once")


## D1: the medium roll protects on ticks [5, 21), covers about 2.95 m, a backstep 70 % of it,
## and loses distance against a wall.
func _test_roll() -> void:
	await _arena()
	_combat.start_roll(Vector3.FORWARD)
	var windows := []
	for age in [4, 5, 20, 21]:
		_combat.action_age = age / 60.0
		windows.append(_combat.is_invulnerable())
	_check(windows == [false, true, true, false], "a medium roll is invulnerable on ticks [5, 21) exactly %s" % [windows])

	await _arena()
	var start := _player.global_position
	_player.commands.offer(&"roll", Engine.get_physics_frames())
	Input.action_press(&"move_left")
	await _ticks(1)
	Input.action_release(&"move_left")
	await _ticks(45)
	var rolled := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(absf(rolled - 2.95) < 0.25, "a medium roll covers about 2.95 m (%.2f)" % rolled)

	await _arena()
	start = _player.global_position
	_player.commands.offer(&"roll", Engine.get_physics_frames())
	await _ticks(46)
	var stepped := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(absf(stepped - 2.065) < 0.25, "with no input it is a backstep of about 2.07 m (%.2f)" % stepped)

	await _arena()
	# A wall a metre to the hero's left.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 3.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	current_scene.add_child(wall)
	wall.global_position = _player.global_position + Vector3(-1.2, 1.5, 0)
	await _ticks(3)
	start = _player.global_position
	_player.commands.offer(&"roll", Engine.get_physics_frames())
	Input.action_press(&"move_left")
	await _ticks(1)
	Input.action_release(&"move_left")
	await _ticks(45)
	var blocked := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(blocked < 1.2, "a roll into a wall loses the blocked distance (%.2f)" % blocked)


## T2: a press lives 10 ticks (last valid +9); same-tick presses resolve by priority.
func _test_buffer() -> void:
	var buffer := CommandBuffer.new()
	buffer.offer(&"light_attack", 100)
	_check(buffer.peek(109) == &"light_attack" and buffer.peek(110) == &"", "a light press is valid through +9 and expired at +10")
	buffer.offer(&"jump", 200)
	buffer.offer(&"roll", 200)
	buffer.offer(&"light_attack", 200)
	_check(buffer.peek(200) == &"roll", "same-tick presses resolve roll first")
	buffer.offer(&"jump", 201)
	_check(buffer.peek(201) == &"jump" and buffer.peek(207) == &"", "a newer press replaces the slot; a jump lives 6 ticks")


## C2: acquire within 18 m, hold to 21 m. On the ruins road: a long straight, open line.
func _test_lock_ranges() -> void:
	change_scene_to_file("res://scenes/expedition/outer_ruins.tscn")
	await scene_changed
	_player = current_scene.get_node("Player")
	for foe in current_scene.get_node("Area").enemies():
		foe.ai_enabled = false
		foe.get_node("LockPoint").hide()
	var marker := Marker3D.new()
	marker.add_to_group(&"lock_targets")
	current_scene.add_child(marker)
	var camera := _player.get_node("CameraRig")
	_player.global_position = Vector3(0, 0.03, 6.0)
	camera.rotation.y = 0.0
	marker.global_position = Vector3(0, 1.3, 6.0 - 19.0)
	await _ticks(5)
	_check(camera._find_target() == null, "a target 19 m away is not acquired")
	marker.global_position = Vector3(0, 1.3, 6.0 - 17.0)
	await _ticks(3)
	camera.lock_target = camera._find_target()
	_check(camera.lock_target == marker, "a target 17 m away is acquired")
	marker.global_position = Vector3(0, 1.3, 6.0 - 20.5)
	await _ticks(3)
	_check(camera.lock_target == marker, "and kept at 20.5 m")
	marker.global_position = Vector3(0, 1.3, 6.0 - 22.0)
	await _ticks(3)
	_check(camera.lock_target == null, "and released past 21 m")


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
