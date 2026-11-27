extends CharacterBody3D

const OrbitCamera = preload("res://scenes/player/orbit_camera.gd")
const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const COMBAT_PRESSES: Array[StringName] = [&"roll", &"parry", &"heavy_attack", &"light_attack", &"jump"]
## Presses are kept this long while an action plays. Long enough to queue the next swing or a
## dodge during recovery, short enough that a stale press does not fire after the fact.
const BUFFER_SECONDS: float = 0.26
const JUMP_SPEED: float = 4.4
const SPRINT_STAMINA_PER_SECOND: float = 13.0
## Gravity is stronger while falling than while rising: jumps arc quickly and land with weight.
const RISE_GRAVITY := 1.3
const FALL_GRAVITY := 1.85
## A reversal above this speed plants the heels and skids before pushing off the other way.
const SKID_SPEED := 3.4
const SKID_TIME := 0.24
const SKID_BRAKE := 19.0

@export_range(0.1, 12.0, 0.1, "suffix:m/s") var move_speed: float = 4.5
@export_range(0.1, 12.0, 0.1, "suffix:m/s") var sprint_speed: float = 6.4
@export_range(1.0, 30.0, 0.5, "suffix:rad/s") var turn_speed: float = 14.0
## Start-up acceleration. 0 snaps to the input velocity (legacy behaviour).
@export_range(0.0, 100.0, 1.0, "suffix:m/s²") var move_acceleration: float = 0.0
## Braking when the stick is released or reversed. Lower values carry more momentum.
@export_range(0.0, 100.0, 1.0, "suffix:m/s²") var move_deceleration: float = 0.0
@export var weapons: Array[SoulsWeapon] = []

var can_fight: bool = true
var sprinting: bool
var _buffered_action: StringName
var _buffer_time: float
var _roll_backwards: bool
var _weapon_index: int
var _was_on_floor := true
var _air_time: float
var _skid_time: float
var _skid_direction := Vector3.ZERO
var _roll_landed: bool

@onready var _heading: Node3D = $Heading
@onready var _camera_rig: OrbitCamera = $CameraRig
@onready var _combat := get_node_or_null("Combat") as Combatant
@onready var _rig: Node3D = get_node_or_null("Heading/Rig")


func _ready() -> void:
	if _combat != null and not weapons.is_empty():
		_combat.equip(weapons[0])


func _unhandled_input(event: InputEvent) -> void:
	if _combat == null or not can_fight or _combat.action == &"dead":
		return
	if event.is_action_pressed(&"switch_weapon"):
		cycle_weapon()
		return
	for action in COMBAT_PRESSES:
		if event.is_action_pressed(action):
			_buffer(action)
			break


func cycle_weapon() -> bool:
	if weapons.size() < 2 or _combat.action != &"" or _combat.contact_frozen:
		return false
	_weapon_index = (_weapon_index + 1) % weapons.size()
	_combat.equip(weapons[_weapon_index])
	return true


func _physics_process(delta: float) -> void:
	_camera_rig.update_orbit(delta)
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var target := _camera_rig.lock_target
	var back := _camera_rig.global_basis.z
	if is_instance_valid(target):
		back = _flat_direction(global_position - target.global_position)
	var right := Vector3.UP.cross(back)
	var direction := right * input.x + back * input.y
	_update_sprint(direction, delta)
	var motion := direction * (sprint_speed if sprinting else move_speed)
	if _combat != null:
		var was_free := _combat.action == &""
		motion = _combat_motion(motion, direction, delta)
		if was_free and _combat.action != &"" and _combat.action != &"roll" and is_instance_valid(target):
			_face_target(target)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_update_skid(direction, horizontal, delta)
	if _combat != null and _combat.contact_frozen:
		horizontal = Vector3.ZERO
	elif _skid_time > 0.0:
		var speed := maxf(0.0, horizontal.length() - SKID_BRAKE * delta)
		horizontal = _skid_direction * speed
	elif move_acceleration > 0.0 and (_combat == null or _combat.action != &"roll"):
		var braking := motion.length_squared() < horizontal.length_squared() or motion.dot(horizontal) < 0.0
		var rate := move_deceleration if braking and move_deceleration > 0.0 else move_acceleration
		if not is_on_floor():
			rate *= 0.35
		horizontal = horizontal.move_toward(motion, rate * delta)
	else:
		horizontal = motion
	if _combat != null:
		horizontal += _combat.push
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta * (RISE_GRAVITY if velocity.y > 0.0 else FALL_GRAVITY)
		_air_time += delta
	var falling_speed := -velocity.y
	move_and_slide()
	if is_on_floor() and not _was_on_floor:
		if _air_time > 0.2 and _rig != null:
			var strength := clampf(falling_speed / 7.0, 0.25, 1.0)
			_rig.absorb(strength)
			RetroFX.dust(global_position, int(6 + 10 * strength))
			if _combat != null:
				_combat.feedback.emit(&"land", global_position, strength)
		_air_time = 0.0
	_was_on_floor = is_on_floor()

	_update_heading(target, direction, delta)
	if _rig != null:
		var local_velocity := _heading.global_basis.inverse() * get_real_velocity()
		# Normalized to walking-to-running speed; a sprint reads above 1 and blends the sprint clip.
		var local_motion := Vector2(local_velocity.x, local_velocity.z).limit_length(sprint_speed) / move_speed
		var phase := _combat.pose_phase()
		if _combat.action == &"roll" and _roll_backwards:
			phase = 1.0 - phase
		_rig.track_velocity(get_real_velocity(), delta, _combat.action != &"")
		_rig.skid = move_toward(_rig.skid, 1.0 if _skid_time > 0.0 else 0.0, delta * 9.0)
		_rig.apply_motion(_combat.clip(), phase, local_motion, delta)


func _update_sprint(direction: Vector3, delta: float) -> void:
	var wants := (can_fight and _combat != null and _combat.action == &"" and not _combat.blocking
			and direction.length_squared() > 0.25 and Input.is_action_pressed(&"sprint"))
	if wants and _combat.stamina > 1.0:
		sprinting = true
		_combat.stamina = maxf(0.0, _combat.stamina - SPRINT_STAMINA_PER_SECOND * delta)
		_combat.blocking = false
	else:
		sprinting = false


## Reversing at a run digs the heels in: the body keeps sliding along its old line while it
## turns, then pushes off. Short, readable, and the source of the "weight" in a direction change.
func _update_skid(direction: Vector3, horizontal: Vector3, delta: float) -> void:
	if _skid_time > 0.0:
		_skid_time -= delta
		if _skid_time <= 0.0 and direction.length_squared() > 0.04:
			velocity += direction.normalized() * 1.6
		return
	var busy := _combat != null and _combat.action != &""
	if busy or not is_on_floor() or horizontal.length() < SKID_SPEED or direction.length_squared() < 0.25:
		return
	if direction.normalized().dot(horizontal.normalized()) < -0.35:
		_skid_time = SKID_TIME
		_skid_direction = horizontal.normalized()
		RetroFX.dust(global_position + _skid_direction * 0.3, 14, 0.3)
		if _combat != null:
			_combat.feedback.emit(&"skid", global_position, clampf(horizontal.length() / 6.0, 0.3, 1.0))


func _combat_motion(motion: Vector3, direction: Vector3, delta: float) -> Vector3:
	if can_fight:
		if Input.is_action_just_pressed(&"parry_trigger"):
			_buffer(&"parry")
		elif Input.is_action_just_pressed(&"heavy_trigger"):
			_buffer(&"heavy_attack")
	_combat.blocking = can_fight and _combat.action == &"" and not sprinting and Input.is_action_pressed(&"block")
	_combat.charging = Input.is_action_pressed(&"heavy_attack") or Input.is_action_pressed(&"heavy_trigger")
	_combat.aim_target = _camera_rig.lock_target
	_combat.advance(delta)
	if not can_fight:
		_buffered_action = &""
	elif _buffered_action != &"":
		if _combat.action != &"" and _combat.can_cancel_into(_buffered_action):
			_combat.cancel_recovery()
		if _combat.action == &"" and not _combat.contact_frozen:
			match _buffered_action:
				&"light_attack": _combat.start_light()
				&"heavy_attack": _combat.start_heavy()
				&"parry": _combat.start_parry()
				&"jump":
					var g := get_gravity().length()
					var rise := JUMP_SPEED / (g * RISE_GRAVITY)
					var height := JUMP_SPEED * JUMP_SPEED / (2.0 * g * RISE_GRAVITY)
					var airtime := rise + sqrt(2.0 * height / (g * FALL_GRAVITY))
					if _combat.start_jump(airtime + 0.09):
						velocity.y = JUMP_SPEED
						Perf.mark(&"jump")
				&"roll":
					var backwards := direction.length_squared() <= 0.01
					var dodge := _heading.global_basis.z if backwards else direction
					if _combat.start_roll(dodge):
						_roll_backwards = backwards
			_buffered_action = &""
		elif not _holds_buffer():
			_buffer_time -= delta
			if _buffer_time <= 0.0:
				_buffered_action = &""

	if _combat.action == &"roll":
		# Burst, carry, then plant: the last fifth of the roll is the body landing and rising.
		var age := _combat.action_age
		var speed := 8.6 * smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.24, 0.48, age))
		if age >= 0.4 and not _roll_landed:
			_roll_landed = true
			_rig.absorb(0.35)
			RetroFX.dust(global_position, 9)
		return _combat.dodge_direction * speed
	_roll_landed = false
	if not can_fight:
		return Vector3.ZERO
	return motion * _combat.movement_weight() - _heading.global_basis.z * _combat.lunge_speed()


func _update_heading(target: Marker3D, direction: Vector3, delta: float) -> void:
	if _skid_time > 0.0 and direction.length_squared() > 0.0:
		_heading.rotation.y = rotate_toward(_heading.rotation.y, atan2(-direction.x, -direction.z), 16.0 * delta)
		return
	if _combat != null and (not can_fight or _combat.action != &""):
		if _combat.action == &"roll" and not _roll_backwards:
			var dodge := _combat.dodge_direction
			_heading.rotation.y = atan2(-dodge.x, -dodge.z)
		elif _combat.attack != null and _combat.action_age < _combat.attack.windup * 0.6 and direction.length_squared() > 0.04:
			# Early windup still accepts a steer, as in Souls games; after that the swing commits.
			var steer := atan2(-direction.x, -direction.z)
			_heading.rotation.y = rotate_toward(_heading.rotation.y, steer, 9.0 * delta)
		return
	if is_instance_valid(target) and not sprinting:
		_face_target(target, turn_speed * delta if _combat != null else TAU)
	elif direction.length_squared() > 0.0:
		var desired_yaw := atan2(-direction.x, -direction.z)
		var rate := turn_speed * (0.6 if sprinting else 1.0)
		_heading.rotation.y = rotate_toward(_heading.rotation.y, desired_yaw, rate * delta)


func _face_target(target: Marker3D, turn_limit: float = TAU) -> void:
	var towards_target := _flat_direction(target.global_position - global_position)
	var target_yaw := atan2(-towards_target.x, -towards_target.z)
	_heading.rotation.y = rotate_toward(_heading.rotation.y, target_yaw, turn_limit)


## A press made after a swing has started cutting waits for that swing's cancel point,
## so a queued follow-up or dodge is never lost to a slow weapon's long recovery.
func _holds_buffer() -> bool:
	var swing := _combat.attack
	return (swing != null and _combat.action_age >= swing.windup
			and _buffered_action in [&"light_attack", &"heavy_attack", &"roll"])


func _buffer(action: StringName) -> void:
	_buffered_action = action
	_buffer_time = BUFFER_SECONDS


func buffer_status() -> String:
	return "%s %d ms" % [_buffered_action, roundi(_buffer_time * 1000.0)] if _buffered_action != &"" else "—"


## Camera trauma for nearby impacts; blows the player gives or takes shake hardest.
func on_world_impact(cue: StringName, location: Vector3, strength: float) -> void:
	var base := 0.0
	match cue:
		&"hit", &"death": base = lerpf(0.22, 0.6, strength)
		&"block": base = lerpf(0.12, 0.32, strength)
		&"guard_break": base = 0.55
		&"knockdown": base = 0.5
		&"posture_break": base = 0.35
		&"shockwave": base = 0.6
		&"nova": base = 0.4
		&"skid": base = 0.06
		&"parry": base = 0.3
		&"land": base = 0.12
		&"heavy": base = 0.08 * strength
	if base <= 0.0:
		return
	var falloff := clampf(1.0 - global_position.distance_to(location) / 9.0, 0.0, 1.0)
	_camera_rig.add_trauma(base * falloff)


func _flat_direction(vector: Vector3) -> Vector3:
	vector.y = 0.0
	return vector.normalized()
