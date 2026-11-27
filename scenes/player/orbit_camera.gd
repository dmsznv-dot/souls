extends Node3D

@export_range(0.001, 0.015, 0.0001) var mouse_sensitivity: float = 0.0035
@export_range(0.5, 6.0, 0.1, "suffix:rad/s") var stick_speed: float = 2.6
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var camera_return_speed: float = 3.8
@export_range(1.0, 50.0, 0.5, "suffix:m") var lock_range: float = 20.0
@export_range(0.05, 1.0, 0.01, "suffix:s") var occlusion_grace_time: float = 0.35
@export_range(-0.4, 0.4, 0.01, "suffix:rad") var lock_yaw_offset: float = 0.0
@export_flags_3d_physics var sight_collision_mask: int = 1

var lock_target: Marker3D

var _mouse_motion: Vector2
var _using_mouse: bool = true
var _lock_requested: bool
var _occlusion_time: float
var _camera_distance: float

@onready var _pitch: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm
@onready var _arm_end: Node3D = $Pitch/SpringArm/ArmEnd
@onready var _camera: Camera3D = $Pitch/SpringArm/ArmEnd/Camera
@onready var _lock_marker: Label3D = $"../LockMarker"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_distance = _arm.spring_length


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"release_cursor"):
		_using_mouse = false
		_mouse_motion = Vector2.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif (not _using_mouse and event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		_using_mouse = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"lock_on") and (_using_mouse or event is InputEventJoypadButton):
		_lock_requested = true
	elif _using_mouse and event is InputEventMouseMotion:
		_mouse_motion += event.screen_relative


func update_orbit(delta: float) -> void:
	_update_lock(delta)
	if is_instance_valid(lock_target):
		var offset := lock_target.global_position - global_position
		var target_yaw := atan2(-offset.x, -offset.z) + lock_yaw_offset
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-14.0 * delta))
		_pitch.rotation.x = lerpf(_pitch.rotation.x, -0.22, 1.0 - exp(-10.0 * delta))
		_lock_marker.global_position = lock_target.global_position + Vector3.UP * 0.92
	else:
		var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		var motion := _mouse_motion * mouse_sensitivity + stick * stick_speed * delta
		rotation.y = wrapf(rotation.y - motion.x, -PI, PI)
		_pitch.rotation.x = clampf(_pitch.rotation.x - motion.y, -1.05, 0.65)
	_mouse_motion = Vector2.ZERO
	_lock_marker.visible = is_instance_valid(lock_target)


func _process(delta: float) -> void:
	# The arm endpoint has a valid position before the first physics query.
	var safe_distance := _arm_end.position.z
	_camera_distance = minf(safe_distance,
		move_toward(_camera_distance, _arm.spring_length, camera_return_speed * delta))
	# The arm moves its direct child immediately. The camera can only offset inward.
	_camera.position.z = _camera_distance - safe_distance


func _update_lock(delta: float) -> void:
	if is_instance_valid(lock_target) and lock_target.is_visible_in_tree():
		if _can_see_target(lock_target.global_position):
			_occlusion_time = 0.0
		else:
			_occlusion_time += delta
			if _occlusion_time >= occlusion_grace_time:
				lock_target = null
	else:
		lock_target = null

	if _lock_requested:
		lock_target = null if is_instance_valid(lock_target) else _find_target()
		_occlusion_time = 0.0
		_lock_requested = false


func _find_target() -> Marker3D:
	var best_target: Marker3D
	var best_alignment := -1.0
	for node in get_tree().get_nodes_in_group(&"lock_targets"):
		var target := node as Marker3D
		if target == null or not target.is_visible_in_tree():
			continue
		var point := target.global_position
		if (global_position.distance_squared_to(point) > lock_range * lock_range
				or not _camera.is_position_in_frustum(point)):
			continue
		var direction := _camera.global_position.direction_to(point)
		var alignment := -_camera.global_basis.z.dot(direction)
		if alignment > best_alignment and _can_see_target(point):
			best_target = target
			best_alignment = alignment
	return best_target


func _can_see_target(point: Vector3) -> bool:
	return (_has_line_of_sight(global_position, point)
		and _has_line_of_sight(_camera.global_position, point))


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, sight_collision_mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
