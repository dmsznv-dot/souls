extends CharacterBody3D

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const BOSS_CLEAVE = preload("res://scenes/expedition/enemies/boss_cleave.tres")

signal phase_changed(phase: int)

@export var player: CharacterBody3D
@export var ai_enabled: bool = true
@export var pursuit_speed: float = 2.85
@export var notice_distance: float = 6.2
@export var role: StringName = &"watcher"
@export var boss_enabled: bool

var boss_phase: int = 1

var _alerted: bool
var _next_thrust: bool
var _cooldown: float = 0.38
var _visible: bool
var _sight_delay: float
var _has_path: bool

@onready var _combat: Combatant = $Combat
@onready var _heading: Node3D = $Heading
@onready var _rig: Node3D = $Heading/Rig
@onready var _navigation: NavigationAgent3D = $Navigation


func _ready() -> void:
	if boss_enabled:
		_combat.max_health = 154.0
		_combat.health = _combat.max_health
		_rig.scale *= 1.12
		$LockPoint.position.y = 1.57


func _physics_process(delta: float) -> void:
	var previous := _combat.action
	_combat.blocking = role == &"shield" and previous == &"" and _combat.stamina > 0.0
	_combat.advance(delta)
	if previous != &"" and _combat.action == &"":
		_cooldown = 0.36 if previous == &"stagger" else 0.56
		if boss_phase == 2 and previous == &"enemy_slash" and _next_thrust:
			_cooldown = 0.12
	if (boss_enabled and boss_phase == 1 and _combat.action == &"" and not _combat.contact_frozen
			and _combat.health > 0.0 and _combat.health < _combat.max_health * 0.5):
		boss_phase = 2
		_next_thrust = false
		_combat.start_boss_phase()
		phase_changed.emit(boss_phase)
	var motion := -_heading.global_basis.z * _combat.lunge_speed()
	if ai_enabled and is_instance_valid(player) and _combat.action == &"" and not _combat.contact_frozen:
		motion = _read_player(delta)
	velocity.x = motion.x
	velocity.z = motion.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	var local_velocity := _heading.global_basis.inverse() * get_real_velocity()
	var local_motion := Vector2(local_velocity.x, local_velocity.z).limit_length(pursuit_speed) / pursuit_speed
	_rig.apply_motion(_combat.clip(), _combat.pose_phase(), local_motion, delta)


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
	if _visible and distance <= notice_distance:
		_alerted = true
	if not _alerted:
		return Vector3.ZERO

	var aim := atan2(-offset.x, -offset.z)
	_heading.rotation.y = rotate_toward(_heading.rotation.y, aim, 8.0 * delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	var definition := _combat.heavy_attack if _next_thrust else _combat.light_attack
	if boss_phase == 2 and _next_thrust:
		definition = BOSS_CLEAVE
	var stop_distance := definition.reach - 0.55
	if role == &"thrower" and _visible and distance < 3.1:
		var away := -offset.normalized()
		var retreat := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP,
			global_position + Vector3.UP + away * 1.1, 1)
		if get_world_3d().direct_space_state.intersect_ray(retreat).is_empty():
			return away * (pursuit_speed * 0.72)
	if distance > stop_distance or not _visible:
		if not _has_path or _navigation.target_position.distance_squared_to(player.global_position) > 0.16:
			_navigation.target_position = player.global_position
			_has_path = true
		var step := _navigation.get_next_path_position() - global_position
		step.y = 0.0
		return step.normalized() * pursuit_speed
	_has_path = false
	if _cooldown == 0.0 and absf(angle_difference(_heading.rotation.y, aim)) < 0.25:
		_combat.start_attack(definition)
		_next_thrust = not _next_thrust
	return Vector3.ZERO
