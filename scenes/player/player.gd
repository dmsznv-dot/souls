extends CharacterBody3D
## Hero controller. One physics tick: stamp this tick's presses into the command buffer, pick the
## one owner of horizontal motion (reaction > action > skid > locomotion), integrate the driven
## velocity toward its goal, add the separate external push once, move, then pose the rig.
## Tuning follows the movement and combat specification; see docs/movement-and-combat.md.

const OrbitCamera = preload("res://scenes/player/orbit_camera.gd")
const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const CommandBuffer = preload("res://scenes/player/command_buffer.gd")
const COMBAT_PRESSES: Array[StringName] = [&"roll", &"parry", &"heavy_attack", &"light_attack", &"jump"]
const JUMP_SPEED: float = 4.4
const JUMP_COST: float = 10.0
const PARRY_COST: float = 12.0
const SPRINT_STAMINA_PER_SECOND: float = 13.0
## Sprinting may start with at least this much stamina; once dry, the button must be released.
const SPRINT_ENTRY: float = 10.0
## Gravity is stronger while falling than while rising: jumps arc quickly and land with weight.
const RISE_GRAVITY := 1.30
const FALL_GRAVITY := 1.85
const AIR_CONTROL := 0.35
## Radial stick deadzone, and the stick travel at which a walk becomes a run.
const STICK_DEADZONE := 0.22
const WALK_EDGE := 0.55
## Skid: a reversal of at least 130 degrees at 4.2 m/s or more brakes along the old line.
const SKID_SPEED := 4.2
const SKID_STICK := 0.55
const SKID_DOT := -0.6428
const SKID_BRAKE := 38.0
const SKID_MAX_TIME := 8.0 / 60.0
## Hard landing: falling at 7 m/s or more costs 6 ticks of recovery.
const HARD_LANDING_SPEED := 7.0
const LANDING_RECOVERY := 6.0 / 60.0
## Turn rates in rad/s: 720 deg/s running, 480 sprinting, 600 locked on.
const TURN_RUN := 12.566
const TURN_SPRINT := 8.378
const TURN_LOCKED := 10.472
## Locked on, sideways and backward movement are slower than forward.
const STRAFE_SIDE := 0.85
const STRAFE_BACK := 0.75
## Early windup steering: the first half, at most 45 degrees in all, at most 540 deg/s.
const ATTACK_STEER_SHARE := 0.5
const ATTACK_STEER_LIMIT := 0.7854
const ATTACK_STEER_RATE := 9.425
## Cumulative share of roll distance over normalised roll age (monotone cubic through these).
const ROLL_CURVE := [Vector2(0.0, 0.0), Vector2(0.15, 0.12), Vector2(0.42, 0.62), Vector2(0.75, 0.96), Vector2(1.0, 1.0)]
const BACKSTEP_SHARE := 0.7
## Equipped load = (armour + active weapon) / capacity. Each class: [upper bound, speed scale,
## acceleration scale, roll ticks, i-frames [start, end) ticks, roll distance m, roll cost].
const CAPACITY := 50.0
const LOAD_CLASSES := [
	[0.30, 1.02, 1.10, 34, Vector2i(4, 21), 3.25, 18.0],
	[0.70, 1.00, 1.00, 39, Vector2i(5, 21), 2.95, 22.0],
	[1.00, 0.87, 0.82, 49, Vector2i(7, 20), 2.25, 29.0],
	[INF, 0.62, 0.70, 0, Vector2i.ZERO, 0.0, 0.0],
]

@export_range(0.1, 12.0, 0.1, "suffix:m/s") var walk_speed: float = 2.0
@export_range(0.1, 12.0, 0.1, "suffix:m/s") var move_speed: float = 4.5
@export_range(0.1, 12.0, 0.1, "suffix:m/s") var sprint_speed: float = 6.3
## Ground acceleration toward the stick, braking when slowing, and the rate that first kills
## momentum against a reversal.
@export_range(0.0, 100.0, 1.0, "suffix:m/s²") var move_acceleration: float = 32.0
@export_range(0.0, 100.0, 1.0, "suffix:m/s²") var move_deceleration: float = 38.0
@export_range(0.0, 100.0, 1.0, "suffix:m/s²") var reverse_deceleration: float = 44.0
## Mass of the worn armour; with the active weapon it sets the load class.
@export_range(0.0, 80.0, 0.5, "suffix:kg") var armor_mass: float = 20.0
@export var weapons: Array[SoulsWeapon] = []

var can_fight: bool = true
var sprinting: bool
var commands := CommandBuffer.new()
## Driven horizontal velocity (what the stick, a roll or a lunge asks for). The combatant's
## push is external and added once per tick, never folded back into this.
var drive := Vector3.ZERO
var _pending: Array[StringName] = []
var _roll_backwards: bool
var _weapon_index: int
var _was_on_floor := true
var _air_time: float
var _skid_time: float
var _skid_direction := Vector3.ZERO
var _roll_landed: bool
var _landing: float
var _sprint_locked: bool
var _attack_yaw: float
var _last_yaw_basis := Vector3.BACK
## Seconds the two-handed stance is held after the last sign of a fight.
var _combat_ready: float

@onready var _heading: Node3D = $Heading
@onready var _camera_rig: OrbitCamera = $CameraRig
@onready var _combat := get_node_or_null("Combat") as Combatant
@onready var _rig: Node3D = get_node_or_null("Heading/Rig")


func _ready() -> void:
	floor_max_angle = deg_to_rad(45.0)
	floor_snap_length = 0.18
	safe_margin = 0.002
	floor_stop_on_slope = true
	floor_constant_speed = true
	if _combat != null and not weapons.is_empty():
		_combat.equip(weapons[0])


func _unhandled_input(event: InputEvent) -> void:
	if _combat == null or not can_fight or _combat.action == &"dead" or event.is_echo():
		return
	if event.is_action_pressed(&"switch_weapon"):
		cycle_weapon()
		return
	for action in COMBAT_PRESSES:
		if event.is_action_pressed(action):
			_pending.append(action)
			break


## Weapon changes only from a free state; a successful change clears queued commands.
func cycle_weapon() -> bool:
	if weapons.size() < 2 or _combat.action != &"" or _combat.contact_frozen:
		return false
	_weapon_index = (_weapon_index + 1) % weapons.size()
	_combat.equip(weapons[_weapon_index])
	commands.clear()
	return true


## [speed scale, acceleration scale, roll ticks, i-frames, distance, cost] of the current load.
func load_class() -> Array:
	var mass := armor_mass + (_combat.weapon.mass if _combat != null and _combat.weapon != null else 0.0)
	var ratio := mass / CAPACITY
	for entry: Array in LOAD_CLASSES:
		if ratio < entry[0] or (entry[0] == 1.0 and ratio <= 1.0):
			return entry
	return LOAD_CLASSES[-1]


func overloaded() -> bool:
	return load_class()[0] == INF


func _physics_process(delta: float) -> void:
	var tick := Engine.get_physics_frames()
	for action in _pending:
		commands.offer(action, tick)
	_pending.clear()
	if Input.is_action_just_pressed(&"parry_trigger"):
		commands.offer(&"parry", tick)
	if Input.is_action_just_pressed(&"heavy_trigger"):
		commands.offer(&"heavy_attack", tick)
	if _combat != null and (not can_fight or _combat.action == &"dead"):
		commands.clear()

	_camera_rig.update_orbit(delta)
	var target := _camera_rig.lock_target
	var stick := _stick()
	var direction := _input_direction(stick, target)
	var load := load_class()
	_landing = maxf(0.0, _landing - delta)
	_update_sprint(direction, stick.length(), delta)
	var speed := _stick_speed(stick.length()) * float(load[1])
	if sprinting:
		speed = sprint_speed * float(load[1])
	var goal := direction * speed
	if is_instance_valid(target) and not sprinting:
		goal = _strafe(goal, target)

	var owner := &"locomotion"
	if _combat != null:
		var was_free := _combat.action == &""
		_combat_step(direction, tick, delta)
		if was_free and _combat.action != &"" and _combat.attack != null:
			_attack_yaw = _heading.rotation.y
			if is_instance_valid(target):
				_face_target(target)
				_attack_yaw = _heading.rotation.y
			# A lunge starts from a near halt: walking speed is not stacked on top of it.
			drive *= 0.3
		owner = _motion_owner()
	_update_skid(direction, stick.length(), owner, delta)
	if _skid_time > 0.0 and owner == &"locomotion":
		owner = &"skid"

	var horizontal := _drive_for(owner, goal, float(load[2]), delta)
	if _combat != null:
		horizontal += _combat.push
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta * (RISE_GRAVITY if velocity.y > 0.0 else FALL_GRAVITY)
		_air_time += delta
	var falling_speed := -velocity.y
	move_and_slide()
	_slide_off_walls()
	_land(falling_speed)
	_update_heading(target, direction, delta)
	_pose(target, delta)


func _stick() -> Vector2:
	# Raw strength, one radial deadzone applied here.
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back", 0.0)
	var amount := raw.length()
	if amount < STICK_DEADZONE:
		return Vector2.ZERO
	return raw.limit_length(1.0)


## Stick travel to ground speed: walk up to 2 m/s by 0.55 of travel, then run to 4.5 m/s.
func _stick_speed(amount: float) -> float:
	if amount <= STICK_DEADZONE:
		return 0.0
	if amount < WALK_EDGE:
		return walk_speed * (amount - STICK_DEADZONE) / (WALK_EDGE - STICK_DEADZONE)
	return lerpf(walk_speed, move_speed, clampf((amount - WALK_EDGE) / (1.0 - WALK_EDGE), 0.0, 1.0))


## Camera-relative, or target-relative when locked; a target almost underfoot keeps the last
## valid basis instead of collapsing to zero.
func _input_direction(stick: Vector2, target: Marker3D) -> Vector3:
	var back := _camera_rig.global_basis.z
	back.y = 0.0
	if is_instance_valid(target):
		var away := global_position - target.global_position
		away.y = 0.0
		if away.length() >= 0.25:
			back = away
		else:
			back = _last_yaw_basis
	back = back.normalized()
	_last_yaw_basis = back
	var right := Vector3.UP.cross(back)
	var direction := right * stick.x + back * stick.y
	return direction.normalized() if direction.length_squared() > 0.0 else Vector3.ZERO


func _strafe(goal: Vector3, target: Marker3D) -> Vector3:
	var forward := target.global_position - global_position
	forward.y = 0.0
	if forward.length() < 0.25:
		return goal
	forward = forward.normalized()
	var along := goal.dot(forward)
	var side := goal - forward * along
	return forward * along * (STRAFE_BACK if along < 0.0 else 1.0) + side * STRAFE_SIDE


func _motion_owner() -> StringName:
	match _combat.action:
		&"", &"jump":
			return &"locomotion"
		&"roll":
			return &"roll"
		&"flinch", &"stagger", &"dazed", &"knockdown", &"dead", &"winded":
			return &"reaction"
	return &"action"


func _drive_for(owner: StringName, goal: Vector3, accel_scale: float, delta: float) -> Vector3:
	if _combat != null and _combat.contact_frozen:
		# Hit-stop freezes the driven motion; the push keeps its own life.
		return Vector3.ZERO
	match owner:
		&"roll":
			drive = _roll_velocity(delta)
		&"reaction":
			drive = drive.move_toward(Vector3.ZERO, move_deceleration * delta)
		&"skid":
			drive = drive.move_toward(Vector3.ZERO, SKID_BRAKE * delta)
		&"action":
			var weight := _combat.movement_weight()
			drive = drive.move_toward(goal * weight, move_deceleration * delta)
			return drive - _heading.global_basis.z * _combat.lunge_speed()
		_:
			if _landing > 0.0 or not can_fight:
				goal = Vector3.ZERO
			if _combat != null:
				goal *= _combat.movement_weight()
			var desired := goal
			var rate := move_acceleration * accel_scale
			if drive.dot(desired) < 0.0:
				# A reversal first kills the old momentum.
				desired = Vector3.ZERO
				rate = reverse_deceleration
			elif desired.length_squared() < drive.length_squared():
				rate = move_deceleration
			if not is_on_floor():
				rate *= AIR_CONTROL
			drive = drive.move_toward(desired, rate * delta)
	return drive


## Roll displacement from a cumulative-distance curve: the speed this tick is the distance the
## curve adds between this tick's age and the next, so walls cut the roll short without
## carrying the blocked part over.
func _roll_velocity(delta: float) -> Vector3:
	var duration := maxf(_combat.roll_duration, 0.001)
	var u0 := clampf((_combat.action_age - delta) / duration, 0.0, 1.0)
	var u1 := clampf(_combat.action_age / duration, 0.0, 1.0)
	var distance := _combat.roll_distance * (BACKSTEP_SHARE if _roll_backwards else 1.0)
	var step := (_roll_curve(u1) - _roll_curve(u0)) * distance
	if not _roll_landed and u1 >= 0.62:
		_roll_landed = true
		if _rig != null:
			_rig.absorb(0.35)
		RetroFX.dust(global_position, 9)
	return _combat.dodge_direction * step / delta


## Monotone cubic (Fritsch-Carlson) through ROLL_CURVE.
static func _roll_curve(u: float) -> float:
	var points := ROLL_CURVE
	var i := 0
	while i < points.size() - 2 and u > points[i + 1].x:
		i += 1
	var a: Vector2 = points[i]
	var b: Vector2 = points[i + 1]
	var h := b.x - a.x
	var t := (u - a.x) / h
	var m0 := _slope(i)
	var m1 := _slope(i + 1)
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * a.y + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * b.y + (t3 - t2) * h * m1


static func _slope(k: int) -> float:
	var points := ROLL_CURVE
	if k == 0:
		return (points[1].y - points[0].y) / (points[1].x - points[0].x)
	if k == points.size() - 1:
		return (points[k].y - points[k - 1].y) / (points[k].x - points[k - 1].x)
	var left: float = (points[k].y - points[k - 1].y) / (points[k].x - points[k - 1].x)
	var right: float = (points[k + 1].y - points[k].y) / (points[k + 1].x - points[k].x)
	if left * right <= 0.0:
		return 0.0
	return 2.0 / (1.0 / left + 1.0 / right)


## Walls take the part of the driven velocity and push that runs into them, so pushing into a
## wall never accumulates speed along it.
func _slide_off_walls() -> void:
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if normal.y > 0.7:
			continue
		var wall := Vector3(normal.x, 0.0, normal.z).normalized()
		if wall == Vector3.ZERO:
			continue
		if drive.dot(wall) < 0.0:
			drive = drive.slide(wall)
		if _combat != null and _combat.push.dot(wall) < 0.0:
			_combat.push = _combat.push.slide(wall)


func _land(falling_speed: float) -> void:
	if is_on_floor() and not _was_on_floor:
		if _air_time > 0.2 and _rig != null:
			var strength := clampf(falling_speed / HARD_LANDING_SPEED, 0.25, 1.0)
			_rig.absorb(strength)
			RetroFX.dust(global_position, int(6 + 10 * strength))
			if _combat != null:
				_combat.feedback.emit(&"land", global_position, strength)
		if falling_speed >= HARD_LANDING_SPEED:
			_landing = LANDING_RECOVERY
		_air_time = 0.0
	_was_on_floor = is_on_floor()


func _pose(target: Marker3D, delta: float) -> void:
	if _rig == null:
		return
	# Heavy two-handers rest on the shoulder until a fight calls for the stance.
	_combat_ready = maxf(0.0, _combat_ready - delta)
	if is_instance_valid(target) or _combat.blocking or _combat.action not in [&"", &"roll", &"jump"]:
		_combat_ready = 2.5
	_rig.guard_up = _combat_ready > 0.0
	var local_velocity := _heading.global_basis.inverse() * get_real_velocity()
	# Normalised to walking-to-running speed; a sprint reads above 1 and blends the sprint clip.
	var local_motion := Vector2(local_velocity.x, local_velocity.z).limit_length(sprint_speed) / move_speed
	var phase := _combat.pose_phase()
	if _combat.action == &"roll" and _roll_backwards:
		phase = 1.0 - phase
	_rig.track_velocity(get_real_velocity(), delta, _combat.action != &"")
	_rig.skid = move_toward(_rig.skid, 1.0 if _skid_time > 0.0 else 0.0, delta * 9.0)
	_rig.apply_motion(_combat.clip(), phase, local_motion, delta)


## 13 stamina/s; starts at 10 or more and stops at zero; once dry the button must be released.
func _update_sprint(direction: Vector3, amount: float, delta: float) -> void:
	var held := Input.is_action_pressed(&"sprint")
	if not held:
		_sprint_locked = false
	var free := can_fight and _combat != null and _combat.action == &"" and not _combat.blocking
	var wants := free and held and amount > 0.5 and direction != Vector3.ZERO and not _sprint_locked and not overloaded()
	if wants and (sprinting or _combat.stamina >= SPRINT_ENTRY) and _combat.stamina > 0.0:
		sprinting = true
		_combat.drain(SPRINT_STAMINA_PER_SECOND * delta)
		if _combat.stamina <= 0.0:
			sprinting = false
			_sprint_locked = true
	else:
		sprinting = false


## Reversing at a run plants the heels: up to 8 ticks of braking along the old line, ended early
## by a stop, an action or leaving the floor. The new direction then takes over normally.
func _update_skid(direction: Vector3, amount: float, owner: StringName, delta: float) -> void:
	var flat := Vector3(drive.x, 0.0, drive.z)
	if _skid_time > 0.0:
		_skid_time -= delta
		if owner != &"locomotion" or not is_on_floor() or flat.length() <= 0.25:
			_skid_time = 0.0
		return
	if owner != &"locomotion" or not is_on_floor() or flat.length() < SKID_SPEED or amount < SKID_STICK:
		return
	if direction.dot(flat.normalized()) <= SKID_DOT:
		_skid_time = SKID_MAX_TIME
		_skid_direction = flat.normalized()
		RetroFX.dust(global_position + _skid_direction * 0.3, 14, 0.3)
		if _combat != null:
			_combat.feedback.emit(&"skid", global_position, clampf(flat.length() / 6.0, 0.3, 1.0))


## Takes the buffered command if it may start now: every condition and cost is checked before
## the current recovery is cut, so an unaffordable press never ends a swing early.
func _combat_step(direction: Vector3, tick: int, delta: float) -> void:
	var guard_held := can_fight and _combat.action == &"" and not sprinting and Input.is_action_pressed(&"block")
	_combat.blocking = guard_held
	_combat.charging = Input.is_action_pressed(&"heavy_attack") or Input.is_action_pressed(&"heavy_trigger")
	_combat.aim_target = _camera_rig.lock_target
	_combat.advance(delta)
	var command := commands.peek(tick)
	if command == &"" or not can_fight or _combat.contact_frozen or _landing > 0.0:
		return
	var free := _combat.action == &""
	var cancel := not free and _combat.can_cancel_into(command)
	if not free and not cancel:
		return
	if not _affordable(command, direction):
		if free:
			# Permanently impossible from here (no stamina, overloaded, airborne): drop it.
			_combat.emit_refusal(command)
			commands.clear()
		return
	if cancel:
		_combat.cancel_recovery()
	match command:
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
			var backwards := direction == Vector3.ZERO
			var dodge := _heading.global_basis.z if backwards else direction
			var load := load_class()
			var profile := [load[3] / 60.0, Vector2(load[4]) / 60.0, load[5], load[6]]
			if _combat.start_roll(dodge, profile):
				_roll_backwards = backwards
				_roll_landed = false
				_skid_time = 0.0
	commands.clear()


func _affordable(command: StringName, _direction: Vector3) -> bool:
	match command:
		&"light_attack":
			var next := _combat.next_light()
			return next != null and _combat.can_afford(next.stamina_cost) and (_combat.focus >= next.focus_cost or _combat.weapon.fallback_light != null)
		&"heavy_attack":
			var heavy := _combat.heavy_attack
			return heavy != null and _combat.can_afford(heavy.stamina_cost) and _combat.focus >= heavy.focus_cost
		&"parry":
			return _combat.can_afford(PARRY_COST)
		&"jump":
			return is_on_floor() and not overloaded() and _combat.can_afford(JUMP_COST)
		&"roll":
			return is_on_floor() and not overloaded() and _combat.can_afford(float(load_class()[6]))
	return false


func _update_heading(target: Marker3D, direction: Vector3, delta: float) -> void:
	if _skid_time > 0.0 and direction != Vector3.ZERO:
		_heading.rotation.y = rotate_toward(_heading.rotation.y, atan2(-direction.x, -direction.z), TURN_RUN * delta)
		return
	if _combat != null and (not can_fight or _combat.action != &""):
		if _combat.action == &"roll" and not _roll_backwards:
			var dodge := _combat.dodge_direction
			_heading.rotation.y = atan2(-dodge.x, -dodge.z)
		elif _combat.attack != null and _combat.action_age < _combat.attack.windup * ATTACK_STEER_SHARE:
			# The first half of a windup still steers, toward the locked target or the stick,
			# at most 45 degrees from where the swing began; after that the swing commits.
			var steer := NAN
			if is_instance_valid(target):
				var to_target := _flat_direction(target.global_position - global_position)
				steer = atan2(-to_target.x, -to_target.z)
			elif direction != Vector3.ZERO:
				steer = atan2(-direction.x, -direction.z)
			if not is_nan(steer):
				var offset := clampf(angle_difference(_attack_yaw, steer), -ATTACK_STEER_LIMIT, ATTACK_STEER_LIMIT)
				_heading.rotation.y = rotate_toward(_heading.rotation.y, _attack_yaw + offset, ATTACK_STEER_RATE * delta)
		return
	if is_instance_valid(target) and not sprinting:
		_face_target(target, TURN_LOCKED * delta)
	elif direction != Vector3.ZERO:
		var desired_yaw := atan2(-direction.x, -direction.z)
		_heading.rotation.y = rotate_toward(_heading.rotation.y, desired_yaw, (TURN_SPRINT if sprinting else TURN_RUN) * delta)


func _face_target(target: Marker3D, turn_limit: float = TAU) -> void:
	var towards_target := _flat_direction(target.global_position - global_position)
	if towards_target == Vector3.ZERO:
		return
	var target_yaw := atan2(-towards_target.x, -towards_target.z)
	_heading.rotation.y = rotate_toward(_heading.rotation.y, target_yaw, turn_limit)


func buffer_status() -> String:
	return commands.describe(Engine.get_physics_frames())


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
	return vector.normalized() if vector.length_squared() > 0.0 else Vector3.ZERO
