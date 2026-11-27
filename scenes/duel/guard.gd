extends CharacterBody3D
## Melee and ranged foes, from shambling husks to the Ash Gatekeeper. Each step it reads the
## player, plans one attack (or a boss combo) for the current range, closes to that attack's
## reach and commits. Leaps, spins, hit-and-run and backsteps come from the attack data.

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const BOSS_WEAPON = preload("res://scenes/combat/weapons/greatsword.tres")
const BOSS := "res://scenes/expedition/enemies/boss/"

signal phase_changed(phase: int)

@export var player: CharacterBody3D
@export var ai_enabled: bool = true
@export var pursuit_speed: float = 2.85
@export var notice_distance: float = 6.2
@export var role: StringName = &"watcher"
## Name on the health bar. Empty falls back to the area's caption for the role.
@export var title: String = ""
@export var boss_enabled: bool
## Body weight in motion: how fast it gets going, how long it slides to a stop, how fast it turns.
@export var acceleration: float = 14.0
@export var deceleration: float = 10.0
@export_range(0.5, 20.0, 0.1, "suffix:rad/s") var turn_rate: float = 8.0
## Seconds spent backing off after each attack (hit-and-run creatures).
@export_range(0.0, 3.0, 0.05, "suffix:s") var retreat_after_attack: float = 0.0
## Pause between attacks.
@export_range(0.0, 3.0, 0.05, "suffix:s") var attack_rest: float = 0.56

signal noticed

var boss_phase: int = 1
## Name of the boss move in progress, for the debug overlay and tests.
var boss_move: StringName

var _alerted: bool
var _next_thrust: bool
var _cooldown: float = 0.38
var _visible: bool
var _sight_delay: float
var _has_path: bool
var _plan: Array = []
var _last_move: StringName
var _retreat: float
var _backstep: float
var _leap_target: Vector3
var _boss_moves: Dictionary = {}

@onready var _combat: Combatant = $Combat
@onready var _heading: Node3D = $Heading
@onready var _rig: Node3D = $Heading/Rig
@onready var _navigation: NavigationAgent3D = $Navigation


func _ready() -> void:
	if boss_enabled:
		_combat.max_health = 154.0
		_combat.health = _combat.max_health
		_combat.armor = &"plate"
		_rig.scale *= 1.12
		_rig.set_weapon(BOSS_WEAPON)
		$LockPoint.position.y = 1.57
		for move in ["slash", "backhand", "thrust", "cleave", "delayed", "leap", "charge", "spin", "ash_wave"]:
			_boss_moves[StringName(move)] = load(BOSS + move + ".tres")


func is_engaged() -> bool:
	return ai_enabled and _alerted and _combat.health > 0.0


func _physics_process(delta: float) -> void:
	var previous := _combat.action
	_combat.blocking = role == &"shield" and previous == &"" and _combat.stamina > 0.0
	_combat.aim_target = player
	_combat.advance(delta)
	if previous != &"" and _combat.action == &"":
		_after_action(previous)
	if (boss_enabled and boss_phase == 1 and _combat.action == &"" and not _combat.contact_frozen
			and _combat.health > 0.0 and _combat.health < _combat.max_health * 0.5):
		boss_phase = 2
		_next_thrust = false
		_plan.clear()
		_combat.start_boss_phase()
		phase_changed.emit(boss_phase)
	var lunge := _combat.lunge_speed()
	var motion := -_heading.global_basis.z * lunge
	if ai_enabled and is_instance_valid(player) and _combat.action == &"" and not _combat.contact_frozen:
		motion = _read_player(delta)
	var leaping := _leap_motion(delta)
	_spin(delta)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if _combat.contact_frozen:
		horizontal = Vector3.ZERO
	elif leaping != Vector3.INF:
		horizontal = leaping
	elif lunge > 0.0:
		horizontal = motion
	else:
		var braking := motion.length_squared() < horizontal.length_squared() or motion.dot(horizontal) < 0.0
		horizontal = horizontal.move_toward(motion, (deceleration if braking else acceleration) * delta)
	horizontal += _combat.push
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta * (1.3 if velocity.y > 0.0 else 1.8)
	move_and_slide()
	var local_velocity := _heading.global_basis.inverse() * get_real_velocity()
	var local_motion := Vector2(local_velocity.x, local_velocity.z).limit_length(pursuit_speed) / pursuit_speed
	_rig.track_velocity(get_real_velocity(), delta, _combat.action != &"")
	_rig.apply_motion(_combat.clip(), _combat.pose_phase(), local_motion, delta)


func _after_action(previous: StringName) -> void:
	_cooldown = 0.36 if previous in [&"stagger", &"flinch"] else attack_rest
	if previous in [&"stagger", &"flinch", &"boss_phase"]:
		_plan.clear()
	elif not _plan.is_empty():
		# The next blow of a combo follows straight on, re-aimed at the player.
		_cooldown = 0.0
		if is_instance_valid(player):
			var offset := player.global_position - global_position
			_heading.rotation.y = lerp_angle(_heading.rotation.y, atan2(-offset.x, -offset.z), 0.65)
		_combat.start_attack(_plan.pop_front())
		return
	else:
		boss_move = &""
	if retreat_after_attack > 0.0 and previous not in [&"stagger", &"flinch", &"dead"]:
		_retreat = retreat_after_attack


func _read_player(delta: float) -> Vector3:
	var offset := player.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	_sight_delay -= delta
	if _sight_delay <= 0.0:
		_sight_delay = 0.15
		var sight := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP, player.global_position + Vector3.UP, 1)
		_visible = get_world_3d().direct_space_state.intersect_ray(sight).is_empty()
	if _visible and distance <= notice_distance and not _alerted:
		_alerted = true
		noticed.emit()
	if not _alerted:
		return Vector3.ZERO

	var aim := atan2(-offset.x, -offset.z)
	_heading.rotation.y = rotate_toward(_heading.rotation.y, aim, turn_rate * delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	var away := -offset.normalized()
	if _retreat > 0.0:
		_retreat -= delta
		return away * pursuit_speed * 0.9 if _clear_behind(away) else Vector3.ZERO
	if _backstep > 0.0:
		_backstep -= delta
		if _backstep <= 0.0:
			_attack_now(aim)
		return away * pursuit_speed * 1.6 if _clear_behind(away) else Vector3.ZERO
	if _plan.is_empty():
		_plan = _choose_plan(distance)
	var definition: DuelAttack = _plan[0]
	if role == &"thrower" and _visible and distance < 3.1:
		if _clear_behind(away):
			return away * (pursuit_speed * 0.72)
	var stop_distance := definition.reach - 0.55
	if distance > stop_distance or not _visible:
		if not _has_path or _navigation.target_position.distance_squared_to(player.global_position) > 0.16:
			_navigation.target_position = player.global_position
			_has_path = true
		var step := _navigation.get_next_path_position() - global_position
		step.y = 0.0
		return step.normalized() * pursuit_speed
	_has_path = false
	if _cooldown == 0.0 and absf(angle_difference(_heading.rotation.y, aim)) < 0.25:
		if boss_move == &"charge" and distance < 4.2:
			# Give ground first, then drive the thrust across the gap.
			_backstep = 0.42
			return away * pursuit_speed
		_attack_now(aim)
	return Vector3.ZERO


func _attack_now(_aim: float) -> void:
	if _plan.is_empty():
		return
	var definition: DuelAttack = _plan.pop_front()
	if _combat.start_attack(definition):
		_next_thrust = not _next_thrust
		if definition.leap > 0.0 and is_instance_valid(player):
			_leap_target = player.global_position
	else:
		_plan.clear()


func _clear_behind(away: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP,
		global_position + Vector3.UP + away * 1.1, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## One attack for ordinary foes; a gap closer when the heavy reaches much further.
func _choose_plan(distance: float) -> Array:
	if boss_enabled:
		return _boss_plan(distance)
	var light := _combat.light_attack
	var heavy := _combat.heavy_attack
	if heavy != light and (heavy.leap > 0.0 or heavy.reach > light.reach + 0.7):
		if distance > light.reach - 0.2 and distance < heavy.reach + 1.5:
			return [heavy]
		return [heavy] if randf() < 0.25 else [light]
	return [heavy if _next_thrust else light]


## The Ash Gatekeeper reads range and phase, never repeats a move back to back, and chains
## combos. Close: cuts, a three-blow string, a delayed overhead, a spin in phase two. Middle:
## thrusts, a charging lunge after a backstep. Far: a leaping slam, ash waves in phase two.
func _boss_plan(distance: float) -> Array:
	var two := boss_phase == 2
	var options := {}
	if distance < 3.0:
		options = {&"slash": 3, &"trio": 3 if two else 2, &"thrust": 1, &"delayed": 2, &"spin": 3 if two else 0}
	elif distance < 6.0:
		options = {&"thrust": 2, &"charge": 2, &"delayed": 1, &"leap": 1, &"ash_wave": 2 if two else 0}
	else:
		options = {&"leap": 3, &"charge": 2, &"ash_wave": 3 if two else 0}
	options.erase(_last_move)
	var total := 0
	for weight in options.values():
		total += weight
	var roll := randi() % maxi(total, 1)
	var move: StringName = &"slash"
	for key in options:
		roll -= options[key]
		if roll < 0:
			move = key
			break
	_last_move = move
	boss_move = move
	match move:
		&"trio":
			return [_boss_moves[&"slash"], _boss_moves[&"backhand"], _boss_moves[&"cleave"]]
		&"slash":
			return [_boss_moves[&"slash"], _boss_moves[&"spin"]] if two and randf() < 0.4 else [_boss_moves[&"slash"]]
		&"thrust":
			return [_boss_moves[&"thrust"], _boss_moves[&"cleave"]] if two else [_boss_moves[&"thrust"]]
	return [_boss_moves[move]]


## Horizontal velocity for the airborne part of a leaping attack, or INF when not leaping.
func _leap_motion(_delta: float) -> Vector3:
	var attack := _combat.attack
	if attack == null or attack.leap <= 0.0 or _combat.contact_frozen:
		return Vector3.INF
	var start := attack.windup * 0.55
	var land := attack.windup + attack.active * 0.5
	if _combat.action_age < start or _combat.action_age > land:
		return Vector3.INF
	if is_on_floor() and _combat.action_age < start + 0.05:
		velocity.y = 4.2
	var to_target := _leap_target - global_position
	to_target.y = 0.0
	var span := minf(to_target.length() - 1.0, attack.leap)
	if span <= 0.0:
		return Vector3.ZERO
	return to_target.normalized() * span / (land - start)


func _spin(delta: float) -> void:
	var attack := _combat.attack
	if attack == null or not attack.spin or _combat.contact_frozen:
		return
	if _combat.action_age >= attack.windup and _combat.action_age < attack.windup + attack.active:
		_heading.rotation.y = wrapf(_heading.rotation.y + TAU * delta / attack.active, -PI, PI)
