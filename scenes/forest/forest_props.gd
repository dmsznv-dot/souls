extends RefCounted
## Low-poly meshes for the Thornwood: trees, undergrowth, rocks, logs, glowing caps, and the
## lights that guide the player (lanterns on posts, torches) and the bonfire with its spear.
## Meshes carry vertex colours and flat normals so one material draws a whole tree, which lets
## MultiMesh place thousands of them in a handful of draw calls.

const NoirLighting = preload("res://scenes/fx/noir_lighting.gd")


static func vertex_material(roughness: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = roughness
	return material


# ---------------------------------------------------------------- primitives

## Faceted frustum from (center, r0) up to (center + up * height, r1), coloured bottom to top.
static func frustum(tool: SurfaceTool, center: Vector3, r0: float, r1: float, height: float, sides: int,
		c0: Color, c1: Color, twist: float = 0.0, lean := Vector3.ZERO) -> void:
	var top := center + Vector3.UP * height + lean
	for i in sides:
		var a0 := TAU * i / sides + twist
		var a1 := TAU * (i + 1) / sides + twist
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * r0
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * r0
		var q0 := top + Vector3(cos(a0), 0, sin(a0)) * r1
		var q1 := top + Vector3(cos(a1), 0, sin(a1)) * r1
		_quad(tool, p0, p1, q1, q0, c0, c1)
		if r1 > 0.001:
			_tri(tool, top, q0, q1, c1)
		if r0 > 0.001:
			_tri(tool, center, p1, p0, c0)


## Quad with its front outward when p0 -> p1 runs counter-clockwise seen from above (Godot's
## front faces wind clockwise as seen by the viewer): bottom edge p0-p1, top edge q0-q1.
static func _quad(tool: SurfaceTool, p0: Vector3, p1: Vector3, q1: Vector3, q0: Vector3, bottom: Color, top: Color) -> void:
	tool.set_color(bottom)
	tool.add_vertex(p0)
	tool.add_vertex(p1)
	tool.set_color(top)
	tool.add_vertex(q0)
	tool.set_color(bottom)
	tool.add_vertex(p1)
	tool.set_color(top)
	tool.add_vertex(q1)
	tool.add_vertex(q0)


static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


## Faceted blob: a low-poly ball squashed by scale.
static func blob(tool: SurfaceTool, center: Vector3, radius: float, scale: Vector3, color: Color, shade: Color, rng: RandomNumberGenerator) -> void:
	var rings := 3
	var sides := 6
	var points := []
	for r in rings + 1:
		var row := []
		var phi := PI * r / rings
		for s in sides:
			var theta := TAU * s / sides + (0.5 if r % 2 == 1 else 0.0)
			var jitter := 1.0 + rng.randf_range(-0.12, 0.12) if r > 0 and r < rings else 1.0
			row.append(center + Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * scale * radius * jitter)
		points.append(row)
	for r in rings:
		var c_top := color.lerp(shade, float(r) / rings)
		var c_bottom := color.lerp(shade, float(r + 1) / rings)
		for s in sides:
			var a: Vector3 = points[r][s]
			var b: Vector3 = points[r][(s + 1) % sides]
			var c: Vector3 = points[r + 1][s]
			var d: Vector3 = points[r + 1][(s + 1) % sides]
			_quad(tool, c, d, b, a, c_bottom, c_top)


static func _commit(tool: SurfaceTool) -> ArrayMesh:
	tool.generate_normals()
	return tool.commit()


static func _begin() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	return tool


# ---------------------------------------------------------------- vegetation

## A fir: a bare lower trunk and stacked, slightly offset cones, darkest at the bottom.
static func fir(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	var height := rng.randf_range(8.0, 11.0)
	var bark := Color(0.22, 0.16, 0.12)
	frustum(tool, Vector3.ZERO, 0.24, 0.1, height * 0.55, 6, bark, bark.darkened(0.2))
	var tiers := 4
	for t in tiers:
		var f := float(t) / tiers
		var base := height * (0.22 + f * 0.58)
		var radius := lerpf(2.4, 0.9, f) * rng.randf_range(0.9, 1.1)
		var tall := height * lerpf(0.34, 0.3, f)
		var green := Color(0.1, 0.2, 0.15).lerp(Color(0.17, 0.3, 0.2), f)
		var offset := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		frustum(tool, Vector3(0, base, 0) + offset, radius, 0.0, tall, 7, green.darkened(0.35), green.lightened(0.1), rng.randf() * TAU)
	return _commit(tool)


## A gnarled broadleaf: leaning trunk, two boughs, clumps of foliage.
static func oak(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	var bark := Color(0.25, 0.2, 0.16)
	var height := rng.randf_range(4.5, 6.0)
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	frustum(tool, Vector3.ZERO, 0.42, 0.22, height, 7, bark.darkened(0.25), bark, 0.0, lean)
	var crown := Vector3(0, height, 0) + lean
	for b in 2:
		var angle := rng.randf() * TAU
		var tip := crown + Vector3(cos(angle) * 1.8, rng.randf_range(0.6, 1.4), sin(angle) * 1.8)
		frustum(tool, crown - Vector3(0, 0.6, 0), 0.16, 0.06, (tip - crown).length(), 5, bark, bark, 0.0, tip - crown - Vector3.UP * (tip - crown).length())
	var leaves := Color(0.16, 0.26, 0.15)
	for k in 5:
		var at := crown + Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(0.4, 2.2), rng.randf_range(-1.8, 1.8))
		blob(tool, at, rng.randf_range(1.2, 1.9), Vector3(1, 0.75, 1), leaves.lightened(rng.randf_range(0.0, 0.15)), leaves.darkened(0.45), rng)
	return _commit(tool)


## A dead tree: pale trunk, broken top, bare crooked limbs.
static func snag(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	var bark := Color(0.38, 0.36, 0.33)
	var height := rng.randf_range(5.0, 8.0)
	frustum(tool, Vector3.ZERO, 0.3, 0.12, height, 6, bark.darkened(0.3), bark)
	for k in 5:
		var at := Vector3(0, height * rng.randf_range(0.4, 0.95), 0)
		var angle := rng.randf() * TAU
		var reach := Vector3(cos(angle), rng.randf_range(0.2, 0.9), sin(angle)) * rng.randf_range(1.0, 2.2)
		frustum(tool, at, 0.07, 0.02, reach.length(), 4, bark, bark.lightened(0.1), 0.0, reach - Vector3.UP * reach.length())
	return _commit(tool)


static func bush(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	var green := Color(0.13, 0.22, 0.13)
	for k in rng.randi_range(2, 4):
		var at := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.25, 0.45), rng.randf_range(-0.5, 0.5))
		blob(tool, at, rng.randf_range(0.45, 0.75), Vector3(1, 0.7, 1), green.lightened(rng.randf_range(0, 0.12)), green.darkened(0.5), rng)
	return _commit(tool)


## Fern: a fan of thin blades.
static func fern(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	var green := Color(0.16, 0.3, 0.14)
	for k in 7:
		var angle := TAU * k / 7.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(angle), 0, sin(angle))
		var side := out.cross(Vector3.UP) * 0.09
		var tip := out * rng.randf_range(0.6, 0.9) + Vector3.UP * rng.randf_range(0.35, 0.55)
		var mid := out * 0.35 + Vector3.UP * 0.4
		for flip in [1.0, -1.0]:
			_tri(tool, Vector3.ZERO, mid + side * flip, tip, green.darkened(0.3) if flip > 0 else green)
	tool.set_smooth_group(-1)
	return _commit(tool)


static func rock(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	var stone := Color(0.3, 0.31, 0.3)
	blob(tool, Vector3(0, 0.25, 0), 0.8, Vector3(1.2, 0.7, 1.0), stone.lightened(0.1), stone.darkened(0.3), rng)
	# Moss cap.
	blob(tool, Vector3(0.1, 0.62, 0), 0.5, Vector3(1.3, 0.25, 1.1), Color(0.18, 0.28, 0.14), Color(0.12, 0.2, 0.1), rng)
	return _commit(tool)


static func log_mesh(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	var bark := Color(0.24, 0.19, 0.15)
	var length := rng.randf_range(3.0, 5.0)
	frustum(tool, Vector3(0, 0.3, -length * 0.5), 0.32, 0.26, length, 7, bark.darkened(0.25), bark)
	var mesh := _commit(tool)
	# Lay it along Z: rebuild with the frustum turned onto its side.
	var turned := _begin()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var basis := Basis(Vector3.RIGHT, PI * 0.5)
	for i in vertices.size():
		turned.set_color(colors[i])
		var v := basis * (vertices[i] - Vector3(0, 0.3, -length * 0.5)) + Vector3(0, 0.3, -length * 0.5)
		turned.add_vertex(v)
	return _commit(turned)


## A cluster of glowing caps: cold light in the undergrowth.
static func mushrooms(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tool := _begin()
	for k in rng.randi_range(3, 6):
		var at := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var tall := rng.randf_range(0.08, 0.22)
		frustum(tool, at, 0.025, 0.02, tall, 4, Color(0.6, 0.75, 0.8), Color(0.7, 0.85, 0.9))
		frustum(tool, at + Vector3.UP * tall, rng.randf_range(0.06, 0.11), 0.0, 0.06, 6, Color(0.3, 0.95, 1.0), Color(0.6, 1.0, 1.0))
	return _commit(tool)


# ---------------------------------------------------------------- guiding lights

## A lantern hung from a crooked post. Its light is named "Lamp" so the noir pass warms it and
## gives it a flicker and a crackle.
static func lantern(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Lantern%d" % index
	var tool := _begin()
	var wood := Color(0.2, 0.15, 0.11)
	frustum(tool, Vector3.ZERO, 0.08, 0.06, 2.3, 5, wood.darkened(0.3), wood)
	frustum(tool, Vector3(0, 2.15, 0), 0.04, 0.04, 0.7, 4, wood, wood, PI * 0.25, Vector3(0, -0.7, 0) + Vector3(0.65, 0, 0))
	# The arm is a frustum laid sideways: rebuild as a beam.
	var iron := Color(0.12, 0.12, 0.13)
	frustum(tool, Vector3(0.62, 1.68, 0), 0.11, 0.09, 0.32, 4, iron, iron, PI * 0.25)
	frustum(tool, Vector3(0.62, 2.0, 0), 0.13, 0.0, 0.12, 4, iron, iron, PI * 0.25)
	var post := MeshInstance3D.new()
	post.mesh = _commit(tool)
	post.material_override = vertex_material()
	root.add_child(post)
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.24, 0.15)
	glass.mesh = box
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.72, 0.35)
	glass.material_override = glow
	root.add_child(glass)
	glass.position = Vector3(0.62, 1.84, 0)
	var light := OmniLight3D.new()
	light.name = "Lamp%d" % index
	light.omni_range = 4.6
	root.add_child(light)
	light.position = Vector3(0.62, 1.8, 0)
	return root


## A torch staked in the ground, its flame alive; the light is a "WatchFire" for the noir pass.
static func torch(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Torch%d" % index
	var tool := _begin()
	var wood := Color(0.24, 0.18, 0.12)
	frustum(tool, Vector3.ZERO, 0.05, 0.06, 1.6, 5, wood.darkened(0.3), wood)
	frustum(tool, Vector3(0, 1.5, 0), 0.09, 0.11, 0.2, 5, Color(0.15, 0.1, 0.08), Color(0.3, 0.12, 0.06))
	var stake := MeshInstance3D.new()
	stake.mesh = _commit(tool)
	stake.material_override = vertex_material()
	root.add_child(stake)
	root.add_child(flames(0.6, 12, 0.07))
	root.get_child(-1).position = Vector3(0, 1.72, 0)
	var light := OmniLight3D.new()
	light.name = "WatchFireTorch%d" % index
	light.omni_range = 4.0
	root.add_child(light)
	light.position = Vector3(0, 1.9, 0)
	return root


static func flames(lifetime: float, amount: int, size: float, spread_radius: float = 0.06) -> CPUParticles3D:
	var fire := CPUParticles3D.new()
	fire.name = "Flames"
	fire.amount = amount
	fire.lifetime = lifetime
	fire.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = glow
	fire.mesh = quad
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = spread_radius
	fire.direction = Vector3.UP
	fire.spread = 12.0
	fire.gravity = Vector3(0, 1.8, 0)
	fire.initial_velocity_min = 0.3
	fire.initial_velocity_max = 0.8
	fire.scale_amount_min = 0.7
	fire.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.86, 0.45, 1.0))
	ramp.add_point(0.4, Color(1.0, 0.45, 0.1, 0.95))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.35, 0.08, 0.04, 0.0))
	fire.color_ramp = ramp
	return fire


## The bonfire: ash and charred logs in a ring of stones, a spear driven through it at a slant.
## Unlit it smoulders; lit, it burns high with sparks. Returns the root; "Fire" holds the
## flames and light that kindle() turns on.
static func bonfire() -> Node3D:
	var root := Node3D.new()
	root.name = "Bonfire"
	var tool := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var stone := Color(0.28, 0.28, 0.27)
	for i in 10:
		var angle := TAU * i / 10.0
		blob(tool, Vector3(cos(angle), 0.08, sin(angle)) * 0.85, 0.2, Vector3(1.2, 0.8, 1.0), stone.lightened(0.08), stone.darkened(0.3), rng)
	blob(tool, Vector3(0, 0.02, 0), 0.75, Vector3(1, 0.18, 1), Color(0.22, 0.2, 0.19), Color(0.1, 0.09, 0.09), rng)
	var char := Color(0.09, 0.07, 0.06)
	for i in 5:
		var angle := TAU * i / 5.0 + 0.3
		var out := Vector3(cos(angle), 0, sin(angle))
		frustum(tool, out * 0.55, 0.09, 0.06, 0.75, 5, char, Color(0.3, 0.1, 0.05), 0.0, -out * 0.55 + Vector3.UP * -0.25)
	# The spear: an ash shaft driven in at a slant, a leaf blade buried, a rag tied below the head.
	var lean := Vector3(0.35, 0, 0.18)
	var shaft_dark := Color(0.22, 0.17, 0.12)
	frustum(tool, Vector3(0, -0.3, 0), 0.035, 0.03, 2.4, 5, shaft_dark, shaft_dark.lightened(0.15), 0.0, lean)
	var butt := Vector3(0, 2.1, 0) + lean * (2.4 / 2.4)
	frustum(tool, butt, 0.045, 0.045, 0.12, 5, Color(0.35, 0.3, 0.22), Color(0.35, 0.3, 0.22), 0.0, lean * 0.05)
	frustum(tool, Vector3(0, 1.45, 0) + lean * 0.7, 0.06, 0.05, 0.22, 5, Color(0.45, 0.12, 0.1), Color(0.35, 0.1, 0.08), 0.0, lean * 0.1)
	var body := MeshInstance3D.new()
	body.mesh = _commit(tool)
	body.material_override = vertex_material()
	root.add_child(body)
	var fire := Node3D.new()
	fire.name = "Fire"
	root.add_child(fire)
	var high := flames(1.0, 44, 0.24, 0.32)
	high.name = "HighFlames"
	high.initial_velocity_max = 1.4
	high.emitting = false
	fire.add_child(high)
	high.position = Vector3(0, 0.2, 0)
	var sparks := flames(1.8, 14, 0.04, 0.3)
	sparks.name = "Sparks"
	sparks.gravity = Vector3(0, 2.6, 0)
	sparks.spread = 35.0
	sparks.emitting = false
	fire.add_child(sparks)
	sparks.position = Vector3(0, 0.4, 0)
	var embers := MeshInstance3D.new()
	embers.name = "Embers"
	var bed := CylinderMesh.new()
	bed.top_radius = 0.42
	bed.bottom_radius = 0.5
	bed.height = 0.05
	bed.radial_segments = 7
	embers.mesh = bed
	var ember_glow := StandardMaterial3D.new()
	ember_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_glow.albedo_color = Color(1.0, 0.36, 0.1)
	embers.material_override = ember_glow
	fire.add_child(embers)
	embers.position = Vector3(0, 0.07, 0)
	var smoulder := flames(1.2, 6, 0.06, 0.3)
	smoulder.name = "Smoulder"
	fire.add_child(smoulder)
	smoulder.position = Vector3(0, 0.05, 0)
	var light := OmniLight3D.new()
	light.name = "BonfireLight"
	light.light_color = Color(1.0, 0.52, 0.2)
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.omni_attenuation = 0.8
	fire.add_child(light)
	light.position = Vector3(0, 1.0, 0)
	var shape := CylinderShape3D.new()
	shape.radius = 0.95
	shape.height = 0.5
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	var holder := CollisionShape3D.new()
	holder.shape = shape
	solid.add_child(holder)
	holder.position = Vector3(0, 0.25, 0)
	root.add_child(solid)
	return root
