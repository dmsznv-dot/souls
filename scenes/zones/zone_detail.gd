extends RefCounted
## Detail builder for zones: everything is low-poly geometry with vertex colours, gathered into
## three meshes per zone (opaque, double-sided, glowing), so a zone's detail costs three draw
## calls however much of it there is. Collision stays with the zone's simple blocks; detail is
## visual unless the zone adds a block for it.

const Props = preload("res://scenes/forest/forest_props.gd")

var opaque := SurfaceTool.new()
var foliage := SurfaceTool.new()
var glow := SurfaceTool.new()
var rng := RandomNumberGenerator.new()
var _baked := []


func _init(seed: int) -> void:
	rng.seed = seed
	for tool in [opaque, foliage, glow]:
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(-1)


## Finishes the geometry (normals, arrays). Touches no scene or server: safe on a worker thread.
func bake() -> void:
	_baked.clear()
	for tool: SurfaceTool in [opaque, foliage, glow]:
		tool.generate_normals()
		var arrays := tool.commit_to_arrays()
		var empty := arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty()
		_baked.append([] if empty else arrays)


## Adds the baked meshes under parent in a holder of that name. Zones keep one builder per
## region so no merged mesh spans more lights than the renderer gives one object.
func attach(parent: Node3D, holder_name: String) -> void:
	if _baked.is_empty():
		bake()
	var holder := Node3D.new()
	holder.name = holder_name
	parent.add_child(holder)
	var specs := [["DetailOpaque", false, false], ["DetailFoliage", true, false], ["DetailGlow", true, true]]
	for i in specs.size():
		var arrays: Array = _baked[i]
		if arrays.is_empty():
			continue
		var spec: Array = specs[i]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var view := MeshInstance3D.new()
		view.name = spec[0]
		view.mesh = mesh
		var material := Props.vertex_material(0.9)
		if spec[1]:
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if spec[2]:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.material_override = material
		holder.add_child(view)


func _jitter(color: Color, amount: float = 0.08) -> Color:
	return color.lightened(rng.randf_range(0.0, amount)).darkened(rng.randf_range(0.0, amount))


# ---------------------------------------------------------------- primitives

## An oriented box with every face its own flat shade.
func block(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var corners := []
	for i in 8:
		corners.append(center + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	# Faces as quads of corner indices, wound clockwise seen from outside.
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]
	var shades := [0.82, 0.82, 0.9, 0.9, 0.7, 1.0]
	for f in faces.size():
		var q: Array = faces[f]
		var shade: float = shades[f]
		tool.set_color(Color(color.r * shade, color.g * shade, color.b * shade))
		for k in [0, 1, 2, 0, 2, 3]:
			tool.add_vertex(corners[q[k]])


## A flat triangle seen from both sides (gables, broken slabs).
func triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	tool.set_color(color)
	for v in [a, b, c, a, c, b]:
		tool.add_vertex(v)


func frustum(tool: SurfaceTool, from: Vector3, r0: float, r1: float, height: float, sides: int, c0: Color, c1: Color, lean := Vector3.ZERO) -> void:
	Props.frustum(tool, from, r0, r1, height, sides, c0, c1, rng.randf() * TAU, lean)


## A rod between two points (roots, ropes, chains, rails): rings square to its run.
func rod(tool: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, color: Color, sides: int = 5) -> void:
	var run := b - a
	if run.length() < 0.001:
		return
	var d := run.normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	# u x v = -d, as the frustum's rings, so the shared quad faces outward.
	var v := u.cross(d)
	var twist := rng.randf() * TAU
	for i in sides:
		var a0 := TAU * i / sides + twist
		var a1 := TAU * (i + 1) / sides + twist
		var o0 := u * cos(a0) + v * sin(a0)
		var o1 := u * cos(a1) + v * sin(a1)
		Props._quad(tool, a + o0 * r0, a + o1 * r0, b + o1 * r1, b + o0 * r1, color.darkened(0.15), color)


## A rod that bends through a list of points.
func chain(tool: SurfaceTool, points: Array, r0: float, r1: float, color: Color) -> void:
	for i in points.size() - 1:
		var t0 := float(i) / (points.size() - 1)
		var t1 := float(i + 1) / (points.size() - 1)
		rod(tool, points[i], points[i + 1], lerpf(r0, r1, t0), lerpf(r0, r1, t1), _jitter(color, 0.05))


func blob(tool: SurfaceTool, center: Vector3, radius: float, scale: Vector3, color: Color, shade: float = 0.4) -> void:
	Props.blob(tool, center, radius, scale, color, color.darkened(shade), rng)


# ---------------------------------------------------------------- landscape

## A low island or bank over a box footprint (half extents in x and z): a faceted top over the
## whole footprint (so where there is ground there is a surface over it) mottled with moss and
## puddles, and a skirt sloping out and down under the water, mossy humps along the rim.
func landmass(center: Vector3, half: Vector2, top_y: float, depth: float, top_color: Color, side_color: Color) -> void:
	var nx := maxi(2, ceili(half.x * 2.0 / 1.1))
	var nz := maxi(2, ceili(half.y * 2.0 / 1.1))
	var grid := []
	for i in nx + 1:
		var column := []
		for j in nz + 1:
			var p := Vector2(-half.x + half.x * 2.0 * i / nx, -half.y + half.y * 2.0 * j / nz)
			var edge := i == 0 or i == nx or j == 0 or j == nz
			if edge:
				# Pull the rim in a little, the corners more, so the outline is not a ruler line.
				var inward := Vector2(-signf(p.x) if i == 0 or i == nx else 0.0, -signf(p.y) if j == 0 or j == nz else 0.0)
				var corner := inward.x != 0.0 and inward.y != 0.0
				p += inward.normalized() * (0.4 if corner else rng.randf_range(0.0, 0.15))
			var y := top_y + (rng.randf_range(-0.04, 0.0) if edge else rng.randf_range(-0.035, 0.015))
			column.append(Vector3(center.x + p.x, y, center.z + p.y))
		grid.append(column)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.16
	var moss := Color(0.11, 0.13, 0.09)
	var puddle := Color(0.06, 0.07, 0.09)
	for i in nx:
		for j in nz:
			var p00: Vector3 = grid[i][j]
			var p10: Vector3 = grid[i + 1][j]
			var p11: Vector3 = grid[i + 1][j + 1]
			var p01: Vector3 = grid[i][j + 1]
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				var middle: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var n := noise.get_noise_2d(middle.x, middle.z)
				var color := top_color
				if n < -0.38:
					color = puddle
				elif n > 0.28:
					color = top_color.lerp(moss, clampf((n - 0.28) * 4.0, 0.0, 1.0))
				opaque.set_color(_jitter(color, 0.03))
				for v in tri:
					opaque.add_vertex(v)
	# The rim, in the order the angle grows (from +x toward +z), and its skirt.
	var rim := []
	for j in nz + 1:
		rim.append(Vector2i(nx, j))
	for i in range(nx - 1, -1, -1):
		rim.append(Vector2i(i, nz))
	for j in range(nz - 1, -1, -1):
		rim.append(Vector2i(0, j))
	for i in range(1, nx):
		rim.append(Vector2i(i, 0))
	var mid := Vector3(center.x, top_y, center.z)
	var top := []
	var low := []
	for cell: Vector2i in rim:
		var at: Vector3 = grid[cell.x][cell.y]
		top.append(at)
		var out := Vector3(at.x - mid.x, 0, at.z - mid.z)
		out = Vector3(out.x / maxf(half.x, 0.1), 0, out.z / maxf(half.y, 0.1)).normalized()
		low.append(at + out * rng.randf_range(1.0, 2.2) + Vector3(0, -depth, 0))
	var points := top.size()
	for i in points:
		var j := (i + 1) % points
		opaque.set_color(_jitter(side_color, 0.06))
		opaque.add_vertex(top[j])
		opaque.add_vertex(top[i])
		opaque.add_vertex(low[i])
		opaque.add_vertex(top[j])
		opaque.add_vertex(low[i])
		opaque.add_vertex(low[j])
	# Mossy humps and stones along the rim, half sunk.
	for i in range(0, points, 3):
		var at: Vector3 = top[i].lerp(mid, rng.randf_range(0.02, 0.05))
		blob(opaque, at - Vector3(0, 0.12, 0), rng.randf_range(0.25, 0.5), Vector3(1.3, 0.45, 1.0), _jitter(Color(0.13, 0.16, 0.1)))


## A plank walk along -Z from z0 to z1 at deck height: planks across, a hand apart, each
## a little different; two stringers below.
func plank_walk(x: float, z0: float, z1: float, deck_y: float, width: float, planks: Color) -> void:
	var z := z0 - 0.15
	while z > z1 + 0.1:
		var tilt := Basis.from_euler(Vector3(0, rng.randf_range(-0.03, 0.03), rng.randf_range(-0.02, 0.02)))
		block(opaque, Vector3(x + rng.randf_range(-0.04, 0.04), deck_y - 0.04 + rng.randf_range(-0.015, 0.01), z),
				Vector3(width * rng.randf_range(0.96, 1.04), 0.07, 0.24), _jitter(planks, 0.12), tilt)
		z -= 0.29
	for side: float in [-1.0, 1.0]:
		block(opaque, Vector3(x + side * width * 0.36, deck_y - 0.16, (z0 + z1) * 0.5), Vector3(0.14, 0.14, absf(z0 - z1)), planks.darkened(0.35))


## A rope hanging between two points.
func rope(a: Vector3, b: Vector3, sag: float, color: Color) -> void:
	var points := []
	for i in 7:
		var t := i / 6.0
		points.append(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0))
	chain(foliage, points, 0.018, 0.018, color)


## A clump of reeds: thin double-sided blades leaning out.
func reeds(at: Vector3, radius: float, count: int) -> void:
	for i in count:
		var base := at + Vector3(rng.randf_range(-radius, radius), 0, rng.randf_range(-radius, radius))
		var height := rng.randf_range(0.6, 1.4)
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.03
		var tip := base + Vector3(0, height, 0) + lean
		var color := Color(0.25, 0.3, 0.16).lerp(Color(0.4, 0.36, 0.2), rng.randf())
		foliage.set_color(color.darkened(0.4))
		foliage.add_vertex(base - side)
		foliage.add_vertex(base + side)
		foliage.set_color(color)
		foliage.add_vertex(tip)
		if rng.randf() < 0.3:
			# A seed head.
			block(opaque, tip - lean * 0.05, Vector3(0.05, 0.18, 0.05), Color(0.22, 0.14, 0.09))


func lily_pads(at: Vector3, radius: float, count: int, water_y: float) -> void:
	for i in count:
		var p := at + Vector3(rng.randf_range(-radius, radius), 0, rng.randf_range(-radius, radius))
		var r := rng.randf_range(0.18, 0.35)
		var green := _jitter(Color(0.16, 0.26, 0.14))
		var center := Vector3(p.x, water_y + 0.015, p.z)
		var notch := rng.randf() * TAU
		for k in 7:
			var a0 := notch + 0.35 + (TAU - 0.5) * k / 7.0
			var a1 := notch + 0.35 + (TAU - 0.5) * (k + 1) / 7.0
			opaque.set_color(green)
			opaque.add_vertex(center)
			opaque.add_vertex(center + Vector3(cos(a0), 0, sin(a0)) * r)
			opaque.add_vertex(center + Vector3(cos(a1), 0, sin(a1)) * r)


# ---------------------------------------------------------------- stone and roots

## Rough rock clinging to a wall: boulders half sunk into the face so it stops reading as a
## flat box. Normal points into the room; size is the face's extent (u along tangent, v up).
func rock_skin(face_center: Vector3, normal: Vector3, width: float, height: float, density: float, color: Color) -> void:
	var tangent := Vector3.UP.cross(normal).normalized()
	if tangent == Vector3.ZERO:
		tangent = Vector3.RIGHT
	var up := normal.cross(tangent).normalized()
	var count := int(width * height * density)
	for i in count:
		var u := rng.randf_range(-0.5, 0.5) * width
		var v := rng.randf_range(-0.5, 0.5) * height
		var r := rng.randf_range(0.3, 0.55)
		# Sunk past half into the face: nothing stands out more than about 0.4 m.
		var at := face_center + tangent * u + up * v - normal * r * 0.6
		blob(opaque, at, r, Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.9, 1.3)), _jitter(color, 0.1), 0.18)


## Masonry courses on a wall face: blocks a finger proud of the surface.
func masonry(face_center: Vector3, normal: Vector3, width: float, height: float, color: Color) -> void:
	var tangent := Vector3.UP.cross(normal).normalized()
	var course := 0.32
	var rows := int(height / course)
	for row in rows:
		var u := -width * 0.5 + (0.3 if row % 2 else 0.0)
		while u < width * 0.5 - 0.15:
			var length := minf(rng.randf_range(0.5, 0.8), width * 0.5 - u)
			if rng.randf() > 0.12:
				var at := face_center + tangent * (u + length * 0.5) + Vector3.UP * (-height * 0.5 + course * (row + 0.5)) + normal * 0.04
				block(opaque, at, Vector3(length - 0.04, course - 0.04, 0.1), _jitter(color, 0.1), Basis(tangent, Vector3.UP, normal).orthonormalized())
			u += length


## A root snaking from a to b with a few kinks.
func root(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var points := [a]
	for i in range(1, 5):
		var t := i / 5.0
		points.append(a.lerp(b, t) + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.3, 0.1), rng.randf_range(-0.25, 0.25)))
	points.append(b)
	chain(opaque, points, radius, radius * 0.5, color)


## A column: base, shaft in drums, capital; roots wrapped round it.
func pillar(at: Vector3, height: float, radius: float, color: Color, roots: Color) -> void:
	block(opaque, at + Vector3(0, 0.18, 0), Vector3(radius * 2.6, 0.36, radius * 2.6), color.darkened(0.15))
	var drums := 4
	for i in drums:
		var y := 0.36 + (height - 0.8) * i / drums
		frustum(opaque, at + Vector3(rng.randf_range(-0.02, 0.02), y, 0), radius, radius * 0.96, (height - 0.8) / drums - 0.03, 8, _jitter(color), _jitter(color))
	block(opaque, at + Vector3(0, height - 0.22, 0), Vector3(radius * 2.8, 0.44, radius * 2.8), color.darkened(0.1))
	for k in 3:
		var angle := rng.randf() * TAU
		var p := []
		for s in 6:
			var t := s / 5.0
			var a := angle + t * 2.2
			p.append(at + Vector3(cos(a) * radius * 1.05, height * (1.0 - t * 0.95), sin(a) * radius * 1.05))
		chain(opaque, p, 0.09, 0.05, roots)


## A stone coffin with a cracked lid.
func sarcophagus(at: Vector3, yaw: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	block(opaque, at + basis * Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 2.1), color, basis)
	block(opaque, at + basis * Vector3(0, 0.86, -0.45), Vector3(1.0, 0.12, 1.1), color.lightened(0.08), basis * Basis(Vector3.RIGHT, 0.04))
	block(opaque, at + basis * Vector3(0.05, 0.84, 0.6), Vector3(0.98, 0.12, 0.95), color.lightened(0.05), basis * Basis(Vector3.FORWARD, 0.08))


## A chain hanging from a point: links turned a quarter to each other, a hook at the end.
func iron_chain(from: Vector3, length: float, color: Color) -> void:
	var links := int(length / 0.14)
	for i in links:
		var at := from - Vector3(0, 0.07 + i * 0.14, 0)
		var turn := Basis(Vector3.UP, PI * 0.5 * (i % 2))
		block(opaque, at + turn * Vector3(0.035, 0, 0), Vector3(0.02, 0.17, 0.02), color, turn)
		block(opaque, at + turn * Vector3(-0.035, 0, 0), Vector3(0.02, 0.17, 0.02), color, turn)
	var end := from - Vector3(0, links * 0.14, 0)
	rod(opaque, end, end + Vector3(0.08, -0.16, 0), 0.025, 0.02, color, 4)
	rod(opaque, end + Vector3(0.08, -0.16, 0), end + Vector3(0.0, -0.24, 0), 0.02, 0.015, color, 4)


## A stone flag floor over a rectangle: slabs a finger proud, a few missing or cracked.
func flagstones(center: Vector3, half: Vector2, slab: Vector2, color: Color, skip: float = 0.1) -> void:
	var x := -half.x
	var row := 0
	while x < half.x - 0.05:
		var width := minf(slab.x * rng.randf_range(0.8, 1.2), half.x - x)
		var z := -half.y + (slab.y * 0.5 if row % 2 else 0.0)
		if row % 2:
			z = -half.y
		while z < half.y - 0.05:
			var depth := minf(slab.y * rng.randf_range(0.7, 1.3), half.y - z)
			if rng.randf() > skip:
				var at := center + Vector3(x + width * 0.5, 0.015 + rng.randf_range(-0.01, 0.012), z + depth * 0.5)
				block(opaque, at, Vector3(width - 0.05, 0.04, depth - 0.05), _jitter(color, 0.1), Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)))
			z += depth
		x += width
		row += 1


## A cluster of candles: wax in the opaque mesh, flames in the glowing one.
func candles(at: Vector3, count: int) -> void:
	for i in count:
		var p := at + Vector3(rng.randf_range(-0.22, 0.22), 0, rng.randf_range(-0.22, 0.22))
		var h := rng.randf_range(0.08, 0.3)
		frustum(opaque, p, 0.035, 0.03, h, 5, Color(0.75, 0.7, 0.58), Color(0.85, 0.8, 0.66))
		block(glow, p + Vector3(0, h + 0.035, 0), Vector3(0.025, 0.06, 0.025), Color(1.0, 0.75, 0.35))


# ---------------------------------------------------------------- air

static func _soft_sprite(color: Color, size: Vector2, additive: bool) -> QuadMesh:
	var texture := GradientTexture2D.new()
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	texture.gradient = gradient
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.no_depth_test = false
	material.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	return quad


## Slow drifting particles in a box: mist banks over water, fireflies, dust in a light shaft.
static func drift(name: String, at: Vector3, extents: Vector3, amount: int, lifetime: float, sprite: QuadMesh,
		speed: float, color: Color) -> CPUParticles3D:
	var air := CPUParticles3D.new()
	air.name = name
	air.amount = amount
	air.lifetime = lifetime
	air.preprocess = lifetime
	air.mesh = sprite
	air.position = at
	air.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	air.emission_box_extents = extents
	air.direction = Vector3(1, 0.2, 0)
	air.spread = 180.0
	air.gravity = Vector3.ZERO
	air.initial_velocity_min = speed * 0.4
	air.initial_velocity_max = speed
	air.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	air.visibility_aabb = AABB(-extents - Vector3.ONE * 2.0, extents * 2.0 + Vector3.ONE * 4.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.0))
	ramp.add_point(0.3, color)
	ramp.add_point(0.7, color)
	ramp.set_color(ramp.get_point_count() - 1, Color(color, 0.0))
	air.color_ramp = ramp
	return air


static func mist(at: Vector3, extents: Vector3, amount: int) -> CPUParticles3D:
	return drift("Mist", at, extents, amount, 14.0, _soft_sprite(Color(1, 1, 1), Vector2(5.0, 2.2), false), 0.25,
			Color(0.55, 0.62, 0.72, 0.13))


static func fireflies(at: Vector3, extents: Vector3, amount: int) -> CPUParticles3D:
	var air := drift("Fireflies", at, extents, amount, 5.0, _soft_sprite(Color(1, 1, 1), Vector2(0.09, 0.09), true), 0.35,
			Color(0.75, 0.95, 0.5, 0.9))
	air.direction = Vector3(0, 1, 0)
	air.gravity = Vector3(0, -0.05, 0)
	return air


static func dust(at: Vector3, extents: Vector3, amount: int) -> CPUParticles3D:
	var air := drift("Dust", at, extents, amount, 9.0, _soft_sprite(Color(1, 1, 1), Vector2(0.05, 0.05), true), 0.08,
			Color(0.7, 0.78, 0.95, 0.55))
	air.gravity = Vector3(0, -0.02, 0)
	return air


## A cold shaft of light: an open cone, additive and faint, brightest at the top.
static func light_shaft(top: Vector3, bottom: Vector3, r_top: float, r_bottom: float, color: Color) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 12
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := bottom + Vector3(cos(a0), 0, sin(a0)) * r_bottom
		var p1 := bottom + Vector3(cos(a1), 0, sin(a1)) * r_bottom
		var q0 := top + Vector3(cos(a0), 0, sin(a0)) * r_top
		var q1 := top + Vector3(cos(a1), 0, sin(a1)) * r_top
		Props._quad(tool, p0, p1, q1, q0, Color(color, 0.0), color)
	var view := MeshInstance3D.new()
	view.name = "LightShaft"
	view.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view
