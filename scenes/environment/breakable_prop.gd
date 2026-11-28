extends Node3D
## A prop the hero's blade can break: a crate, a barrel or a rotten grate over a side niche.
##
## Intact, a static body blocks the way and an Area3D on the Breakable layer receives blows.
## The player's swing sweep (combatant.gd) hits it through receive_hit(): one count per swing
## however many sub-steps touch it. Breaking is atomic: the prop stops taking hits at once,
## hides the whole mesh, drops its collision after the physics step and throws a few light
## fragments that touch only the world and vanish after about two seconds (at most 24 in the
## scene). Crates and barrels come back when the player rests or rises; an opened grate stays
## open for the rest of the expedition. Not a foe: no lock-on, no Combatant.

signal broken(prop: Node3D)

const LAYER := 8 # physics layer 4, "Breakable"
const MAX_FRAGMENTS := 24
const KINDS := {
	# [size, light blows, heavy blows, fragment count, fragment size, keep open after reset]
	&"crate": [Vector3(0.62, 0.62, 0.62), 1, 1, 4, Vector3(0.5, 0.08, 0.09), false],
	&"barrel": [Vector3(0.6, 0.86, 0.6), 2, 1, 5, Vector3(0.12, 0.62, 0.06), false],
	&"grate": [Vector3(1.6, 1.5, 0.14), 3, 1, 5, Vector3(0.1, 1.2, 0.05), true],
}

static var _live_fragments := 0

@export var kind: StringName = &"crate"
## Stable id: area/anchor/prop.
@export var prop_id: String = ""

var is_broken := false
var _blows := 0.0
var _last_swing := -1
var _last_swing_owner := 0
var _intact: Node3D
var _body: StaticBody3D
var _area: Area3D
var _voice: AudioStreamPlayer3D
var _wood: StandardMaterial3D
var _dark: StandardMaterial3D
var _iron: StandardMaterial3D


func _ready() -> void:
	_wood = _material(Color(0.25, 0.19, 0.15))
	_dark = _material(Color(0.17, 0.14, 0.12))
	_iron = _material(Color(0.2, 0.21, 0.22), 0.5)
	var spec: Array = KINDS[kind]
	var size: Vector3 = spec[0]
	_intact = Node3D.new()
	_intact.name = "Intact"
	add_child(_intact)
	match kind:
		&"crate": _build_crate(size)
		&"barrel": _build_barrel(size)
		&"grate": _build_grate(size)
	_body = StaticBody3D.new()
	_body.name = "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_area = Area3D.new()
	_area.name = "Hurt"
	_area.collision_layer = LAYER
	_area.collision_mask = 0
	_area.monitoring = false
	_area.set_meta(&"breakable", self)
	add_child(_area)
	for holder in [_body, _area]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		holder.add_child(shape)
		shape.position = Vector3(0, size.y * 0.5, 0)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = &"SFX"
	_voice.unit_size = 6.0
	_voice.max_distance = 30.0
	add_child(_voice)


func _material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.85
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return material


func _box(size: Vector3, at: Vector3, material: Material, degrees := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	_intact.add_child(part)
	part.position = at
	part.rotation_degrees = degrees


func _build_crate(size: Vector3) -> void:
	_box(size, Vector3(0, size.y * 0.5, 0), _wood)
	for k in 2:
		var z := (k - 0.5) * size.z * 0.98
		_box(Vector3(size.x * 1.02, 0.07, 0.04), Vector3(0, size.y * 0.5, z), _dark, Vector3(0, 0, 40))
		_box(Vector3(size.x * 1.02, 0.06, 0.04), Vector3(0, size.y * 0.92, z), _dark)


func _build_barrel(size: Vector3) -> void:
	var staves := CylinderMesh.new()
	staves.top_radius = size.x * 0.44
	staves.bottom_radius = size.x * 0.44
	staves.height = size.y
	staves.radial_segments = 10
	var body := MeshInstance3D.new()
	body.mesh = staves
	body.material_override = _wood
	_intact.add_child(body)
	body.position = Vector3(0, size.y * 0.5, 0)
	for y in [0.18, 0.82]:
		var hoop := CylinderMesh.new()
		hoop.top_radius = size.x * 0.47
		hoop.bottom_radius = size.x * 0.47
		hoop.height = 0.05
		hoop.radial_segments = 10
		var ring := MeshInstance3D.new()
		ring.mesh = hoop
		ring.material_override = _iron
		_intact.add_child(ring)
		ring.position = Vector3(0, size.y * y, 0)


## Grate: a frame of rotten boards across an opening, a cross brace nailed over them.
func _build_grate(size: Vector3) -> void:
	for k in 5:
		var x := -size.x * 0.5 + size.x * (k + 0.5) / 5.0
		_box(Vector3(0.12, size.y, 0.06), Vector3(x, size.y * 0.5, 0), _wood if k % 2 == 0 else _dark, Vector3(0, 0, (k - 2) * 2.0))
	_box(Vector3(size.x * 1.15, 0.1, 0.07), Vector3(0, size.y * 0.5, 0.05), _dark, Vector3(0, 0, 32))
	_box(Vector3(size.x, 0.08, 0.08), Vector3(0, size.y * 0.85, 0.04), _dark)


## One count per swing: sub-steps of the same swing touching the prop do not add up.
## Returns true when this blow broke it.
func receive_hit(swing_owner: Object, swing_serial: int, heavy: bool) -> bool:
	if is_broken:
		return false
	var owner_id := swing_owner.get_instance_id()
	if swing_serial == _last_swing and owner_id == _last_swing_owner:
		return false
	_last_swing = swing_serial
	_last_swing_owner = owner_id
	var spec: Array = KINDS[kind]
	_blows += 1.0 / float(spec[2]) if heavy else 1.0 / float(spec[1])
	if _blows < 0.999:
		_knock()
		return false
	_break()
	return true


func _knock() -> void:
	_play(&"impact_hide", 0.5)
	var tween := create_tween()
	_intact.rotation_degrees.z = 4.0
	tween.tween_property(_intact, ^"rotation_degrees:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC)


func _break() -> void:
	is_broken = true
	_area.set_deferred(&"monitorable", false)
	_area.get_child(0).set_deferred(&"disabled", true)
	_intact.visible = false
	_body.get_child(0).set_deferred(&"disabled", true)
	_play(&"wood_break", 1.0)
	_scatter()
	broken.emit(self)


func _play(cue: StringName, strength: float) -> void:
	var path := "res://assets/audio/sfx/%s.wav" % cue
	if not ResourceLoader.exists(path):
		path = "res://assets/audio/sfx/impact_hide_0.wav" if cue == &"impact_hide" else "res://assets/audio/sfx/%s_0.wav" % cue
	if not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.pitch_scale = randf_range(0.9, 1.1)
	_voice.volume_db = linear_to_db(clampf(strength, 0.05, 1.0)) - 2.0
	_voice.play()


## Splinters and staves: light bodies that only touch the world, gone in 1.5-2.5 s. When the
## scene already holds the maximum, a puff of dust stands in for them.
func _scatter() -> void:
	var spec: Array = KINDS[kind]
	var count: int = spec[3]
	var size: Vector3 = spec[0]
	if _live_fragments + count > MAX_FRAGMENTS:
		_fx().dust(global_position + Vector3.UP * size.y * 0.5, 14, 0.4)
		return
	for i in count:
		var piece := RigidBody3D.new()
		piece.collision_layer = 0
		piece.collision_mask = 1
		piece.mass = 0.6
		var mesh := BoxMesh.new()
		mesh.size = spec[4] * randf_range(0.7, 1.1)
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.material_override = _wood if i % 2 == 0 else _dark
		piece.add_child(view)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		piece.add_child(shape)
		get_tree().current_scene.add_child(piece)
		piece.global_position = global_position + Vector3(randf_range(-0.2, 0.2) * size.x, size.y * randf_range(0.3, 0.8), randf_range(-0.2, 0.2) * size.z)
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		piece.linear_velocity = Vector3(randf_range(-1.6, 1.6), randf_range(1.5, 3.2), randf_range(-1.6, 1.6))
		piece.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		_live_fragments += 1
		var life := randf_range(1.5, 2.5)
		piece.get_tree().create_timer(life, false, true).timeout.connect(func() -> void:
			_live_fragments -= 1
			if is_instance_valid(piece):
				piece.queue_free())
	_fx().dust(global_position + Vector3.UP * size.y * 0.4, 8, 0.3)


static func live_fragments() -> int:
	return _live_fragments


## Restores a crate or barrel after a rest, once nobody stands in its place. An opened grate
## stays open for the rest of the expedition.
func reset() -> void:
	if not is_broken or bool(KINDS[kind][5]):
		return
	var shape := (_body.get_child(0) as CollisionShape3D)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = 2 | 4
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		get_tree().create_timer(1.0).timeout.connect(reset)
		return
	is_broken = false
	_blows = 0.0
	_last_swing = -1
	_intact.visible = true
	shape.set_deferred(&"disabled", false)
	_area.get_child(0).set_deferred(&"disabled", false)
	_area.set_deferred(&"monitorable", true)


## The RetroFX autoload, looked up at run time so this script also compiles where autoload
## names are not known (headless test scripts that preload it).
func _fx() -> Node:
	return get_node(^"/root/RetroFX")
