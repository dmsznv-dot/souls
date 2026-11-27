extends CharacterBody3D

const OrbitCamera = preload("res://scenes/player/orbit_camera.gd")
const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const COMBAT_PRESSES: Array[StringName] = [&"roll", &"parry", &"heavy_attack", &"light_attack"]
const BUFFER_SECONDS: float = 0.12

@export_range(0.1, 12.0, 0.1, "suffix:m/s") var move_speed: float = 4.5
@export_range(1.0, 30.0, 0.5, "suffix:rad/s") var turn_speed: float = 14.0
@export_range(0.0, 100.0, 1.0, "suffix:m/s²") var move_acceleration: float = 0.0

var can_fight: bool = true
var _buffered_action: StringName
var _buffer_time: float
var _roll_backwards: bool

@onready var _heading: Node3D = $Heading
@onready var _camera_rig: OrbitCamera = $CameraRig
@onready var _combat := get_node_or_null("Combat") as Combatant
@onready var _rig: Node3D = get_node_or_null("Heading/Rig")


func _unhandled_input(event: InputEvent) -> void:
	if _combat == null or not can_fight or _combat.action == &"dead":
		return
	for action in COMBAT_PRESSES:
		if event.is_action_pressed(action):
			_buffer(action)
			break


func _physics_process(delta: float) -> void:
	_camera_rig.update_orbit(delta)
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var target := _camera_rig.lock_target
	var back := _camera_rig.global_basis.z
	if is_instance_valid(target):
		back = _flat_direction(global_position - target.global_position)
	var right := Vector3.UP.cross(back)
	var direction := right * input.x + back * input.y
	var motion := direction * move_speed
	if _combat != null:
		var was_free := _combat.action == &""
		motion = _combat_motion(motion, direction, delta)
		if was_free and _combat.action != &"" and _combat.action != &"roll" and is_instance_valid(target):
			_face_target(target)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if move_acceleration > 0.0 and (_combat == null or _combat.action != &"roll"):
		horizontal = horizontal.move_toward(motion, move_acceleration * delta)
	else:
		horizontal = motion
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	_update_heading(target, direction, delta)
	if _rig != null:
		var local_velocity := _heading.global_basis.inverse() * get_real_velocity()
		var local_motion := Vector2(local_velocity.x, local_velocity.z).limit_length(move_speed) / move_speed
		var phase := _combat.pose_phase()
		if _combat.action == &"roll" and _roll_backwards:
			phase = 1.0 - phase
		_rig.apply_motion(_combat.clip(), phase, local_motion, delta)


func _combat_motion(motion: Vector3, direction: Vector3, delta: float) -> Vector3:
	if can_fight:
		if Input.is_action_just_pressed(&"parry_trigger"):
			_buffer(&"parry")
		elif Input.is_action_just_pressed(&"heavy_trigger"):
			_buffer(&"heavy_attack")
	_combat.blocking = can_fight and _combat.action == &"" and Input.is_action_pressed(&"block")
	_combat.advance(delta)
	if not can_fight:
		_buffered_action = &""
	elif _buffered_action != &"":
		if _combat.action == &"":
			match _buffered_action:
				&"light_attack": _combat.start_attack(_combat.light_attack)
				&"heavy_attack": _combat.start_attack(_combat.heavy_attack)
				&"parry": _combat.start_parry()
				&"roll":
					var backwards := direction.length_squared() <= 0.01
					var dodge := _heading.global_basis.z if backwards else direction
					if _combat.start_roll(dodge):
						_roll_backwards = backwards
			_buffered_action = &""
		else:
			_buffer_time -= delta
			if _buffer_time <= 0.0:
				_buffered_action = &""

	if _combat.action == &"roll":
		var speed := 7.6 if _combat.action_age < 0.29 else 7.6 * (1.0 - _combat.pose_phase()) / 0.47
		return _combat.dodge_direction * speed
	if not can_fight or _combat.action != &"":
		return -_heading.global_basis.z * _combat.lunge_speed()
	return motion * (0.38 if _combat.blocking else 1.0)


func _update_heading(target: Marker3D, direction: Vector3, delta: float) -> void:
	if _combat != null and (not can_fight or _combat.action != &""):
		if _combat.action == &"roll" and not _roll_backwards:
			var dodge := _combat.dodge_direction
			_heading.rotation.y = atan2(-dodge.x, -dodge.z)
		return
	if is_instance_valid(target):
		_face_target(target)
	elif direction.length_squared() > 0.0:
		var desired_yaw := atan2(-direction.x, -direction.z)
		_heading.rotation.y = rotate_toward(_heading.rotation.y, desired_yaw, turn_speed * delta)


func _face_target(target: Marker3D) -> void:
	var towards_target := _flat_direction(target.global_position - global_position)
	_heading.rotation.y = atan2(-towards_target.x, -towards_target.z)


func _buffer(action: StringName) -> void:
	_buffered_action = action
	_buffer_time = BUFFER_SECONDS


func buffer_status() -> String:
	return "%s %d ms" % [_buffered_action, roundi(_buffer_time * 1000.0)] if _buffered_action != &"" else "—"


func _flat_direction(vector: Vector3) -> Vector3:
	vector.y = 0.0
	return vector.normalized()
