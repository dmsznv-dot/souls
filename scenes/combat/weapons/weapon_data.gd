class_name SoulsWeapon
extends Resource
## A held weapon: its geometry decides where it strikes, its mass decides how it feels.
## Attack timing, damage and stamina live in the DuelAttack resources it references.

enum Form { SHORTSWORD, LONGSWORD, GREATSWORD, SPEAR, JAVELIN, DAGGER, KATANA, HAMMER, STAFF, CLAW }

@export var display_name: String = "Longsword"
@export var form: Form = Form.LONGSWORD
## Length from the crossguard (or spear socket) to the point.
@export_range(0.2, 2.5, 0.01, "suffix:m") var blade_length: float = 0.9
@export_range(0.08, 0.6, 0.01, "suffix:m") var grip_length: float = 0.19
@export_range(0.01, 0.12, 0.001, "suffix:m") var blade_half_width: float = 0.034
## Share of the blade, measured from the guard, that cannot cut. Spears strike only at the head.
@export_range(0.0, 0.95, 0.01) var dead_length: float = 0.12
@export_range(0.3, 20.0, 0.1, "suffix:kg") var mass: float = 3.0
@export var two_handed: bool = false
@export var light_chain: Array[DuelAttack] = []
@export var heavy: DuelAttack
@export var trail_color: Color = Color(0.92, 0.88, 0.8, 0.55)
## Light attack used when the chain's first attack cannot be paid for (a staff without focus).
@export var fallback_light: DuelAttack
## One line shown when the weapon is drawn: what makes it different.
@export_multiline var hint: String = ""


func light(index: int) -> DuelAttack:
	if light_chain.is_empty():
		return null
	return light_chain[index % light_chain.size()]
