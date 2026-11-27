extends Node

const AttackData = preload("res://scenes/duel/combat/attack_data.gd")

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

var health: float = 100.0
var stamina: float = 100.0
var posture: float = 100.0
var action: StringName
var action_age: float
var action_duration: float
var attack: AttackData
var blocking: bool
var dodge_direction: Vector3

var _stamina_wait: float
var _posture_wait: float
var _parried: bool
var _hit_bodies: Array[int] = []
var _swing_volume: SphereShape3D = SphereShape3D.new()

@onready var body: CharacterBody3D = get_parent()
@onready var heading: Node3D = body.get_node("Heading")


func advance(delta: float) -> void:
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


func receive_attack(attacker: Node, incoming: AttackData) -> void:
	if action == &"dead" or (action == &"roll" and action_age >= 0.07 and action_age <= 0.25):
		return
	var towards_attacker: Vector3 = attacker.body.global_position - body.global_position
	towards_attacker.y = 0.0
	var frontal := -heading.global_basis.z.dot(towards_attacker.normalized()) >= BLOCK_FACING

	if frontal and action == &"parry" and action_age >= 0.035 and action_age <= 0.20:
		attacker.interrupt_for_parry()
		_set_action(&"parry", 0.13)
		action_age = 0.05
		_emit(&"parry")
		return
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
		return

	var damage := incoming.damage * (1.5 if _parried else 1.0)
	_parried = false
	_damage(damage)
	if action == &"dead":
		return
	_emit(&"hit")
	posture = maxf(0.0, posture - incoming.posture_damage)
	_posture_wait = 0.90
	if posture <= 0.0:
		posture = 100.0
		_set_action(&"stagger", 0.82)
	elif opponent_mask == 4 and action != &"stagger":
		_set_action(&"stagger", 0.32)


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
	if attack != null and action_age >= attack.windup and action_age < attack.windup + attack.active:
		return attack.lunge_speed
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
		_hit_bodies.append(other.get_instance_id())
		defender.receive_attack(self, definition)
		if attack != definition:
			return
