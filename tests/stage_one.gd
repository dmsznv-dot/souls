extends SceneTree

var _arena: Node3D
var _player: CharacterBody3D
var _heading: Node3D
var _rig: Node3D
var _camera: Camera3D
var _target: Marker3D
var _marker: Label3D
var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not await _reset_arena():
		quit(1)
		return
	await _test_keyboard_movement()
	await _test_camera_reorients_movement()
	await _test_camera_wall()
	await _test_camera_target_collision()
	await _test_lock_and_strafe()
	await _test_lock_visibility()
	await _test_camera_only_occlusion()
	await _test_lock_removal()
	await _test_gamepad_bindings()
	await _test_lantern_collision()
	print("Stage 1: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_keyboard_movement() -> void:
	var start := _player.global_position
	_key(KEY_W, true)
	await _ticks(24)
	_key(KEY_W, false)
	var straight := _player.global_position - start
	_check(straight.z < -1.0 and absf(straight.x) < 0.01, "W moves along camera forward")
	_player.global_position = start
	# Start the diagonal from rest, as the straight run did.
	_player.drive = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_key(KEY_W, true)
	_key(KEY_D, true)
	await _ticks(24)
	_key(KEY_W, false)
	_key(KEY_D, false)
	var diagonal := _player.global_position - start
	_check(diagonal.x > 0.7 and diagonal.z < -0.7, "W+D moves forward and right")
	_check(absf(diagonal.length() - straight.length()) < 0.02, "diagonal preserves speed")


func _test_camera_reorients_movement() -> void:
	if not await _reset_arena():
		return
	var before := _camera.global_basis.z
	_mouse_motion(Vector2(320.0, 0.0))
	await _ticks(4)
	_check(before.dot(_camera.global_basis.z) < 0.7, "mouse orbits the camera")
	var start := _player.global_position
	_key(KEY_W, true)
	await _ticks(24)
	_key(KEY_W, false)
	var displacement := _player.global_position - start
	var camera_forward := -_camera.global_basis.z
	camera_forward.y = 0.0
	_check(displacement.normalized().dot(camera_forward.normalized()) > 0.98,
		"W follows the new camera heading")


func _test_camera_wall() -> void:
	if not await _reset_arena():
		return
	var open_distance := _camera.global_position.distance_to(_rig.global_position)
	_check(open_distance > 4.5, "camera starts at its full distance in open space")
	_key(KEY_S, true)
	await _ticks(130)
	_key(KEY_S, false)
	var tucked_distance := _camera.global_position.distance_to(_rig.global_position)
	_check(tucked_distance < 1.0, "wall retracts the camera")
	_check(_player.global_position.z < 8.65 and _camera.global_position.z < 8.65,
		"player and camera stay on the playable side of the wall")
	# Clear the obstruction in one tick so wall motion cannot mask a camera snap.
	_player.global_position.z = 2.0
	await _ticks(5)
	var recovering_distance := _camera.global_position.distance_to(_rig.global_position)
	await _ticks(85)
	var restored_distance := _camera.global_position.distance_to(_rig.global_position)
	_check(recovering_distance > tucked_distance + 0.05
		and recovering_distance < 1.0, "camera extends gradually")
	_check(restored_distance > 4.5, "camera restores its open distance")


func _test_camera_target_collision() -> void:
	if not await _reset_arena():
		return
	_player.global_position.z = -2.8
	await _ticks(5)
	_mouse_motion(Vector2(898.0, 0.0))
	await _ticks(5)
	_check(_camera.global_position.z > -3.8, "free camera pulls in before crossing the statue")


func _test_lock_and_strafe() -> void:
	if not await _reset_arena():
		return
	_middle_click()
	await _ticks(15)
	_check(_marker.visible, "middle mouse acquires the visible target")
	var initial_distance := _player.global_position.distance_to(_target.global_position)
	_key(KEY_D, true)
	await _ticks(48)
	_key(KEY_D, false)
	var towards_target := _target.global_position - _player.global_position
	towards_target.y = 0.0
	_check(_player.global_position.x > 2.0 and absf(initial_distance
		- _player.global_position.distance_to(_target.global_position)) < 0.15,
		"locked strafe follows an arc around the target")
	_check((-_heading.global_basis.z).dot(towards_target.normalized()) > 0.995,
		"the hero faces the target throughout strafing")
	_check(_camera.is_position_in_frustum(_target.global_position), "target remains in view")
	_middle_click()
	await _ticks(3)
	_check(not _marker.visible, "middle mouse releases the target")


func _test_lock_visibility() -> void:
	if not await _reset_arena():
		return
	var cover := _add_cover()
	await _ticks(4)
	_middle_click()
	await _ticks(4)
	_check(not _marker.visible, "target cannot be acquired through a wall")
	cover.position.x = 20.0
	await _ticks(4)
	_middle_click()
	await _ticks(4)
	cover.position.x = 0.0
	await _ticks(8)
	_check(_marker.visible, "brief occlusion keeps the lock")
	cover.position.x = 20.0
	await _ticks(5)
	cover.position.x = 0.0
	await _ticks(15)
	_check(_marker.visible, "restored sight resets the occlusion timer")
	await _ticks(16)
	_check(not _marker.visible, "sustained occlusion releases the target")


func _test_camera_only_occlusion() -> void:
	if not await _reset_arena():
		return
	_middle_click()
	await _ticks(4)
	_check(_marker.visible, "target is locked before camera-only occlusion")
	# This narrow obstacle hangs above the spring arm and behind the player pivot.
	_add_cover(Vector3(0.0, 2.35, 4.0), Vector3(2.0, 0.15, 0.14))
	await _ticks(32)
	_check(_camera.global_position.z > 7.5, "camera-only cover leaves the spring arm clear")
	_check(not _marker.visible, "sustained camera-only occlusion releases the target")


func _test_lock_removal() -> void:
	if not await _reset_arena():
		return
	_middle_click()
	await _ticks(4)
	_check(_marker.visible, "target is locked before removal")
	_target.queue_free()
	await _ticks(4)
	_check(not _marker.visible, "removed target returns to free camera")


func _test_gamepad_bindings() -> void:
	if not await _reset_arena():
		return
	var start := _player.global_position
	_joy_axis(JOY_AXIS_LEFT_Y, -0.10)
	await _ticks(12)
	_check(_player.global_position.distance_to(start) < 0.01, "left stick dead zone prevents drift")
	_joy_axis(JOY_AXIS_LEFT_Y, -0.6)
	await _ticks(24)
	_joy_axis(JOY_AXIS_LEFT_Y, 0.0)
	_check(_player.global_position.z < start.z - 0.45, "left stick moves the player")
	_joy_button(JOY_BUTTON_RIGHT_STICK)
	await _ticks(4)
	_check(_marker.visible, "R3 acquires the target")
	_joy_button(JOY_BUTTON_RIGHT_STICK)
	await _ticks(4)
	_check(not _marker.visible, "R3 releases the target")
	var before := _camera.global_basis.z
	_joy_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _ticks(24)
	_joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check(before.dot(_camera.global_basis.z) < 0.85, "right stick orbits the camera")


func _test_lantern_collision() -> void:
	if not await _reset_arena():
		return
	_player.global_position = Vector3(3.65, 0.03, -3.8)
	_key(KEY_W, true)
	await _ticks(50)
	_key(KEY_W, false)
	_check(_player.global_position.z < -5.1 and _player.global_position.z > -5.5,
		"player stops at the lantern base")


func _reset_arena() -> bool:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await process_frame
	var scene := load("res://scenes/arena/controller_arena.tscn") as PackedScene
	if scene == null:
		_check(false, "controller test scene loads")
		return false
	_arena = scene.instantiate() as Node3D
	root.add_child(_arena)
	_player = _arena.get_node_or_null("Player") as CharacterBody3D
	_heading = _arena.get_node_or_null("Player/Heading") as Node3D
	_rig = _arena.get_node_or_null("Player/CameraRig") as Node3D
	_camera = root.get_camera_3d()
	_target = _arena.get_node_or_null("Target/LockPoint") as Marker3D
	_marker = _arena.get_node_or_null("Player/LockMarker") as Label3D
	if (_player == null or _heading == null or _rig == null or _camera == null
			or _target == null or _marker == null):
		_check(false, "main scene creates the player, camera and training target")
		return false
	await _ticks(30)
	return true


func _add_cover(at: Vector3 = Vector3(0.0, 1.5, 0.0),
		size: Vector3 = Vector3(3.0, 3.0, 0.5)) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.position = at
	body.add_child(collision)
	_arena.add_child(body)
	return body


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if passed:
		print("PASS: ", description)
	else:
		_failures += 1
		printerr("FAIL: ", description)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _middle_click() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_MIDDLE
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _joy_button(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
