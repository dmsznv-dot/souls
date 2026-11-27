extends Node

const AttackData = preload("res://scenes/duel/combat/attack_data.gd")
const ThrownBolt = preload("res://scenes/expedition/enemies/thrown_bolt.gd")

signal feedback(cue: StringName, location: Vector3)
signal defeated

const STAMINA_DELAY: float = 0.65
const STAMINA_REGEN: float = 24.0
const BLOCK_FACING: float = 0.5735764 # cos(55°)
const ROLL_DURATION: float = 0.55
const PARRY_DURATION: float = 0.42
const PARRY_STAGGER: float = 0.98

@export var light_attack: AttackData
@export var heavy_attack: AttackData
@export_flags_3d_physics var opponent_mask: int = 4
@export_range(1.0, 300.0, 1.0) var max_health: float = 100.0

var health: float = 100.0
var stamina: float = 100.0
var posture: float = 100.0
var action: StringName
var action_age: float
var action_duration: float
var attack: AttackData
var blocking: bool
var dodge_direction: Vector3
var contact_frozen: bool

var _stamina_wait: float
var _posture_wait: float
var _parried: bool
var _contact_time: float
var _hit_bodies: Array[int] = []
var _swing_volume: SphereShape3D = SphereShape3D.new()

@onready var body: CharacterBody3D = get_parent()
@onready var heading: Node3D = body.get_node("Heading")


func _ready() -> void:
	health = max_health


func advance(delta: float) -> void:
	contact_frozen = _contact_time > 0.0
	if contact_frozen:
		_contact_time = maxf(0.0, _contact_time - delta)
		return
	if action == &"dead":
		action_age = minf(action_age + delta, action_duration)
		return

	_stamina_wait = maxf(0.0, _stamina_wait - delta)
	if _stamina_wait == 0.0 and not blocking:
		stamina = minf(100.0, stamina + STAMINA_REGEN * delta)
	_posture_wait = maxf(0.0, _posture_wait - delta)
	if _posture_wait == 0.0:
		posture = minf(100.0, posture + 27.0 * delta)
	if action == &"":
		return

	var previous_age := action_age
	action_age += delta
	if attack != null and action_age >= attack.windup and previous_age < attack.windup + attack.active:
		if previous_age < attack.windup:
			_emit(&"heavy" if attack.damage >= 30.0 else &"swing")
			if attack.projectile_speed > 0.0:
				_launch_bolt()
		if attack.projectile_speed <= 0.0:
			_hit_within_reach()
	if action_age >= action_duration:
		_set_action(&"", 0.0)


func start_attack(definition: AttackData) -> bool:
	if definition == null or action != &"" or not _spend(definition.stamina_cost):
		return false
	_set_action(definition.clip, definition.windup + definition.active + definition.recovery)
	attack = definition
	if opponent_mask == 2:
		_emit(&"windup")
	return true


func start_roll(direction: Vector3) -> bool:
	if action != &"" or not body.is_on_floor() or not _spend(22.0):
		return false
	dodge_direction = direction.normalized()
	_set_action(&"roll", ROLL_DURATION)
	_emit(&"roll")
	return true


func start_parry() -> bool:
	if action != &"" or not _spend(12.0):
		return false
	_set_action(&"parry", PARRY_DURATION)
	return true


func start_jump(duration: float) -> bool:
	if action != &"" or not body.is_on_floor() or not _spend(10.0):
		return false
	_set_action(&"jump", duration)
	return true


func start_boss_phase() -> void:
	_set_action(&"boss_phase", 0.9)
	_emit(&"windup")


func receive_attack(attacker: Node, incoming: AttackData, shot_source_direction: Vector3 = Vector3.ZERO) -> bool:
	if action == &"dead" or (action == &"roll" and action_age >= 0.07 and action_age <= 0.25):
		return false
	var projectile := shot_source_direction != Vector3.ZERO
	var towards_attacker: Vector3 = shot_source_direction if projectile else attacker.body.global_position - body.global_position
	towards_attacker.y = 0.0
	var frontal := -heading.global_basis.z.dot(towards_attacker.normalized()) >= BLOCK_FACING
	_contact_time = 0.045 if incoming.damage < 30.0 else 0.065

	if frontal and action == &"parry" and action_age >= 0.035 and action_age <= 0.20:
		if not projectile:
			attacker.interrupt_for_parry()
		_set_action(&"parry", 0.13)
		action_age = 0.05
		_contact_time = 0.075
		_emit(&"parry")
		return true
	if frontal and blocking and action == &"":
		var could_hold := stamina > incoming.block_cost
		_spend(minf(stamina, incoming.block_cost))
		_stamina_wait = STAMINA_DELAY
		if could_hold:
			_emit(&"block")
		else:
			_damage(incoming.damage * 0.5)
			if action != &"dead":
				_set_action(&"stagger", 0.75)
				_emit(&"guard_break")
		return true

	var damage := incoming.damage * (1.5 if _parried else 1.0)
	_parried = false
	_damage(damage)
	if action == &"dead":
		return true
	_emit(&"hit")
	posture = maxf(0.0, posture - incoming.posture_damage)
	_posture_wait = 0.90
	if posture <= 0.0:
		posture = 100.0
		_set_action(&"stagger", 0.82)
	elif opponent_mask == 4 and action != &"stagger":
		_set_action(&"stagger", 0.32)
	return true


func interrupt_for_parry() -> void:
	_set_action(&"stagger", PARRY_STAGGER)
	_parried = true


func clip() -> StringName:
	if action != &"":
		return action
	return &"block" if blocking else &"locomotion"


func pose_phase() -> float:
	if attack == null:
		return clampf(action_age / action_duration, 0.0, 1.0) if action_duration > 0.0 else 1.0
	if action_age < attack.windup:
		return remap(action_age, 0.0, attack.windup, 0.0, 0.44)
	var end_active := attack.windup + attack.active
	if action_age < end_active:
		return remap(action_age, attack.windup, end_active, 0.44, 0.66)
	return remap(action_age, end_active, action_duration, 0.66, 1.0)


func phase_name() -> String:
	if attack == null:
		return String(clip())
	if action_age < attack.windup:
		return "%s · windup" % action
	if action_age < attack.windup + attack.active:
		return "%s · active" % action
	return "%s · recovery" % action


func lunge_speed() -> float:
	if not contact_frozen and attack != null and action_age >= attack.windup and action_age < attack.windup + attack.active:
		var progress := (action_age - attack.windup) / attack.active
		return attack.lunge_speed * sin(PI * progress) * 1.45
	return 0.0


func movement_weight() -> float:
	if contact_frozen:
		return 0.0
	if action == &"jump":
		return 0.72
	if attack != null:
		var recovery_start := attack.windup + attack.active
		return smoothstep(recovery_start + attack.recovery * 0.55, action_duration, action_age)
	if action == &"":
		return 0.38 if blocking else 1.0
	return 0.0


func _set_action(next: StringName, duration: float) -> void:
	action = next
	action_duration = duration
	action_age = 0.0
	attack = null
	_parried = false
	_hit_bodies.clear()
	if next != &"":
		blocking = false


func _spend(cost: float) -> bool:
	if stamina < cost:
		_emit(&"tired")
		return false
	if cost > 0.0:
		stamina -= cost
		_stamina_wait = STAMINA_DELAY
	return true


func _damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health == 0.0:
		_set_action(&"dead", 0.80)
		defeated.emit()


func _emit(cue: StringName) -> void:
	feedback.emit(cue, body.global_position + Vector3.UP * 1.20)


func _launch_bolt() -> void:
	var bolt := ThrownBolt.new()
	get_tree().current_scene.add_child(bolt)
	var forward := -heading.global_basis.z
	bolt.launch(self, attack, body.global_position + Vector3.UP * 1.23 + forward * 0.54, forward, opponent_mask)


func _hit_within_reach() -> void:
	var definition := attack
	var origin := body.global_position + Vector3.UP
	_swing_volume.radius = definition.reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _swing_volume
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = opponent_mask
	var space := body.get_world_3d().direct_space_state

	for contact in space.intersect_shape(query, 8):
		var other := contact.collider as CharacterBody3D
		if other == null or _hit_bodies.has(other.get_instance_id()):
			continue
		var offset := other.global_position - body.global_position
		offset.y = 0.0
		var cosine := cos(deg_to_rad(definition.arc * 0.5))
		if offset.length_squared() > definition.reach * definition.reach:
			continue
		if -heading.global_basis.z.dot(offset.normalized()) < cosine:
			continue
		var sight := PhysicsRayQueryParameters3D.create(origin, other.global_position + Vector3.UP, 1)
		if not space.intersect_ray(sight).is_empty():
			continue
		var defender := other.get_node_or_null("Combat")
		if defender == null:
			continue
		if not defender.receive_attack(self, definition):
			continue
		_contact_time = 0.045 if definition.damage < 30.0 else 0.065
		if attack != definition:
			return
		_hit_bodies.append(other.get_instance_id())
