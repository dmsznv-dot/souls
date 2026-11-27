extends Node3D

@export_range(0.001, 0.015, 0.0001) var mouse_sensitivity: float = 0.0035
@export_range(0.5, 6.0, 0.1, "suffix:rad/s") var stick_speed: float = 2.6
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var camera_return_speed: float = 3.8
@export_range(1.0, 50.0, 0.5, "suffix:m") var lock_range: float = 20.0
@export_range(0.05, 1.0, 0.01, "suffix:s") var occlusion_grace_time: float = 0.35
@export_range(-0.4, 0.4, 0.01, "suffix:rad") var lock_yaw_offset: float = 0.0
@export_flags_3d_physics var sight_collision_mask: int = 1
## How quickly the rig catches up with the body. Lower values trail more and read as weight.
@export_range(1.0, 40.0, 0.5) var follow_rate: float = 14.0
@export_range(1.0, 40.0, 0.5) var vertical_follow_rate: float = 7.0
## Player setting, 0..1. Scales screen shake.
@export_range(0.0, 1.0, 0.05) var shake_strength: float = 1.0

var lock_target: Marker3D

var _mouse_motion: Vector2
var _using_mouse: bool = true
var _lock_requested: bool
## Sideways look input gathered while locked; a flick past the threshold switches target.
var _switch_push: float
var _switch_cooldown: float
var _stick_centered := true
const SWITCH_THRESHOLD := 0.22
var _occlusion_time: float
var _camera_distance: float
var _anchor_offset: Vector3
var _follow: Vector3
var trauma: float
var _shake_clock: float
var _base_fov: float

@onready var _pitch: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm
@onready var _arm_end: Node3D = $Pitch/SpringArm/ArmEnd
@onready var _camera: Camera3D = $Pitch/SpringArm/ArmEnd/Camera
@onready var _lock_marker: Label3D = $"../LockMarker"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_distance = _arm.spring_length
	_base_fov = _camera.fov
	_anchor_offset = position
	top_level = true
	_follow = get_parent().global_position + _anchor_offset
	global_position = _follow


## After a teleport: jump straight to the body instead of gliding there.
func snap() -> void:
	_follow = get_parent().global_position + _anchor_offset
	global_position = _follow
	reset_physics_interpolation()


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


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
	# Trail the body slightly: snappy in the plane, softer vertically so jumps and steps breathe.
	var goal: Vector3 = get_parent().global_position + _anchor_offset
	if _follow.distance_squared_to(goal) > 16.0:
		_follow = goal
		global_position = goal
		reset_physics_interpolation()
	var plane := 1.0 - exp(-follow_rate * delta)
	_follow.x = lerpf(_follow.x, goal.x, plane)
	_follow.z = lerpf(_follow.z, goal.z, plane)
	_follow.y = lerpf(_follow.y, goal.y, 1.0 - exp(-vertical_follow_rate * delta))
	global_position = _follow
	_update_lock(delta)
	_switch_cooldown = maxf(0.0, _switch_cooldown - delta)
	if is_instance_valid(lock_target):
		# Flick the mouse or the right stick sideways to move the lock to the next foe that way.
		var stick_x := Input.get_axis(&"look_left", &"look_right")
		_switch_push = _switch_push * exp(-8.0 * delta) + _mouse_motion.x * mouse_sensitivity
		var flick := 0.0
		if absf(_switch_push) > SWITCH_THRESHOLD:
			flick = signf(_switch_push)
		elif _stick_centered and absf(stick_x) > 0.8:
			flick = signf(stick_x)
		_stick_centered = absf(stick_x) < 0.3
		if flick != 0.0 and _switch_cooldown == 0.0:
			switch_target(flick)
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
	# The arm endpoint has a valid position before the first physics query.
	var safe_distance := _arm_end.position.z
	_camera_distance = minf(safe_distance,
		move_toward(_camera_distance, _arm.spring_length, camera_return_speed * delta))
	# The arm moves its direct child immediately. The camera can only offset inward.
	_camera.position.z = _camera_distance - safe_distance


func _process(delta: float) -> void:
	# Projection offsets and FOV only: transforms move in the physics tick so that physics
	# interpolation can smooth them on high-refresh displays.
	_update_shake(delta)
	var body := get_parent()
	var sprint_fov: float = _base_fov + (5.0 if body.get(&"sprinting") else 0.0)
	_camera.fov = lerpf(_camera.fov, sprint_fov, 1.0 - exp(-4.0 * delta))


## Trauma-squared shake through the camera's projection offsets, decaying in real time so hit-stop cannot freeze it
## off-centre. Summed sines instead of per-frame noise keep it from buzzing.
func _update_shake(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.0001)
	if trauma <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	trauma = maxf(trauma - 1.6 * real_delta, 0.0)
	_shake_clock += real_delta * 32.0
	var shake := trauma * trauma * shake_strength
	_camera.h_offset = 0.16 * shake * sin(_shake_clock * 1.7)
	_camera.v_offset = 0.11 * shake * sin(_shake_clock * 2.3 + 1.1)


func _update_lock(delta: float) -> void:
	if is_instance_valid(lock_target) and lock_target.is_visible_in_tree():
		if _can_see_target(lock_target.global_position):
			_occlusion_time = 0.0
		else:
			_occlusion_time += delta
			if _occlusion_time >= occlusion_grace_time:
				lock_target = null
	else:
		# The locked foe fell (its marker hides): carry the lock to the next one in view, as
		# Souls games do. A marker freed with its streamed area just drops the lock.
		lock_target = _find_target() if is_instance_valid(lock_target) else null
		_occlusion_time = 0.0

	if _lock_requested:
		lock_target = null if is_instance_valid(lock_target) else _find_target()
		_occlusion_time = 0.0
		_lock_requested = false


## Moves the lock to the nearest other target on that side of the screen (-1 left, 1 right).
func switch_target(side: float) -> bool:
	_switch_push = 0.0
	_switch_cooldown = 0.3
	if not is_instance_valid(lock_target):
		return false
	var current := _camera.unproject_position(lock_target.global_position)
	var best: Marker3D
	var best_gap := INF
	for node in get_tree().get_nodes_in_group(&"lock_targets"):
		var target := node as Marker3D
		if target == null or target == lock_target or not target.is_visible_in_tree():
			continue
		var point := target.global_position
		if (global_position.distance_squared_to(point) > lock_range * lock_range
				or not _camera.is_position_in_frustum(point) or not _can_see_target(point)):
			continue
		var gap := (_camera.unproject_position(point).x - current.x) * side
		if gap > 4.0 and gap < best_gap:
			best = target
			best_gap = gap
	if best == null:
		return false
	lock_target = best
	_occlusion_time = 0.0
	return true


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
