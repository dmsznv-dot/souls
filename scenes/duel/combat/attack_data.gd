class_name DuelAttack
extends Resource

@export var clip: StringName
@export_range(0.01, 2.0, 0.01, "suffix:s") var windup: float = 0.16
@export_range(0.01, 1.0, 0.01, "suffix:s") var active: float = 0.10
@export_range(0.01, 3.0, 0.01, "suffix:s") var recovery: float = 0.27
@export_range(1.0, 100.0, 1.0) var damage: float = 18.0
@export_range(0.0, 100.0, 1.0) var stamina_cost: float = 15.0
@export_range(1.0, 100.0, 1.0) var block_cost: float = 18.0
@export_range(1.0, 100.0, 1.0) var posture_damage: float = 24.0
@export_range(0.5, 12.0, 0.01, "suffix:m") var reach: float = 2.0
@export_range(5.0, 180.0, 1.0, "degrees") var arc: float = 102.0
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var lunge_speed: float = 1.7
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var projectile_speed: float = 0.0
