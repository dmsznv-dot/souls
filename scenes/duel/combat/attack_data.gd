class_name DuelAttack
extends Resource

enum DamageType { SLASH, PIERCE, IMPACT, MAGIC }

@export var clip: StringName
@export_range(0.01, 2.0, 0.01, "suffix:s") var windup: float = 0.16
@export_range(0.01, 1.0, 0.01, "suffix:s") var active: float = 0.10
@export_range(0.01, 3.0, 0.01, "suffix:s") var recovery: float = 0.27
@export_range(1.0, 100.0, 1.0) var damage: float = 18.0
@export_range(0.0, 100.0, 1.0) var stamina_cost: float = 15.0
@export_range(1.0, 100.0, 1.0) var block_cost: float = 18.0
@export_range(1.0, 100.0, 1.0) var posture_damage: float = 24.0
## Engagement distance for AI and the F2 debug arc. Melee hits come from the blade sweep.
@export_range(0.5, 12.0, 0.01, "suffix:m") var reach: float = 2.0
@export_range(5.0, 180.0, 1.0, "degrees") var arc: float = 102.0
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var lunge_speed: float = 1.7
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var projectile_speed: float = 0.0
## 0 = a flick, 1 = a full-weight blow. Scales hit-stop, knockback, camera trauma and sound.
@export_range(0.0, 1.0, 0.01) var impact: float = 0.4
## Fraction of recovery after which the next chained attack may start.
@export_range(0.0, 1.0, 0.01) var chain_point: float = 0.3
## Fraction of recovery after which a roll may cancel the rest of the swing.
@export_range(0.0, 1.0, 0.01) var roll_cancel_point: float = 0.55
## Light blows landing during windup and strike do not interrupt this attack.
@export var hyper_armor: bool = false
@export var damage_type: DamageType = DamageType.SLASH
## Focus (magic meter) spent to start the attack.
@export_range(0.0, 100.0, 1.0) var focus_cost: float = 0.0

@export_group("Specials")
## Area blow when the strike lands: everything within this radius is hit (0 = none).
@export_range(0.0, 8.0, 0.1, "suffix:m") var shockwave_radius: float = 0.0
## Centre of the area blow ahead of the body; 0 centres it on the attacker (a nova).
@export_range(0.0, 4.0, 0.1, "suffix:m") var shockwave_offset: float = 1.3
## Extra windup the attack can be held for while the button stays down.
@export_range(0.0, 2.0, 0.05, "suffix:s") var charge_time: float = 0.0
## Damage and posture bonus at full charge (0.6 = +60 %).
@export_range(0.0, 2.0, 0.05) var charge_bonus: float = 0.6
## Damage multiplier for hits landing on a foe's back.
@export_range(1.0, 4.0, 0.1) var backstab_multiplier: float = 1.0
## Pose held at the top of the windup before the strike falls: a feint that baits early rolls.
@export_range(0.0, 2.0, 0.05, "suffix:s") var delay: float = 0.0
## The body turns a full circle during the active window.
@export var spin: bool = false
## Horizontal distance closed in a leap during the end of the windup.
@export_range(0.0, 12.0, 0.1, "suffix:m") var leap: float = 0.0
@export_range(1, 7) var projectile_count: int = 1
@export_range(0.0, 90.0, 1.0, "degrees") var projectile_spread: float = 0.0


func hit_stop() -> float:
	return lerpf(0.04, 0.12, impact)


func knockback() -> float:
	return lerpf(0.7, 3.4, impact)
