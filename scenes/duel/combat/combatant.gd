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
## Medium-load roll: 39 ticks with i-frames on ticks [5, 21). Light and heavy loads pass their
## own profile to start_roll (see player.gd LOAD_CLASSES).
const ROLL_DURATION: float = 39.0 / 60.0
const ROLL_IFRAMES := Vector2(5.0 / 60.0, 21.0 / 60.0)
const ROLL_COST: float = 22.0
## Parry: startup [0,4), active [4,11), recovery to 28 ticks. A success recovers in 10 ticks.
const PARRY_DURATION: float = 28.0 / 60.0
const PARRY_WINDOW := Vector2(4.0 / 60.0, 11.0 / 60.0)
const PARRY_SUCCESS_RECOVERY: float = 10.0 / 60.0
## Raising a guard takes 4 ticks before it blocks.
const BLOCK_STARTUP: float = 4.0 / 60.0
## Hit-stop by outcome, in ticks: blocks 2, parries 4 (hits take theirs from the attack).
const BLOCK_HITSTOP: float = 2.0 / 60.0
const PARRY_HITSTOP: float = 4.0 / 60.0
## Flinch and stagger lengths of an ordinary poise break: 12 ticks, 22 from heavy blows.
const FLINCH_TIME: float = 12.0 / 60.0
const HEAVY_FLINCH_TIME: float = 22.0 / 60.0
const PARRY_STAGGER: float = 0.98
const COMBO_RESET: float = 0.45
const FOCUS_REGEN: float = 6.0
## Damage taken per damage type (slash, pierce, impact, magic) for each armour class.
const RESISTANCE := {
	&"plate": [0.8, 1.0, 1.3, 1.1], &"cloth": [1.2, 1.0, 0.9, 1.0],
	&"hide": [0.9, 1.15, 0.8, 1.2], &"bone": [0.9, 0.8, 1.25, 1.0],
}
const BLADE_SUBSTEPS: int = 6
## Poise damage fades if no blow lands for this long (Dark Souls resets poise after a pause).
const POISE_RESET: float = 1.6
## Poise damage of a blow of impact 1.0.
const POISE_PER_IMPACT: float = 50.0
## Posture broken: the foe reels, defenceless, and the next blow lands as a critical.
const DAZE_DURATION: float = 1.9
const DAZE_CRITICAL: float = 1.6
const KNOCKDOWN_DURATION: float = 1.75
## Knocked down bodies lie still between these fractions of the knockdown; the player cannot be
## hit again while down, so heavies cannot chain a fallen hero to death.
const KNOCKDOWN_LYING := Vector2(0.28, 0.72)
## Running stamina dry stops regeneration 90 ticks, then it returns at 16/s until 35.
const EXHAUSTED_DELAY: float = 1.5
const EXHAUSTED_REGEN: float = 16.0
## Regeneration while a raised guard is held, as a share of the normal rate.
const BLOCK_REGEN_SHARE: float = 0.25
## Damage and poise multipliers for blows from the flank and from behind, for every weapon.
const FLANK_BONUS := Vector2(1.08, 1.25)
const REAR_BONUS := Vector2(1.2, 1.5)

@export var light_attack: AttackData
@export var heavy_attack: AttackData
## Player weapon. When set, it supplies the light chain and heavy attack and dresses the rig.
@export var weapon: SoulsWeapon
@export_flags_3d_physics var opponent_mask: int = 4
@export_range(1.0, 300.0, 1.0) var max_health: float = 100.0
## Armour class for damage-type resistances; empty takes every type at full damage.
@export var armor: StringName = &""
## Multiplies flinch length. Brutes shrug hits off (below 1), small creatures reel longer.
@export_range(0.0, 4.0, 0.05) var flinch_scale: float = 1.0
## Poise: poise damage soaked before a blow makes the body flinch. 0 derives it from
## flinch_scale (28 for an ordinary body, about 11 for husks, 70 for brutes).
@export_range(0.0, 400.0, 1.0) var poise: float = 0.0
## Steady bodies (bosses) are never knocked off their feet.
@export var steady: bool = false

var health: float = 100.0
var stamina: float = 100.0
var posture: float = 100.0
var action: StringName
var action_age: float
var action_duration: float
var attack: AttackData
var blocking: bool
var dodge_direction: Vector3
## Roll profile of the roll in progress, fixed when it starts.
var roll_duration: float = ROLL_DURATION
var roll_iframes: Vector2 = ROLL_IFRAMES
var roll_distance: float = 2.95
## Seconds the block button has been held in a free state; the guard is up after BLOCK_STARTUP.
var guard_raise: float
## Increments on every new action: lets observers react once per attack.
var action_serial: int
var contact_frozen: bool
## Horizontal shove from the last blow, decays quickly. Body controllers add it to motion.
var push: Vector3
var combo_step: int
var focus: float = 100.0
## Set by the controller while the attack button is held: charges attacks that allow it.
var charging: bool
## Charge gathered by the current attack, 0..attack.charge_time.
var charge: float
## Where projectiles aim. The player's lock target; enemies aim at their quarry.
var aim_target: Node3D
var _held: float
var _poise_damage: float
var _poise_wait: float
## True after stamina ran dry, until it has recovered a third of the bar.
var exhausted: bool
var _focus_wait: float

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

	guard_raise = guard_raise + delta if blocking and action == &"" else 0.0
	_stamina_wait = maxf(0.0, _stamina_wait - delta)
	if _stamina_wait == 0.0:
		var rate := EXHAUSTED_REGEN if exhausted else STAMINA_REGEN
		if blocking:
			rate *= BLOCK_REGEN_SHARE
		stamina = minf(100.0, stamina + rate * delta)
		if exhausted and stamina >= 35.0:
			exhausted = false
	_poise_wait = maxf(0.0, _poise_wait - delta)
	if _poise_wait == 0.0:
		_poise_damage = 0.0
	_posture_wait = maxf(0.0, _posture_wait - delta)
	if _posture_wait == 0.0:
		posture = minf(100.0, posture + 27.0 * delta)
	_focus_wait = maxf(0.0, _focus_wait - delta)
	if _focus_wait == 0.0:
		focus = minf(100.0, focus + FOCUS_REGEN * delta)
	if action == &"":
		_idle_time += delta
		if _idle_time > COMBO_RESET:
			combo_step = 0
		return
	_idle_time = 0.0

	var previous_age := action_age
	if not _holding(delta):
		action_age += delta
	if attack != null and action_age >= attack.windup and previous_age < attack.windup + attack.active:
		if previous_age < attack.windup:
			if attack.damage_type == AttackData.DamageType.MAGIC:
				_emit(&"cast", attack.impact)
			else:
				_emit(&"heavy" if attack.impact >= 0.6 else &"swing", attack.impact)
			if attack.projectile_speed > 0.0:
				_launch_bolt()
		if attack.projectile_speed <= 0.0:
			_strike()
		# The ground is struck as the swing bottoms out, at the end of the active window.
		if attack != null and attack.shockwave_radius > 0.0 and action_age >= attack.windup + attack.active:
			_shockwave()
	elif attack != null and attack.projectile_speed <= 0.0:
		_blade_previous = _blade()
	if action_age >= action_duration:
		_set_action(&"", 0.0)


func start_attack(definition: AttackData) -> bool:
	if definition == null or action != &"":
		return false
	if focus < definition.focus_cost:
		_emit(&"no_focus")
		return false
	if not _spend(definition.stamina_cost):
		return false
	if definition.focus_cost > 0.0:
		focus -= definition.focus_cost
		_focus_wait = 1.0
	_set_action(definition.clip, definition.windup + definition.active + definition.recovery)
	attack = definition
	_blade_previous = _blade()
	if opponent_mask == 2:
		_emit(&"windup", definition.impact)
	return true


## Next swing of the weapon's light chain. Pressing again during recovery continues the chain.
func start_light() -> bool:
	if weapon != null and combo_step >= weapon.light_chain.size():
		# After the last link the chain starts over from its first blow.
		combo_step = 0
	var definition := next_light()
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
## Windup and active never cancel. In recovery a roll may cut in at the roll point; the next
## light only continues a multi-link chain, and the last link returns to idle first. Heavy,
## parry, jump and weapon changes wait for idle.
func can_cancel_into(next: StringName) -> bool:
	if attack == null or attack.projectile_speed > 0.0 or contact_frozen:
		return false
	var recovery_start := attack.windup + attack.active
	if next == &"roll":
		return action_age >= recovery_start + attack.recovery * attack.roll_cancel_point
	if next == &"light_attack":
		if weapon == null or weapon.light_chain.size() < 2 or combo_step >= weapon.light_chain.size():
			return false
		if attack.chain_point >= 1.0:
			return false
		return action_age >= recovery_start + attack.recovery * attack.chain_point
	return false


## The light attack the next press would start (the chain link, or the focus-free fallback).
func next_light() -> AttackData:
	if weapon == null:
		return light_attack
	var step := combo_step if combo_step < weapon.light_chain.size() else 0
	var definition := weapon.light(step)
	if definition != null and focus < definition.focus_cost and weapon.fallback_light != null:
		definition = weapon.fallback_light
	return definition


## Says why a press was refused (tired, no focus) without spending anything.
func emit_refusal(command: StringName) -> void:
	if command == &"light_attack" or command == &"heavy_attack":
		var definition := next_light() if command == &"light_attack" else heavy_attack
		if definition != null and focus < definition.focus_cost:
			_emit(&"no_focus")
			return
	_emit(&"tired")


func cancel_recovery() -> void:
	_set_action(&"", 0.0)


## profile: [duration, i-frames Vector2, free distance, stamina cost]; defaults are medium load.
func start_roll(direction: Vector3, profile: Array = []) -> bool:
	var cost: float = profile[3] if profile.size() == 4 else ROLL_COST
	if action != &"" or not body.is_on_floor() or not _spend(cost):
		return false
	dodge_direction = direction.normalized()
	combo_step = 0
	roll_duration = profile[0] if profile.size() == 4 else ROLL_DURATION
	roll_iframes = profile[1] if profile.size() == 4 else ROLL_IFRAMES
	roll_distance = profile[2] if profile.size() == 4 else 2.95
	_set_action(&"roll", roll_duration)
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


## Stands winded after a string of blows: open to the player's answer.
func start_rest(duration: float) -> void:
	if action == &"":
		_set_action(&"winded", duration)


func start_boss_phase() -> void:
	_set_action(&"boss_phase", 0.9)
	_emit(&"windup", 0.8)


## Checkpoint respawn: full vitals, no action in progress.
func revive() -> void:
	health = max_health
	focus = 100.0
	stamina = 100.0
	posture = 100.0
	push = Vector3.ZERO
	combo_step = 0
	exhausted = false
	_poise_damage = 0.0
	_contact_time = 0.0
	contact_frozen = false
	_set_action(&"", 0.0)


## Damage multiplier of the current attack from charge.
func power() -> float:
	if attack == null or attack.charge_time <= 0.0:
		return 1.0
	return 1.0 + attack.charge_bonus * charge / attack.charge_time


## Holds the pose near the top of the windup: a boss's delayed strike, or a charged swing.
func _holding(delta: float) -> bool:
	if attack == null or action_age < attack.windup * 0.82 or action_age >= attack.windup:
		return false
	if attack.delay > 0.0 and _held < attack.delay:
		_held += delta
		return true
	if attack.charge_time > 0.0 and charging and charge < attack.charge_time:
		charge = minf(attack.charge_time, charge + delta)
		if charge >= attack.charge_time:
			_emit(&"charged", 1.0)
		return true
	return false


## Hyper armour: the windup and strike of a swing whose attack grants it.
func hyper_armor() -> bool:
	return (attack != null and attack.hyper_armor and action_age >= attack.windup * attack.hyper_armor_start
			and action_age < attack.windup + attack.active)


func is_invulnerable() -> bool:
	if action == &"knockdown" and opponent_mask == 4:
		var lying := action_age / KNOCKDOWN_DURATION
		return lying >= KNOCKDOWN_LYING.x and lying <= KNOCKDOWN_LYING.y
	# Leaving the ground closes a ground roll's protection.
	# Half-tick tolerance: ages accumulate in doubles, the window is stored in single floats.
	return (action == &"roll" and action_age + 0.004 >= roll_iframes.x and action_age + 0.004 < roll_iframes.y
			and body.is_on_floor())


## Poise damage this body soaks before a blow staggers it.
func poise_limit() -> float:
	return poise if poise > 0.0 else 28.0 / maxf(flinch_scale, 0.1)


## Defenceless states: a dazed or fallen body cannot block, roll or strike back.
func is_reeling() -> bool:
	return action in [&"dazed", &"knockdown", &"stagger"]


func receive_attack(attacker: Node, incoming: AttackData, shot_source_direction: Vector3 = Vector3.ZERO, power_scale: float = 1.0, poise_scale: float = 1.0) -> bool:
	if action == &"dead" or is_invulnerable():
		return false
	var projectile := shot_source_direction != Vector3.ZERO
	var towards_attacker: Vector3 = shot_source_direction if projectile else attacker.body.global_position - body.global_position
	towards_attacker.y = 0.0
	var away := -towards_attacker.normalized()
	var frontal := -heading.global_basis.z.dot(towards_attacker.normalized()) >= BLOCK_FACING
	_contact_time = incoming.hit_stop()

	if frontal and not projectile and action == &"parry" and action_age + 0.004 >= PARRY_WINDOW.x and action_age + 0.004 < PARRY_WINDOW.y:
		attacker.interrupt_for_parry()
		_set_action(&"parry", PARRY_SUCCESS_RECOVERY)
		_contact_time = PARRY_HITSTOP
		_emit(&"parry", 0.8)
		return true
	if frontal and guarding():
		_contact_time = BLOCK_HITSTOP
		var could_hold := stamina > incoming.block_cost
		_spend(minf(stamina, incoming.block_cost))
		_stamina_wait = maxf(_stamina_wait, STAMINA_DELAY)
		push = away * incoming.knockback() * 0.55
		if could_hold:
			_emit(&"block", incoming.impact)
		else:
			_damage(incoming.damage * 0.5)
			if action != &"dead":
				_set_action(&"stagger", 0.75)
				_emit(&"guard_break", 1.0)
		return true

	var resist: Array = RESISTANCE.get(armor, [1.0, 1.0, 1.0, 1.0])
	var critical := _parried or action == &"dazed"
	var multiplier := 1.5 if _parried else (DAZE_CRITICAL if action == &"dazed" else 1.0)
	if action == &"knockdown":
		multiplier = 1.2
	var damage: float = incoming.damage * power_scale * resist[incoming.damage_type] * multiplier
	_parried = false
	var was := action
	_damage(damage)
	push = away * incoming.knockback()
	_impact_effect(incoming, power_scale * poise_scale)
	if action == &"dead":
		_emit(&"death", incoming.impact)
		return true
	_emit(&"hit", incoming.impact)
	if critical and was == &"dazed":
		_emit(&"critical", 1.0)
	var force := incoming.impact * power_scale * poise_scale
	posture = maxf(0.0, posture - incoming.posture_damage * power_scale * poise_scale)
	_posture_wait = 0.90
	_poise_damage += force * POISE_PER_IMPACT * (0.4 if hyper_armor() else 1.0)
	_poise_wait = POISE_RESET
	var player := opponent_mask == 4
	if was == &"knockdown":
		# A fallen body stays down; blows only add to the damage.
		return true
	if posture <= 0.0 and not player and not steady and force >= 0.75:
		# A heavy blow that breaks posture bowls the body over outright.
		posture = 100.0
		_knock_down(away, incoming)
	elif posture <= 0.0 and not player:
		# Posture broken: the foe reels, open to a critical blow.
		posture = 100.0
		_poise_damage = 0.0
		_set_action(&"dazed", DAZE_DURATION)
		_emit(&"posture_break", 1.0)
	elif posture <= 0.0:
		posture = 100.0
		_set_action(&"stagger", 0.82)
	elif not steady and not hyper_armor() and force >= (0.9 if player else 0.75) and (player or _poise_damage >= poise_limit()):
		_knock_down(away, incoming)
	elif hyper_armor() and _poise_damage < poise_limit() * 2.0:
		# Committed heavy swings ride through blows, as in Souls games, unless battered hard.
		pass
	elif was == &"dazed" or (was != &"stagger" and _poise_damage >= poise_limit()):
		# Hero and foes alike flinch once the blows outweigh their poise (hero: 28).
		_poise_damage = 0.0
		_set_action(&"flinch", HEAVY_FLINCH_TIME if incoming.impact >= 0.65 else FLINCH_TIME)
	return true


func _knock_down(away: Vector3, incoming: AttackData) -> void:
	_poise_damage = 0.0
	_set_action(&"knockdown", KNOCKDOWN_DURATION)
	push = away * incoming.knockback() * 1.1
	_emit(&"knockdown", incoming.impact)


## Sparks off plate and bone, dark spatter off flesh and hide, sized by the blow.
func _impact_effect(incoming: AttackData, weight: float) -> void:
	var fx := get_node_or_null(^"/root/RetroFX")
	var where := body.global_position + Vector3.UP * 1.15
	var strength := clampf(incoming.impact * weight, 0.0, 1.4)
	var material := impact_material()
	_emit(StringName("impact_" + material), strength)
	if fx == null:
		return
	match material:
		&"plate":
			fx.sparks(where, Color(1.0, 0.82, 0.48), roundi(lerpf(8, 22, strength)))
		&"bone":
			fx.sparks(where, Color(0.86, 0.82, 0.7), roundi(lerpf(6, 16, strength)))
		_:
			fx.sparks(where, Color(0.42, 0.05, 0.06), roundi(lerpf(6, 18, strength)))


## Sound and spatter family of this body's armour.
func impact_material() -> String:
	match armor:
		&"plate": return "plate"
		&"bone": return "bone"
		&"hide": return "hide"
	return "flesh"


## A raised guard: held in a free state for the 4-tick startup.
func guarding() -> bool:
	return blocking and action == &"" and guard_raise >= BLOCK_STARTUP


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
		# Guarding walks at 0.55; the overall load class scales ground speed in the controller.
		return 0.55 if blocking else 1.0
	return 0.0


func _set_action(next: StringName, duration: float) -> void:
	action = next
	action_duration = duration
	action_age = 0.0
	action_serial += 1
	attack = null
	_parried = false
	_hit_bodies.clear()
	_blade_previous = PackedVector3Array()
	_held = 0.0
	charge = 0.0
	if next != &"":
		blocking = false


## Actions need their full cost up front; landing on exactly zero is allowed and exhausts.
func _spend(cost: float) -> bool:
	if not can_afford(cost):
		_emit(&"tired")
		return false
	if cost > 0.0:
		stamina = maxf(0.0, stamina - cost)
		_stamina_wait = STAMINA_DELAY
		_check_exhausted()
	return true


func can_afford(cost: float) -> bool:
	return stamina + 0.0001 >= cost


## Drains stamina outside an action (sprinting): no regeneration this tick or for the usual pause.
func drain(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_wait = maxf(_stamina_wait, STAMINA_DELAY)
	_check_exhausted()


## Running dry costs more than one short pause: regeneration stalls, then crawls.
func _check_exhausted() -> void:
	if stamina <= 0.0001 and not exhausted:
		stamina = 0.0
		exhausted = true
		_stamina_wait = EXHAUSTED_DELAY
		_emit(&"exhausted")


func _damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health == 0.0:
		_set_action(&"dead", 1.4)
		defeated.emit()


func _emit(cue: StringName, strength: float = 0.5) -> void:
	var perf := get_node_or_null(^"/root/Perf")
	if perf != null:
		perf.mark(cue)
	feedback.emit(cue, body.global_position + Vector3.UP * 1.20, strength)


func _launch_bolt() -> void:
	var forward := -heading.global_basis.z
	var origin := body.global_position + Vector3.UP * 1.23 + forward * 0.54
	if is_instance_valid(aim_target):
		var to_target := aim_target.global_position - origin
		if to_target.normalized().dot(forward) > 0.5:
			forward = to_target.normalized()
	var count := attack.projectile_count
	for i in count:
		var angle := 0.0 if count == 1 else deg_to_rad(lerpf(-attack.projectile_spread, attack.projectile_spread, float(i) / (count - 1)))
		var bolt := ThrownBolt.new()
		get_tree().current_scene.add_child(bolt)
		bolt.launch(self, attack, origin, forward.rotated(Vector3.UP, angle), opponent_mask)


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
		var scale := power()
		var bonus := _position_bonus(other)
		if definition.backstab_multiplier > 1.0 and _is_behind(other):
			scale *= definition.backstab_multiplier
			_emit(&"critical", 1.0)
		else:
			scale *= bonus.x
		if not defender.receive_attack(self, definition, Vector3.ZERO, scale, bonus.y):
			continue
		_contact_time = definition.hit_stop()
		if attack != definition:
			return
		_hit_bodies.append(other.get_instance_id())


## [damage, poise] multipliers for where the blow lands: the flank, the back, or the front.
func _position_bonus(other: Node3D) -> Vector2:
	var other_heading := other.get_node_or_null("Heading") as Node3D
	if other_heading == null:
		return Vector2.ONE
	var to_attacker := body.global_position - other.global_position
	to_attacker.y = 0.0
	var facing := -other_heading.global_basis.z.dot(to_attacker.normalized())
	if facing < -0.5:
		return REAR_BONUS
	if facing < 0.35:
		return FLANK_BONUS
	return Vector2.ONE


func _is_behind(other: Node3D) -> bool:
	var other_heading := other.get_node_or_null("Heading") as Node3D
	if other_heading == null:
		return false
	var to_attacker := body.global_position - other.global_position
	to_attacker.y = 0.0
	return -other_heading.global_basis.z.dot(to_attacker.normalized()) < -0.5


## Area blow: everything of the opponent layers within the radius, if not behind a wall.
func _shockwave() -> void:
	var definition := attack
	var forward := -heading.global_basis.z
	var center := body.global_position + forward * definition.shockwave_offset
	feedback.emit(&"shockwave" if definition.damage_type != AttackData.DamageType.MAGIC else &"nova",
			center, definition.impact)
	var shape := SphereShape3D.new()
	shape.radius = definition.shockwave_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP * 0.6)
	query.collision_mask = opponent_mask
	var space := body.get_world_3d().direct_space_state
	for contact in space.intersect_shape(query, 12):
		var other := contact.collider as CharacterBody3D
		if other == null or other == body or _hit_bodies.has(other.get_instance_id()):
			continue
		var sight := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.6, other.global_position + Vector3.UP, 1)
		if not space.intersect_ray(sight).is_empty():
			continue
		var defender := other.get_node_or_null("Combat")
		if defender != null and defender.receive_attack(self, definition, Vector3.ZERO, power() * 0.85):
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
