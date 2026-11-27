extends Node3D
## The Ash Court's seal gate. After the Gatekeeper falls, the door assembly burns away cell by
## cell and opens an archway onto a short stone bridge that meets the Outer Ruins' entrance.
## The bridge, its walls and its collision exist from the start, hidden behind the sealed door.

signal opened

const DISSOLVE := preload("res://scenes/expedition/gate/gate_dissolve.gdshader")
const STONE := preload("res://scenes/expedition/gate/court_stone.tres")
const DOOR_HALF_WIDTH := 2.6
## Bridge span in court space: from the door's inner face to the ruins parapet beyond.
const BRIDGE_Z := Vector2(-11.9, -15.55)

@export var gate_mesh_path: NodePath = ^"../Environment/Court/SealGate"
@export var gate_collision_path: NodePath = ^"../Environment/Masonry/SealGate"

var is_open: bool
var amount: float:
	set(value):
		amount = value
		if _material != null:
			_material.set_shader_parameter(&"open_amount", value)

var _material: ShaderMaterial
var _blocker: CollisionShape3D
var _embers: CPUParticles3D


func _ready() -> void:
	var gate := get_node(gate_mesh_path) as MeshInstance3D
	_material = ShaderMaterial.new()
	_material.shader = DISSOLVE
	_material.set_shader_parameter(&"half_width", DOOR_HALF_WIDTH)
	gate.set_surface_override_material(0, _material)
	_split_collision(get_node(gate_collision_path) as CollisionShape3D)
	_build_bridge()
	_embers = _make_embers()


func open(duration: float = 2.6) -> void:
	if is_open:
		return
	is_open = true
	_embers.emitting = true
	var tween := create_tween()
	tween.tween_property(self, ^"amount", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_callback(func() -> void: _blocker.set_deferred(&"disabled", true)).set_delay(duration * 0.45)
	tween.tween_callback(func() -> void: opened.emit())


## Replaces the wall's single box with two flanks and a door blocker that opening removes.
func _split_collision(original: CollisionShape3D) -> void:
	var box := original.shape as BoxShape3D
	var center := original.position
	original.disabled = true
	var body := original.get_parent() as StaticBody3D
	var flank_width := (box.size.x - DOOR_HALF_WIDTH * 2.0) * 0.5
	for side in [-1.0, 1.0]:
		var flank := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(flank_width, box.size.y, box.size.z)
		flank.shape = shape
		body.add_child(flank)
		flank.position = center + Vector3(side * (DOOR_HALF_WIDTH + flank_width * 0.5), 0, 0)
	_blocker = CollisionShape3D.new()
	var door := BoxShape3D.new()
	door.size = Vector3(DOOR_HALF_WIDTH * 2.0, box.size.y, box.size.z)
	_blocker.shape = door
	_blocker.name = "DoorBlocker"
	body.add_child(_blocker)
	_blocker.position = center


func _build_bridge() -> void:
	var body := StaticBody3D.new()
	body.name = "Bridge"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var length := BRIDGE_Z.x - BRIDGE_Z.y
	var mid_z := (BRIDGE_Z.x + BRIDGE_Z.y) * 0.5
	_slab(body, Vector3(DOOR_HALF_WIDTH * 2.0 + 0.2, 0.4, length + 0.6), Vector3(0, -0.2, mid_z))
	for side in [-1.0, 1.0]:
		# Walls run from inside the gate's thickness to the parapet so nothing opens sideways.
		_slab(body, Vector3(0.5, 4.2, 3.1), Vector3(side * (DOOR_HALF_WIDTH + 0.25), 2.1, -14.0))
	var lamp := OmniLight3D.new()
	lamp.name = "BridgeLamp"
	lamp.light_color = Color(1.0, 0.62, 0.32)
	lamp.light_energy = 1.2
	lamp.omni_range = 5.0
	add_child(lamp)
	lamp.position = Vector3(0, 3.4, -14.6)


func _slab(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	collision.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = STONE
	body.add_child(visual)
	visual.position = at


func _make_embers() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "Embers"
	var cell := BoxMesh.new()
	cell.size = Vector3(0.06, 0.06, 0.06)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.5, 0.18)
	cell.material = glow
	particles.mesh = cell
	particles.amount = 90
	particles.lifetime = 1.6
	particles.emitting = false
	particles.one_shot = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(DOOR_HALF_WIDTH, 2.6, 0.2)
	particles.direction = Vector3.UP
	particles.spread = 35.0
	particles.gravity = Vector3(0, 0.6, 0)
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 1.8
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	add_child(particles)
	particles.position = Vector3(0, 2.8, -12.1)
	opened.connect(func() -> void: particles.emitting = false)
	return particles
