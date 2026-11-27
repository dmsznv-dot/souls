extends Node3D
## The Outer Ruins as a self-contained area: environment, entrance and its three guards.
## It runs standalone (outer_ruins.tscn) or streamed into the Ash Court behind the seal gate,
## in which case the court supplies sky, light and the player, and the entrance is opened.

signal enemy_defeated(enemy: CharacterBody3D)
signal cleared

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const DISSOLVE := preload("res://scenes/expedition/gate/gate_dissolve.gdshader")
const STONE := preload("res://scenes/expedition/gate/court_stone.tres")
const NoirLighting = preload("res://scenes/fx/noir_lighting.gd")
## Magenta fills along the road and under the shrine (area space).
const ACCENTS := [Vector3(-6.4, 2.2, -5.0), Vector3(6.4, 2.2, -14.5), Vector3(-6.4, 2.2, -23.0), Vector3(0.0, 3.2, -28.0)]
const CAPTIONS := {
	&"spearman": "PALE SPEARMAN",
	&"shield": "ASH SHIELDBEARER",
	&"thrower": "CINDER THROWER",
}
## Half width of the cut through the rear parapet, inside the Kenney entrance arch.
const ENTRANCE_HALF_WIDTH := 1.45

var remaining: int


func setup(player: CharacterBody3D, streamed: bool) -> void:
	for enemy: CharacterBody3D in enemies():
		enemy.player = player
		var combat: Combatant = enemy.get_node("Combat")
		combat.defeated.connect(_on_enemy_defeated.bind(enemy))
	remaining = enemies().size()
	if streamed:
		# The host area owns sky, sun and ambient light.
		$Environment/WorldEnvironment.free()
		$Environment/EveningLight.free()
		open_entrance()
	var accents := []
	for point: Vector3 in ACCENTS:
		accents.append(global_transform * point)
	NoirLighting.apply(self, accents)


func enemies() -> Array[Node]:
	return $Enemies.get_children()


func engaged() -> bool:
	return enemies().any(func(enemy: Node) -> bool: return enemy.is_engaged())


func caption(enemy: Node) -> String:
	return enemy.title if not enemy.title.is_empty() else CAPTIONS.get(enemy.role, "")


func entrance_transform() -> Transform3D:
	return $Entrance.global_transform


func set_backdrop_visible(shown: bool) -> void:
	var hills := get_node_or_null(^"Environment/OriginalRuins/Hinterland") as Node3D
	if hills != null:
		hills.visible = shown


## Cuts a doorway through the rear parapet inside the entrance arch, with jambs and collision.
func open_entrance() -> void:
	var parapet := get_node(^"Environment/OriginalRuins/RearParapet") as MeshInstance3D
	var cut := ShaderMaterial.new()
	cut.shader = DISSOLVE
	cut.set_shader_parameter(&"open_amount", 1.0)
	cut.set_shader_parameter(&"half_width", ENTRANCE_HALF_WIDTH)
	cut.set_shader_parameter(&"spring_height", 9.0)
	cut.set_shader_parameter(&"front_slab", Vector2(7.9, 9.8))
	parapet.set_surface_override_material(0, cut)
	var wall := get_node(^"Environment/Stonework/RearGate") as CollisionShape3D
	wall.disabled = true
	var body := wall.get_parent() as StaticBody3D
	for side in [-1.0, 1.0]:
		var jamb := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var width := 8.1 - ENTRANCE_HALF_WIDTH
		shape.size = Vector3(width, 3.2, 1.9)
		jamb.shape = shape
		body.add_child(jamb)
		jamb.position = Vector3(side * (ENTRANCE_HALF_WIDTH + width * 0.5), 1.6, 8.85)
		var lining := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.3, 3.2, 1.8)
		lining.mesh = mesh
		lining.material_override = STONE
		add_child(lining)
		lining.position = Vector3(side * (ENTRANCE_HALF_WIDTH + 0.15), 1.6, 8.85)


func _on_enemy_defeated(enemy: CharacterBody3D) -> void:
	enemy.ai_enabled = false
	enemy.get_node("LockPoint").hide()
	enemy.set_deferred("collision_layer", 0)
	enemy.set_deferred("collision_mask", 1)
	remaining -= 1
	enemy_defeated.emit(enemy)
	if remaining == 0:
		cleared.emit()
