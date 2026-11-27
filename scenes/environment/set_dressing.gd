extends RefCounted
## Reusable set dressing for any area: cracked and sunken paving, rubble, fallen columns,
## collapsed wall sections, broken carts, campfires, barrels, crates, sacks and bones.
##
## An area describes its dressing as a list of entries, each a Dictionary with a "kind" and
## its placement ("at" in area space, optional "yaw" in degrees and a "seed"):
##
##     SetDressing.dress(area_root, [
##         {"kind": "cart", "at": Vector3(5, 0, -3), "yaw": 20, "broken": true},
##         {"kind": "campfire", "at": Vector3(-5, 0, -5.5), "camp": true},
##     ])
##
## Everything is built from low-poly boxes and lofts in the shared palette; props a body could
## walk into get static collision on layer 1, so a navigation rebake (rebake_navigation) routes
## foes around them. Small litter has no collision and never snags anyone.

const NoirLighting = preload("res://scenes/fx/noir_lighting.gd")
const DARK_STONE := preload("res://scenes/expedition/gate/court_stone.tres")
const IRON := preload("res://assets/environment/aged_iron.tres")
const CRACKLE_PREFIX := "WatchFireCamp"

var _root: Node3D
var _rng := RandomNumberGenerator.new()
var _materials := {}
var _fires := 0
## Weathered stone matched to the paving, so spill reads as part of the ruin, not new blocks.
var STONE: StandardMaterial3D = _mat("ruin_stone", Color(0.34, 0.35, 0.32), 0.92)


static func dress(root: Node3D, layout: Array, seed_base: int = 7) -> Node3D:
	var builder := new()
	var holder := Node3D.new()
	holder.name = "SetDressing"
	root.add_child(holder)
	builder._root = holder
	for i in layout.size():
		var entry: Dictionary = layout[i]
		builder._rng.seed = int(entry.get("seed", seed_base * 1000 + i))
		var prop := Node3D.new()
		prop.name = "%s%d" % [String(entry["kind"]).capitalize().replace(" ", ""), i]
		holder.add_child(prop)
		prop.position = entry.get("at", Vector3.ZERO)
		prop.rotation_degrees.y = entry.get("yaw", 0.0)
		builder.call("_" + String(entry["kind"]), prop, entry)
	_merge(holder)
	return holder


## Hundreds of small parts become one mesh per material and shadow setting: a handful of draw
## calls instead of several hundred. Collision, lights and particles stay where they are.
static func _merge(holder: Node3D) -> void:
	var groups := {}
	for part in holder.find_children("*", "MeshInstance3D", true, false):
		var key := [part.material_override, part.cast_shadow]
		if not groups.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = tool
		var relative := _relative(part, holder)
		for surface in part.mesh.get_surface_count():
			groups[key].append_from(part.mesh, surface, relative)
	var parts := holder.find_children("*", "MeshInstance3D", true, false)
	parts.reverse()
	for part in parts:
		# Children first: some parts carry smaller parts (crate battens, skull sockets).
		part.free()
	var index := 0
	for key in groups:
		var merged := MeshInstance3D.new()
		merged.name = "Merged%d" % index
		index += 1
		merged.mesh = groups[key].commit()
		merged.material_override = key[0]
		merged.cast_shadow = key[1]
		holder.add_child(merged)


static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor:
		transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


## Rebuilds a region's navigation mesh from the static colliders under source, so foes path
## around the dressing. Bounds are in source space; floor_height is the walkable floor's height
## above the bottom of the bounds.
static func rebake_navigation(region: NavigationRegion3D, source: Node3D, bounds: AABB, floor_height: float = 1.0) -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.5
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.filter_baking_aabb = bounds
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, data, source)
	NavigationServer3D.bake_from_source_geometry_data(mesh, data)
	if mesh.get_polygon_count() == 0:
		return
	# Recast places a flat floor a cell or two above the stone; agents compare waypoints in 3D,
	# so the mesh is settled back onto the floor. Islands on top of walls and piers are dropped.
	var vertices := mesh.vertices
	var floor_y := INF
	for v in vertices:
		floor_y = minf(floor_y, v.y)
	var lift := floor_y - bounds.position.y - floor_height
	for i in vertices.size():
		vertices[i].y -= lift
	var settled := NavigationMesh.new()
	settled.cell_size = mesh.cell_size
	settled.cell_height = mesh.cell_height
	settled.agent_radius = mesh.agent_radius
	settled.agent_height = mesh.agent_height
	settled.agent_max_climb = mesh.agent_max_climb
	settled.vertices = vertices
	for p in mesh.get_polygon_count():
		var polygon := mesh.get_polygon(p)
		var height := 0.0
		for index in polygon:
			height += vertices[index].y
		if height / polygon.size() < bounds.position.y + floor_height + 0.6:
			settled.add_polygon(polygon)
	region.navigation_mesh = settled


# ---------------------------------------------------------------- materials and primitives

func _mat(key: String, color: Color, roughness: float = 0.85, unshaded: bool = false) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		if unshaded:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = material
	return _materials[key]


func _wood() -> StandardMaterial3D:
	return _mat("wood", Color(0.25, 0.19, 0.15))


func _old_wood() -> StandardMaterial3D:
	return _mat("old_wood", Color(0.19, 0.16, 0.14))


func _box(parent: Node3D, size: Vector3, material: Material, at: Vector3, degrees := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	parent.add_child(part)
	part.position = at
	part.rotation_degrees = degrees
	return part


func _cylinder(parent: Node3D, radius: float, height: float, material: Material, at: Vector3,
		degrees := Vector3.ZERO, sides: int = 8, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	parent.add_child(part)
	part.position = at
	part.rotation_degrees = degrees
	return part


## Static collision box in the prop's space.
func _solid(prop: Node3D, size: Vector3, at: Vector3, degrees := Vector3.ZERO) -> void:
	var body := prop.get_node_or_null(^"Solid") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = 1
		body.collision_mask = 0
		prop.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	holder.position = at
	holder.rotation_degrees = degrees


func _rand_angles(spread: float) -> Vector3:
	return Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(0, 360), _rng.randf_range(-spread, spread))


# ---------------------------------------------------------------- ground

## Jagged dark fissures across the paving. size: Vector2 extent, count: number of cracks.
func _cracks(prop: Node3D, entry: Dictionary) -> void:
	var size: Vector2 = entry.get("size", Vector2(4, 4))
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_normal(Vector3.UP)
	for c in int(entry.get("count", 4)):
		var point := Vector2(_rng.randf_range(-0.5, 0.5) * size.x, _rng.randf_range(-0.5, 0.5) * size.y)
		var heading := _rng.randf() * TAU
		var width := _rng.randf_range(0.11, 0.17)
		for step in _rng.randi_range(5, 9):
			heading += _rng.randf_range(-0.7, 0.7)
			var next := point + Vector2(cos(heading), sin(heading)) * _rng.randf_range(0.3, 0.7)
			_ribbon(builder, point, next, width)
			if _rng.randf() < 0.3:
				# A short branch splits off.
				var fork := heading + _rng.randf_range(0.6, 1.2) * (1.0 if _rng.randf() < 0.5 else -1.0)
				_ribbon(builder, next, next + Vector2(cos(fork), sin(fork)) * _rng.randf_range(0.2, 0.4), width * 0.6)
			point = next
			width *= 0.86
	var mesh := MeshInstance3D.new()
	mesh.mesh = builder.commit()
	mesh.material_override = _mat("crack", Color(0.035, 0.03, 0.035), 1.0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prop.add_child(mesh)


func _ribbon(builder: SurfaceTool, from: Vector2, to: Vector2, width: float) -> void:
	var side := (to - from).orthogonal().normalized() * width * 0.5
	var y := 0.012
	var a := Vector3(from.x - side.x, y, from.y - side.y)
	var b := Vector3(from.x + side.x, y, from.y + side.y)
	var c := Vector3(to.x - side.x * 0.7, y, to.y - side.y * 0.7)
	var d := Vector3(to.x + side.x * 0.7, y, to.y + side.y * 0.7)
	# Clockwise seen from above: Godot's front face.
	for v in [a, b, c, b, d, c]:
		builder.add_vertex(v)


## A patch where the paving has given way: a dark pit with broken slabs tipped into it.
func _sunken(prop: Node3D, entry: Dictionary) -> void:
	var radius: float = entry.get("radius", 1.2)
	var pit := _cylinder(prop, radius, 0.02, _mat("pit", Color(0.02, 0.018, 0.022), 1.0), Vector3(0, 0.008, 0), Vector3.ZERO, 7)
	pit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in _rng.randi_range(5, 7):
		var angle := TAU * i / 6.0 + _rng.randf_range(-0.3, 0.3)
		var at := Vector3(cos(angle), 0, sin(angle)) * radius * _rng.randf_range(0.45, 0.8)
		var slab := Vector3(_rng.randf_range(0.5, 0.8), 0.12, _rng.randf_range(0.4, 0.7))
		# Tipped inward and down, their outer edges still at floor level.
		_box(prop, slab, DARK_STONE, at + Vector3(0, -0.02, 0), Vector3(_rng.randf_range(-16, 16), rad_to_deg(-angle), _rng.randf_range(-16, 16)))
	_rubble_bits(prop, radius * 0.5, 6, false)


## Loose stone: scattered blocks; the larger ones block movement when collide is set.
func _rubble(prop: Node3D, entry: Dictionary) -> void:
	_rubble_bits(prop, entry.get("radius", 1.0), int(entry.get("count", 10)), bool(entry.get("collide", true)))


func _rubble_bits(prop: Node3D, radius: float, count: int, collide: bool) -> void:
	for i in count:
		var r := radius * sqrt(_rng.randf())
		var angle := _rng.randf() * TAU
		var size := _rng.randf_range(0.12, 0.45) * (1.0 - 0.4 * r / maxf(radius, 0.01))
		var block := Vector3(size * _rng.randf_range(0.8, 1.6), size * _rng.randf_range(0.5, 0.9), size)
		var at := Vector3(cos(angle) * r, block.y * 0.35, sin(angle) * r)
		var angles := _rand_angles(18)
		_box(prop, block, STONE if _rng.randf() < 0.7 else DARK_STONE, at, angles)
		if collide and size > 0.32:
			_solid(prop, block, at, angles)


# ---------------------------------------------------------------- ruins

## A column broken off its base, lying in drums with its capital rolled aside.
func _fallen_column(prop: Node3D, entry: Dictionary) -> void:
	var length: float = entry.get("length", 3.6)
	var radius: float = entry.get("radius", 0.36)
	var drums := int(entry.get("drums", 3))
	var along := -length * 0.5
	for i in drums:
		var drum := length / drums - 0.08
		var twist := _rng.randf_range(-7, 7)
		var at := Vector3(along + drum * 0.5, radius, _rng.randf_range(-0.12, 0.12))
		_cylinder(prop, radius, drum, STONE, at, Vector3(_rng.randf_range(0, 40), twist, 90), 10)
		_solid(prop, Vector3(drum, radius * 1.8, radius * 1.8), at, Vector3(0, twist, 0))
		along += length / drums + _rng.randf_range(0.0, 0.18)
	# Stump on its base and the square capital.
	_cylinder(prop, radius * 1.05, 0.55, STONE, Vector3(-length * 0.5 - 0.6, 0.27, 0.2), Vector3(0, 0, 0), 10)
	_box(prop, Vector3(0.95, 0.95, 0.95), STONE, Vector3(-length * 0.5 - 0.6, 0.12, 0.2), Vector3(0, 12, 0)).scale = Vector3(1, 0.25, 1)
	_solid(prop, Vector3(0.9, 0.6, 0.9), Vector3(-length * 0.5 - 0.6, 0.3, 0.2))
	var capital := Vector3(length * 0.5 + 0.5, 0.26, _rng.randf_range(-0.4, 0.4))
	_box(prop, Vector3(0.8, 0.5, 0.8), STONE, capital, Vector3(_rng.randf_range(-12, 12), 30, 8))
	_solid(prop, Vector3(0.8, 0.5, 0.8), capital, Vector3(0, 30, 0))
	_rubble_bits(prop, 0.8, 5, false)


## A section of wall that came down: ragged courses, a breach, its blocks spilled in front.
func _collapsed_wall(prop: Node3D, entry: Dictionary) -> void:
	var width: float = entry.get("width", 3.0)
	var height: float = entry.get("height", 1.8)
	var course := 0.3
	var rows := int(height / course)
	for row in rows:
		var x := -width * 0.5
		var stagger := 0.25 if row % 2 == 1 else 0.0
		x += stagger
		while x < width * 0.5 - 0.1:
			var block := minf(_rng.randf_range(0.45, 0.7), width * 0.5 - x)
			# The breach widens toward the top: blocks near the middle are missing.
			var breach := absf(x + block * 0.5) < width * 0.12 * (row + 1) / float(rows) * 2.4
			if not breach or row == 0:
				_box(prop, Vector3(block - 0.03, course - 0.02, 0.5), DARK_STONE if (row + int(x * 3.0)) % 3 == 0 else STONE,
						Vector3(x + block * 0.5, course * (row + 0.5), _rng.randf_range(-0.03, 0.03)),
						Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-3, 3), _rng.randf_range(-2, 2)))
			x += block
	_solid(prop, Vector3(width, height * 0.6, 0.5), Vector3(0, height * 0.3, 0))
	var spill := Node3D.new()
	prop.add_child(spill)
	spill.position = Vector3(0, 0, 0.9)
	_rubble_bits(spill, 1.1, 14, true)


# ---------------------------------------------------------------- the abandoned camp

## A two-wheeled cart. Broken: a wheel gone, the bed down on that corner, a shaft snapped and
## its load spilled.
func _cart(prop: Node3D, entry: Dictionary) -> void:
	var broken := bool(entry.get("broken", true))
	var body := Node3D.new()
	prop.add_child(body)
	var tilt := Vector3(0, 0, -11.0) if broken else Vector3.ZERO
	body.rotation_degrees = tilt
	body.position = Vector3(0, -0.12 if broken else 0.0, 0)
	var wood := _wood()
	for i in 6:
		_box(body, Vector3(1.12, 0.05, 0.27), wood if i % 2 == 0 else _old_wood(), Vector3(0, 0.62, -0.7 + i * 0.28),
				Vector3(0, 0, _rng.randf_range(-2, 2)))
	for side in [-1.0, 1.0]:
		_box(body, Vector3(0.05, 0.3, 1.7), _old_wood(), Vector3(side * 0.56, 0.8, 0), Vector3(0, 0, side * -6))
	_box(body, Vector3(1.15, 0.3, 0.05), _old_wood(), Vector3(0, 0.8, 0.84))
	_box(body, Vector3(0.09, 0.09, 1.4), wood, Vector3(0, 0.52, 0))
	_cylinder(body, 0.04, 1.4, IRON, Vector3(0, 0.45, -0.1), Vector3(0, 0, 90), 6)
	# Shafts reach forward; a broken one ends in a splintered stub.
	for side in [-1.0, 1.0]:
		var snapped: bool = broken and side > 0.0
		var length := 0.9 if snapped else 1.9
		_box(body, Vector3(0.07, 0.07, length), wood, Vector3(side * 0.35, 0.55, -0.85 - length * 0.5), Vector3(-6, 0, 0))
	if broken:
		_box(prop, Vector3(0.07, 0.07, 1.0), wood, Vector3(0.75, 0.04, -2.1), Vector3(0, 28, 90))
	for side in [-1.0, 1.0]:
		if broken and side > 0.0:
			_wheel(prop, Vector3(1.4, 0.05, 0.6), Vector3(90, 0, 15))
		else:
			_wheel(body, Vector3(side * 0.68, 0.45, -0.1), Vector3(0, 0, 90))
	_solid(prop, Vector3(1.4, 1.0, 1.8), Vector3(0, 0.5, 0), tilt)
	if bool(entry.get("load", true)):
		for i in 3:
			_sack(prop, Vector3(_rng.randf_range(0.7, 1.4), 0.0, _rng.randf_range(-0.6, 0.8)))
		var crate := Node3D.new()
		prop.add_child(crate)
		crate.position = Vector3(-1.0, 0, 0.9)
		_crates(crate, {"count": 2})


func _wheel(parent: Node3D, at: Vector3, degrees: Vector3) -> void:
	var wheel := Node3D.new()
	parent.add_child(wheel)
	wheel.position = at
	wheel.rotation_degrees = degrees
	var rim := TorusMesh.new()
	rim.inner_radius = 0.36
	rim.outer_radius = 0.45
	rim.rings = 12
	rim.ring_segments = 4
	var tyre := MeshInstance3D.new()
	tyre.mesh = rim
	tyre.material_override = _old_wood()
	wheel.add_child(tyre)
	tyre.rotation_degrees = Vector3(0, 0, 90)
	_cylinder(wheel, 0.08, 0.16, IRON, Vector3.ZERO, Vector3(0, 0, 90), 6)
	for k in 6:
		_box(wheel, Vector3(0.04, 0.72, 0.04), _wood(), Vector3.ZERO, Vector3(k * 30.0, 0, 0))


func _sack(parent: Node3D, at: Vector3) -> void:
	var sack := _cylinder(parent, 0.22, 0.5, _mat("sack", Color(0.48, 0.42, 0.3)), at + Vector3(0, 0.14, 0),
			Vector3(90, _rng.randf_range(0, 360), 0), 6, 0.14)
	sack.scale = Vector3(1, 1, 0.6)


## A fire ring with crossed logs and embers. Lit: a flickering light (crackling, via the
## torch audio), rising sparks. Camp: log seats and a bedroll around it.
func _campfire(prop: Node3D, entry: Dictionary) -> void:
	for i in 9:
		var angle := TAU * i / 9.0
		_box(prop, Vector3(0.2, 0.14, 0.16), DARK_STONE, Vector3(cos(angle) * 0.42, 0.06, sin(angle) * 0.42), Vector3(0, rad_to_deg(-angle), _rng.randf_range(-8, 8)))
	for i in 4:
		_cylinder(prop, 0.06, 0.7, _mat("charred", Color(0.1, 0.08, 0.07)), Vector3(0, 0.12, 0),
				Vector3(70, i * 45.0 + _rng.randf_range(-10, 10), 0), 6)
	var lit := bool(entry.get("lit", true))
	var embers := _cylinder(prop, 0.26, 0.05, _mat("embers", Color(1.0, 0.42, 0.12) if lit else Color(0.35, 0.12, 0.06), 1.0, true),
			Vector3(0, 0.04, 0), Vector3.ZERO, 7)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var solid_radius := 0.55
	_solid(prop, Vector3(solid_radius * 2, 0.4, solid_radius * 2), Vector3(0, 0.2, 0))
	if lit:
		var light := OmniLight3D.new()
		light.name = "%s%d" % [CRACKLE_PREFIX, _fires]
		_fires += 1
		light.omni_range = 4.5
		light.light_energy = 2.5
		prop.add_child(light)
		light.position = Vector3(0, 0.6, 0)
		prop.add_child(_flames())
	if bool(entry.get("camp", false)):
		for k in 2:
			var angle := TAU * (0.15 + k * 0.45)
			var seat := _cylinder(prop, 0.16, 1.1, _old_wood(), Vector3(cos(angle) * 1.3, 0.15, sin(angle) * 1.3),
					Vector3(0, rad_to_deg(-angle) + 90, 90), 7)
			seat.name = "Seat%d" % k
			_solid(prop, Vector3(0.32, 0.3, 1.1), seat.position, Vector3(0, rad_to_deg(-angle) + 90, 0))
		var roll := _cylinder(prop, 0.17, 0.9, _mat("bedroll", Color(0.42, 0.18, 0.15)), Vector3(-0.4, 0.17, 1.4), Vector3(0, 80, 90), 7)
		roll.name = "Bedroll"
		_box(prop, Vector3(0.75, 0.03, 1.6), _mat("blanket", Color(0.3, 0.26, 0.22)), Vector3(0.9, 0.02, 1.2), Vector3(0, -25, 0))
		_cylinder(prop, 0.14, 0.2, IRON, Vector3(0.25, 0.32, -0.1), Vector3(0, 0, 0), 7, 0.17)


func _flames() -> CPUParticles3D:
	var flames := CPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = 18
	flames.lifetime = 0.7
	flames.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = glow
	flames.mesh = quad
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.16
	flames.direction = Vector3.UP
	flames.spread = 14.0
	flames.gravity = Vector3(0, 1.6, 0)
	flames.initial_velocity_min = 0.4
	flames.initial_velocity_max = 0.9
	flames.scale_amount_min = 0.7
	flames.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.82, 0.4, 1.0))
	ramp.add_point(0.45, Color(1.0, 0.42, 0.1, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.4, 0.1, 0.05, 0.0))
	flames.color_ramp = ramp
	flames.position = Vector3(0, 0.15, 0)
	return flames


func _barrels(prop: Node3D, entry: Dictionary) -> void:
	for i in int(entry.get("count", 3)):
		var at := Vector3(_rng.randf_range(-0.7, 0.7), 0, _rng.randf_range(-0.7, 0.7)) if i > 0 else Vector3.ZERO
		var barrel := Node3D.new()
		prop.add_child(barrel)
		var tipped := i == 2
		barrel.position = at + (Vector3(0.6, 0.28, 0.2) if tipped else Vector3(0, 0.42, 0))
		barrel.rotation_degrees = Vector3(0, _rng.randf_range(0, 360), 90 if tipped else 0)
		_cylinder(barrel, 0.28, 0.84, _old_wood(), Vector3.ZERO, Vector3.ZERO, 10, 0.25)
		for y in [-0.3, 0.3]:
			_cylinder(barrel, 0.29, 0.05, IRON, Vector3(0, y, 0), Vector3.ZERO, 10)
		_solid(prop, Vector3(0.56, 0.84, 0.56), barrel.position, barrel.rotation_degrees)


func _crates(prop: Node3D, entry: Dictionary) -> void:
	var count := int(entry.get("count", 3))
	for i in count:
		var size := _rng.randf_range(0.45, 0.6)
		var stacked := i == count - 1 and count >= 3
		var at := Vector3(i * 0.65 - (count - 1) * 0.3, size * 0.5, _rng.randf_range(-0.15, 0.15))
		if stacked:
			at = Vector3(-0.3, size * 1.5 + 0.04, 0)
		var angles := Vector3(0, _rng.randf_range(-20, 20), 0)
		var crate := _box(prop, Vector3.ONE * size, _wood(), at, angles)
		for k in 2:
			_box(crate, Vector3(size * 1.02, 0.06, 0.06), _old_wood(), Vector3(0, 0, (k - 0.5) * size * 0.98)).rotation_degrees.x = 0
			_box(crate, Vector3(0.06, size * 1.02, 0.06), _old_wood(), Vector3((k - 0.5) * size * 0.98, 0, -size * 0.51))
		_solid(prop, Vector3.ONE * size, at, angles)


## Scattered bones; a skull or two.
func _bones(prop: Node3D, entry: Dictionary) -> void:
	var radius: float = entry.get("radius", 1.0)
	var bone := _mat("bone", Color(0.8, 0.76, 0.64), 0.9)
	for i in int(entry.get("count", 10)):
		var r := radius * sqrt(_rng.randf())
		var angle := _rng.randf() * TAU
		var length := _rng.randf_range(0.18, 0.42)
		_cylinder(prop, 0.025, length, bone, Vector3(cos(angle) * r, 0.03, sin(angle) * r),
				Vector3(90, _rng.randf_range(0, 360), 0), 5)
	for k in int(entry.get("skulls", 1)):
		var at := Vector3(_rng.randf_range(-0.5, 0.5), 0.09, _rng.randf_range(-0.5, 0.5)) * radius
		var skull := _cylinder(prop, 0.1, 0.18, bone, at, Vector3(_rng.randf_range(-20, 20), _rng.randf_range(0, 360), 90), 7, 0.08)
		skull.scale = Vector3(1, 1, 1.1)
		_box(skull, Vector3(0.05, 0.04, 0.03), _mat("socket", Color(0.03, 0.03, 0.03)), Vector3(0.03, -0.02, -0.09))
		_box(skull, Vector3(0.05, 0.04, 0.03), _mat("socket", Color(0.03, 0.03, 0.03)), Vector3(-0.03, -0.02, -0.09))
