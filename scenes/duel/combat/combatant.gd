extends Node

const AttackData = preload("res://scenes/duel/combat/attack_data.gd")
const ThrownBolt = preload("res://scenes/expedition/enemies/thrown_bolt.gd")

## cue names a sound/feedback event; strength is the impact weight of the blow (0..1).
signal feedback(cue: StringName, location: Vector3, strength: float)
signal defeated
signal weapon_changed(weapon: SoulsWeapon)

const STAMINA_DELAY: float = 0.65
const STAMINA_REGEN: float = 24.0
const BLOCK_FACING: float = 0.5735764 # cos(55°)
const ROLL_DURATION: float = 0.55
## Invulnerable part of the roll. Dark Souls 1 grants 11-13 of 30 frames on medium and fast
## rolls; this shorter roll keeps a similar share of its length.
const ROLL_IFRAMES := Vector2(0.05, 0.33)
const PARRY_DURATION: float = 0.42
const PARRY_STAGGER: float = 0.98
const COMBO_RESET: float = 0.45
const BLADE_SUBSTEPS: int = 4

@export var light_attack: AttackData
@export var heavy_attack: AttackData
## Player weapon. When set, it supplies the light chain and heavy attack and dresses the rig.
@export var weapon: SoulsWeapon
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
## Horizontal shove from the last blow, decays quickly. Body controllers add it to motion.
var push: Vector3
var combo_step: int

var _stamina_wait: float
var _posture_wait: float
var _parried: bool
var _contact_time: float
var _idle_time: float
var _hit_bodies: Array[int] = []
var _swing_volume: SphereShape3D = SphereShape3D.new()
var _blade_previous := PackedVector3Array()

@onready var body: CharacterBody3D = get_parent()
@onready var heading: Node3D = body.get_node("Heading")
@onready var rig: Node3D = body.get_node_or_null("Heading/Rig")


func _ready() -> void:
	health = max_health
	if weapon != null:
		equip(weapon)


func equip(next: SoulsWeapon) -> void:
	weapon = next
	light_attack = weapon.light(0)
	heavy_attack = weapon.heavy
	combo_step = 0
	if rig != null and rig.has_method(&"set_weapon"):
		if rig.is_node_ready():
			rig.set_weapon(weapon)
		else:
			rig.weapon = weapon
	weapon_changed.emit(weapon)


func advance(delta: float) -> void:
	push = push.move_toward(Vector3.ZERO, 14.0 * delta)
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
		_idle_time += delta
		if _idle_time > COMBO_RESET:
			combo_step = 0
		return
	_idle_time = 0.0

	var previous_age := action_age
	action_age += delta
	if attack != null and action_age >= attack.windup and previous_age < attack.windup + attack.active:
		if previous_age < attack.windup:
			_emit(&"heavy" if attack.impact >= 0.6 else &"swing", attack.impact)
			if attack.projectile_speed > 0.0:
				_launch_bolt()
		if attack.projectile_speed <= 0.0:
			_strike()
	elif attack != null and attack.projectile_speed <= 0.0:
		_blade_previous = _blade()
	if action_age >= action_duration:
		_set_action(&"", 0.0)


func start_attack(definition: AttackData) -> bool:
	if definition == null or action != &"" or not _spend(definition.stamina_cost):
		return false
	_set_action(definition.clip, definition.windup + definition.active + definition.recovery)
	attack = definition
	_blade_previous = _blade()
	if opponent_mask == 2:
		_emit(&"windup", definition.impact)
	return true


## Next swing of the weapon's light chain. Pressing again during recovery continues the chain.
func start_light() -> bool:
	var definition := light_attack
	if weapon != null:
		definition = weapon.light(combo_step)
	if start_attack(definition):
		combo_step += 1
		return true
	return false


func start_heavy() -> bool:
	if start_attack(heavy_attack):
		combo_step = 0
		return true
	return false


## True once the current swing has recovered far enough to be cut short by the given action.
func can_cancel_into(next: StringName) -> bool:
	if attack == null or attack.projectile_speed > 0.0 or contact_frozen:
		return false
	var recovery_start := attack.windup + attack.active
	var point := attack.roll_cancel_point if next == &"roll" else attack.chain_point
	return action_age >= recovery_start + attack.recovery * point


func cancel_recovery() -> void:
	_set_action(&"", 0.0)


func start_roll(direction: Vector3) -> bool:
	if action != &"" or not body.is_on_floor() or not _spend(22.0):
		return false
	dodge_direction = direction.normalized()
	combo_step = 0
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
	_emit(&"windup", 0.8)


## Checkpoint respawn: full vitals, no action in progress.
func revive() -> void:
	health = max_health
	stamina = 100.0
	posture = 100.0
	push = Vector3.ZERO
	combo_step = 0
	_contact_time = 0.0
	contact_frozen = false
	_set_action(&"", 0.0)


func is_invulnerable() -> bool:
	return action == &"roll" and action_age >= ROLL_IFRAMES.x and action_age <= ROLL_IFRAMES.y


func receive_attack(attacker: Node, incoming: AttackData, shot_source_direction: Vector3 = Vector3.ZERO) -> bool:
	if action == &"dead" or is_invulnerable():
		return false
	var projectile := shot_source_direction != Vector3.ZERO
	var towards_attacker: Vector3 = shot_source_direction if projectile else attacker.body.global_position - body.global_position
	towards_attacker.y = 0.0
	var away := -towards_attacker.normalized()
	var frontal := -heading.global_basis.z.dot(towards_attacker.normalized()) >= BLOCK_FACING
	_contact_time = incoming.hit_stop()

	if frontal and action == &"parry" and action_age >= 0.035 and action_age <= 0.20:
		if not projectile:
			attacker.interrupt_for_parry()
		_set_action(&"parry", 0.13)
		action_age = 0.05
		_contact_time = 0.075
		_emit(&"parry", 0.8)
		return true
	if frontal and blocking and action == &"":
		var could_hold := stamina > incoming.block_cost
		_spend(minf(stamina, incoming.block_cost))
		_stamina_wait = STAMINA_DELAY
		push = away * incoming.knockback() * 0.55
		if could_hold:
			_emit(&"block", incoming.impact)
		else:
			_damage(incoming.damage * 0.5)
			if action != &"dead":
				_set_action(&"stagger", 0.75)
				_emit(&"guard_break", 1.0)
		return true

	var damage := incoming.damage * (1.5 if _parried else 1.0)
	_parried = false
	_damage(damage)
	push = away * incoming.knockback()
	if action == &"dead":
		_emit(&"death", incoming.impact)
		return true
	_emit(&"hit", incoming.impact)
	posture = maxf(0.0, posture - incoming.posture_damage)
	_posture_wait = 0.90
	if posture <= 0.0:
		posture = 100.0
		_set_action(&"stagger", 0.82)
	elif opponent_mask == 4 and action != &"stagger":
		_set_action(&"stagger", 0.32)
	elif incoming.impact >= 0.85 and action != &"stagger":
		# Full-weight blows flinch even the player out of whatever they were doing.
		_set_action(&"stagger", 0.42)
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
		var carry := weapon.carry_factor() if weapon != null else 1.0
		return (0.38 if blocking else 1.0) * carry
	return 0.0


func _set_action(next: StringName, duration: float) -> void:
	action = next
	action_duration = duration
	action_age = 0.0
	attack = null
	_parried = false
	_hit_bodies.clear()
	_blade_previous = PackedVector3Array()
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


func _emit(cue: StringName, strength: float = 0.5) -> void:
	feedback.emit(cue, body.global_position + Vector3.UP * 1.20, strength)


func _launch_bolt() -> void:
	var bolt := ThrownBolt.new()
	get_tree().current_scene.add_child(bolt)
	var forward := -heading.global_basis.z
	bolt.launch(self, attack, body.global_position + Vector3.UP * 1.23 + forward * 0.54, forward, opponent_mask)


func _blade() -> PackedVector3Array:
	if rig != null and rig.has_method(&"blade_segment"):
		return rig.blade_segment()
	return PackedVector3Array()


## Melee contact comes from the weapon: the striking segment is swept from its previous
## position to its current one and tested against each opponent's capsule.
func _strike() -> void:
	var current := _blade()
	if current.size() != 2:
		_hit_within_reach()
		return
	var previous := _blade_previous if _blade_previous.size() == 2 else current
	_blade_previous = current
	var definition := attack
	var origin := body.global_position + Vector3.UP
	var space := body.get_world_3d().direct_space_state
	_swing_volume.radius = maxf(origin.distance_to(current[1]), origin.distance_to(previous[1])) + 1.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _swing_volume
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = opponent_mask
	for contact in space.intersect_shape(query, 8):
		var other := contact.collider as CharacterBody3D
		if other == null or other == body or _hit_bodies.has(other.get_instance_id()):
			continue
		var capsule := _capsule_of(other)
		if capsule.is_empty():
			continue
		var point: Vector3 = Vector3.INF
		for step in range(1, BLADE_SUBSTEPS + 1):
			var t := float(step) / BLADE_SUBSTEPS
			var base := previous[0].lerp(current[0], t)
			var tip := previous[1].lerp(current[1], t)
			var closest := Geometry3D.get_closest_points_between_segments(base, tip, capsule[0], capsule[1])
			if closest[0].distance_to(closest[1]) <= capsule[2] + (weapon.blade_half_width if weapon else 0.04):
				point = closest[0]
				break
		if point == Vector3.INF:
			continue
		var sight := PhysicsRayQueryParameters3D.create(origin, point, 1)
		if not space.intersect_ray(sight).is_empty():
			continue
		var defender := other.get_node_or_null("Combat")
		if defender == null:
			continue
		if not defender.receive_attack(self, definition):
			continue
		_contact_time = definition.hit_stop()
		if attack != definition:
			return
		_hit_bodies.append(other.get_instance_id())


## [axis start, axis end, radius] of a body's capsule in world space.
func _capsule_of(other: CharacterBody3D) -> Array:
	for child in other.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or not shape_node.shape is CapsuleShape3D:
			continue
		var capsule := shape_node.shape as CapsuleShape3D
		var half := maxf(0.0, capsule.height * 0.5 - capsule.radius)
		var axis := shape_node.global_basis.y.normalized() * half
		var center := shape_node.global_position
		return [center - axis, center + axis, capsule.radius]
	return []


## Fallback for bodies without a dressed weapon: a sector around the body.
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
		_contact_time = definition.hit_stop()
		if attack != definition:
			return
		_hit_bodies.append(other.get_instance_id())
