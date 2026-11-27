extends CharacterBody3D
## Foes from shambling husks to the Ash Gatekeeper.
##
## Perception: a view cone and line of sight, hearing for a sprinting player, and alarms from
## allies. Once hunting, a foe asks the Director for an attack token. Without one it circles at
## a spacing ring, strafing and keeping clear of its allies; with one it closes to its planned
## attack's reach, hesitates a beat and commits, tracking the player through the early windup.
## It may sidestep the player's swings, punishes openings, backs off after taking hits, and if
## it loses the player it searches their last position before returning to its post.

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const BOSS_WEAPON = preload("res://scenes/combat/weapons/greatsword.tres")
const BOSS := "res://scenes/expedition/enemies/boss/"

signal phase_changed(phase: int)
signal noticed

enum Mode { IDLE, HUNT, SEARCH, RETURN }

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

@export_group("Tactics")
## Chance to roll away from a swing that will reach it.
@export_range(0.0, 1.0, 0.05) var evade_chance: float = 0.15
## Chance to seize an opening: the player recovering from a swing, winded or reeling.
@export_range(0.0, 1.0, 0.05) var punish_chance: float = 0.6
## Chance to step back out of range after being hit.
@export_range(0.0, 1.0, 0.05) var backoff_chance: float = 0.35
## Share of the Director's attack budget this foe uses while attacking.
@export_range(1, 3) var token_cost: int = 1
## Full width of the view cone. Behind it, the player can approach unseen.
@export_range(30.0, 360.0, 5.0, "degrees") var view_angle: float = 140.0
## Spacing ring while waiting to attack; 0 derives it from the planned attack's reach.
@export_range(0.0, 12.0, 0.1, "suffix:m") var circle_distance: float = 0.0
## How far it follows from its post before giving up.
@export_range(5.0, 60.0, 1.0, "suffix:m") var leash: float = 24.0

var boss_phase: int = 1
## Name of the boss move in progress, for the debug overlay and tests.
var boss_move: StringName
var mode: Mode = Mode.IDLE

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
var _post: Vector3
var _last_seen: Vector3
var _lost_time: float
var _search_time: float
var _strafe_dir: float = 1.0
var _strafe_timer: float
var _hesitate: float = -1.0
var _evade_cooldown: float
var _counter_ready: bool

@onready var _combat: Combatant = $Combat
@onready var _heading: Node3D = $Heading
@onready var _rig: Node3D = $Heading/Rig
@onready var _navigation: NavigationAgent3D = $Navigation


func _ready() -> void:
	add_to_group(&"foes")
	_post = global_position
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	_combat.feedback.connect(_on_own_feedback)
	_combat.defeated.connect(func() -> void: _director_release())
	if boss_enabled:
		_combat.max_health = 154.0
		_combat.health = _combat.max_health
		_combat.armor = &"plate"
		_rig.scale *= 1.12
		_rig.set_weapon(BOSS_WEAPON)
		$LockPoint.position.y = 1.57
		view_angle = 360.0
		evade_chance = 0.0
		for move in ["slash", "backhand", "thrust", "cleave", "delayed", "leap", "charge", "spin", "ash_wave"]:
			_boss_moves[StringName(move)] = load(BOSS + move + ".tres")


func is_engaged() -> bool:
	return ai_enabled and mode == Mode.HUNT and _combat.health > 0.0


## An ally raised the alarm: go and look where it was.
func hear_alarm(at: Vector3) -> void:
	if not ai_enabled or _combat.health <= 0.0 or mode == Mode.HUNT:
		return
	mode = Mode.SEARCH
	_last_seen = at
	_search_time = 0.0


func _physics_process(delta: float) -> void:
	var previous := _combat.action
	_combat.blocking = (role == &"shield" and previous == &"" and _combat.stamina > 0.0
			and (mode == Mode.HUNT or not ai_enabled))
	_combat.aim_target = player
	_combat.advance(delta)
	if previous != &"" and _combat.action == &"":
		_after_action(previous)
	if (boss_enabled and boss_phase == 1 and _combat.action == &"" and not _combat.contact_frozen
			and _combat.health > 0.0 and _combat.health < _combat.max_health * 0.5):
		boss_phase = 2
		evade_chance = 0.3
		_next_thrust = false
		_plan.clear()
		_combat.start_boss_phase()
		phase_changed.emit(boss_phase)
	_evade_cooldown = maxf(0.0, _evade_cooldown - delta)
	var lunge := _combat.lunge_speed()
	var motion := -_heading.global_basis.z * lunge
	var direct := lunge > 0.0
	if _combat.action == &"roll":
		var age := _combat.action_age
		motion = _combat.dodge_direction * 7.2 * smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.24, 0.48, age))
		direct = true
	elif ai_enabled and is_instance_valid(player) and _combat.action == &"" and not _combat.contact_frozen:
		motion = _think(delta)
	elif ai_enabled and is_instance_valid(player):
		_track_windup(delta)
	var leaping := _leap_motion(delta)
	_spin(delta)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if _combat.contact_frozen:
		horizontal = Vector3.ZERO
	elif leaping != Vector3.INF:
		horizontal = leaping
	elif direct:
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
	var hurt := previous in [&"stagger", &"flinch"]
	_cooldown = 0.36 if hurt else attack_rest * randf_range(0.8, 1.5)
	_hesitate = -1.0
	if hurt or previous == &"boss_phase":
		_plan.clear()
		if hurt and randf() < backoff_chance:
			_retreat = randf_range(0.35, 0.6)
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
	if previous not in [&"roll", &"flinch", &"stagger"]:
		_director_release()
	if retreat_after_attack > 0.0 and not hurt and previous != &"dead":
		_retreat = retreat_after_attack


func _think(delta: float) -> Vector3:
	var offset := player.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	_sight_delay -= delta
	if _sight_delay <= 0.0:
		_sight_delay = 0.15
		var sight := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP, player.global_position + Vector3.UP, 1)
		_visible = get_world_3d().direct_space_state.intersect_ray(sight).is_empty()
	var facing := -_heading.global_basis.z
	var in_cone := distance < 2.0 or facing.angle_to(offset.normalized()) <= deg_to_rad(view_angle * 0.5)
	var heard := distance < 5.0 and bool(player.get(&"sprinting"))
	var sees := _visible and distance <= notice_distance * (1.6 if mode == Mode.HUNT else 1.0) and (in_cone or mode == Mode.HUNT)
	match mode:
		Mode.IDLE, Mode.RETURN, Mode.SEARCH:
			if sees or heard:
				_engage()
			else:
				return _wander(delta)
	if sees:
		_last_seen = player.global_position
		_lost_time = 0.0
	else:
		_lost_time += delta
		if _lost_time > 2.5 and not boss_enabled:
			mode = Mode.SEARCH
			_search_time = 0.0
			_director_release()
			return Vector3.ZERO
	if not boss_enabled and global_position.distance_to(_post) > leash:
		mode = Mode.RETURN
		_director_release()
		return Vector3.ZERO

	var aim := atan2(-offset.x, -offset.z)
	_heading.rotation.y = rotate_toward(_heading.rotation.y, aim, turn_rate * delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	var away := -offset.normalized()
	if _retreat > 0.0:
		_retreat -= delta
		return away * pursuit_speed * 0.9 if _clear(away) else Vector3.ZERO
	if _backstep > 0.0:
		_backstep -= delta
		if _backstep <= 0.0:
			_attack_now()
		return away * pursuit_speed * 1.6 if _clear(away) else Vector3.ZERO
	if _try_evade(distance, away):
		return Vector3.ZERO
	if _plan.is_empty():
		_plan = _choose_plan(distance)
	var definition: DuelAttack = _plan[0]
	if role == &"thrower" and _visible and distance < 3.1 and _clear(away):
		return away * (pursuit_speed * 0.72)
	var opening := _player_opening()
	var may_attack := _cooldown == 0.0 or (_counter_ready and distance < definition.reach)
	if may_attack and not _has_token():
		may_attack = Director.request(self, token_cost, opening or _counter_ready)
	if not may_attack:
		return _circle(distance, definition, delta)
	var stop_distance := definition.reach - 0.55
	if distance > stop_distance or not _visible:
		return _navigate_to(player.global_position)
	_has_path = false
	if _hesitate < 0.0:
		# A beat of reaction time before committing; openings and counters skip it.
		_hesitate = 0.0 if opening or _counter_ready or boss_enabled else randf_range(0.0, 0.3)
	_hesitate -= delta
	if _hesitate <= 0.0 and absf(angle_difference(_heading.rotation.y, aim)) < 0.25:
		_counter_ready = false
		if boss_move == &"charge" and distance < 4.2:
			# Give ground first, then drive the thrust across the gap.
			_backstep = 0.42
			return away * pursuit_speed
		_attack_now()
	return Vector3.ZERO


func _engage() -> void:
	if mode != Mode.HUNT:
		mode = Mode.HUNT
		_lost_time = 0.0
		if not _alerted:
			_alerted = true
			noticed.emit()
		Director.alert(self, 9.0)


func _wander(delta: float) -> Vector3:
	match mode:
		Mode.SEARCH:
			_search_time += delta
			if _search_time > 5.0 or global_position.distance_to(_last_seen) < 1.0:
				if _search_time > 5.0:
					mode = Mode.RETURN
				return Vector3.ZERO
			_face(_last_seen, delta)
			return _navigate_to(_last_seen) * 0.75
		Mode.RETURN:
			if global_position.distance_to(_post) < 0.8:
				mode = Mode.IDLE
				return Vector3.ZERO
			_face(_post, delta)
			return _navigate_to(_post) * 0.6
	return Vector3.ZERO


## Keeps a ring around the player while another foe has the attack: strafing sideways,
## easing in and out to hold the spacing, pausing now and then, never stacking on allies.
func _circle(distance: float, definition: DuelAttack, delta: float) -> Vector3:
	var ring := circle_distance
	if ring <= 0.0:
		ring = clampf(definition.reach + 1.3, 3.0, 5.5)
		if role == &"thrower":
			ring = 7.0
	if distance > ring + 3.0 or not _visible:
		return _navigate_to(player.global_position)
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.0, 2.6)
		var roll := randf()
		_strafe_dir = 0.0 if roll < 0.2 else (1.0 if roll < 0.6 else -1.0)
	var toward := (player.global_position - global_position)
	toward.y = 0.0
	toward = toward.normalized()
	var tangent := toward.cross(Vector3.UP) * _strafe_dir
	var steer := tangent * 0.85 + toward * clampf((distance - ring) * 0.9, -1.0, 1.0)
	for other in get_tree().get_nodes_in_group(&"foes"):
		if other == self or not other.is_inside_tree():
			continue
		var gap: Vector3 = global_position - other.global_position
		gap.y = 0.0
		if gap.length() < 1.6 and gap.length() > 0.01:
			steer += gap.normalized() * (1.6 - gap.length()) * 1.5
	if steer.length_squared() < 0.01:
		return Vector3.ZERO
	if not _clear(steer.normalized()):
		_strafe_dir = -_strafe_dir
	return steer.limit_length(1.0) * pursuit_speed * 0.55


## Rolls away from a swing about to land, if it will reach and the foe is quick enough.
func _try_evade(distance: float, away: Vector3) -> bool:
	if evade_chance <= 0.0 or _evade_cooldown > 0.0:
		return false
	var threat: Node = player.get_node_or_null("Combat")
	if threat == null or threat.attack == null or threat.action_age > threat.attack.windup * 0.7:
		return false
	if distance > threat.attack.reach + 0.6:
		return false
	_evade_cooldown = 1.4
	if randf() >= evade_chance:
		return false
	var side := away.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	var direction := (away + side * 0.8).normalized()
	if not _clear(direction):
		direction = away
	return _combat.start_roll(direction)


func _player_opening() -> bool:
	var threat: Node = player.get_node_or_null("Combat")
	if threat == null or randf() > punish_chance:
		return false
	if threat.action in [&"flinch", &"stagger"] or threat.stamina < 12.0:
		return true
	return threat.attack != null and threat.action_age > threat.attack.windup + threat.attack.active


## Swings track the player through the early windup, then commit.
func _track_windup(delta: float) -> void:
	var attack := _combat.attack
	if attack == null or attack.spin or _combat.action_age > attack.windup * 0.75:
		return
	var offset := player.global_position - global_position
	_heading.rotation.y = rotate_toward(_heading.rotation.y, atan2(-offset.x, -offset.z), turn_rate * 0.6 * delta)


func _on_own_feedback(cue: StringName, _at: Vector3, _strength: float) -> void:
	if cue == &"block" and role == &"shield" and randf() < 0.6:
		_counter_ready = true
		_cooldown = 0.0


func _face(target: Vector3, delta: float) -> void:
	var offset := target - global_position
	offset.y = 0.0
	if offset.length_squared() > 0.01:
		_heading.rotation.y = rotate_toward(_heading.rotation.y, atan2(-offset.x, -offset.z), turn_rate * 0.6 * delta)


func _navigate_to(target: Vector3) -> Vector3:
	if not _has_path or _navigation.target_position.distance_squared_to(target) > 0.16:
		_navigation.target_position = target
		_has_path = true
	var step := _navigation.get_next_path_position() - global_position
	step.y = 0.0
	return step.normalized() * pursuit_speed


func _has_token() -> bool:
	return boss_enabled or Director.holds(self)


func _director_release() -> void:
	if not boss_enabled:
		Director.release(self)


func _attack_now() -> void:
	if _plan.is_empty():
		return
	var definition: DuelAttack = _plan.pop_front()
	if _combat.start_attack(definition):
		_next_thrust = not _next_thrust
		if definition.leap > 0.0 and is_instance_valid(player):
			_leap_target = player.global_position
	else:
		_plan.clear()
		_director_release()


func _clear(direction: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP,
		global_position + Vector3.UP + direction * 1.1, 1)
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
	if heavy != light and randf() < 0.3:
		# Ordinary foes string two blows together now and then.
		return [light, heavy]
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
