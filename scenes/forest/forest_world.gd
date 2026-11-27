extends RefCounted
## The Thornwood's ground and growth, generated from fixed seeds so every run is the same
## place. A dirt road winds from the entrance south-west through dense fir and broadleaf to a
## clearing with the bonfire. Terrain, trees and undergrowth are split into 20 m chunks:
## the Compatibility renderer lights each object with at most eight lights, so a lantern only
## has to reach the chunks around it, and far chunks cull as a whole.
##
## Space: x across, z along the road (the entrance near z 10, the clearing near z -214).

const Props = preload("res://scenes/forest/forest_props.gd")

const MIN := Vector2(-56.0, -240.0)
const MAX := Vector2(64.0, 18.0)
const CHUNK := 20.0
## Growth is batched in larger cells: one MultiMesh per mesh per cell. A lantern every 15 m
## keeps any cell under the eight-light limit, and far fewer draw calls are issued.
const GROWTH_CHUNK := 40.0
const ROAD_POINTS := [Vector3(0, 0, 18), Vector3(0, 0, 4), Vector3(3, 0, -18), Vector3(-6, 0, -44),
	Vector3(-3, 0, -70), Vector3(8, 0, -94), Vector3(12, 0, -118), Vector3(3, 0, -144),
	Vector3(-7, 0, -166), Vector3(-4, 0, -190), Vector3(0, 0, -204)]
const CLEARING := Vector3(0, 0, -216)
const CLEARING_RADIUS := 13.0
const ROAD_HALF := 1.7
## Trees keep this far from the road's centre line.
const ROAD_CLEAR := 4.2

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
## Road centre x and height for each metre of z, index = int(MAX.y - z).
var _road_x := PackedFloat32Array()
var _road_y := PackedFloat32Array()
var _road_slope := PackedFloat32Array()
var _clearing_y := 0.0
var _rng := RandomNumberGenerator.new()
## When set, build() spreads its work over frames: at most SLICE_USEC per frame.
var _tree: SceneTree
var _slice_start := 0
const SLICE_USEC := 2500
var _grid := PackedFloat32Array()
var _grid_width := 0
var _grid_depth := 0

## Filled by build(): positions along the road (every metre, from entrance to clearing).
var road := PackedVector3Array()
## Round obstacles (trunks, big rocks): Vector4(x, y, z, radius).
var trunks: Array[Vector4] = []
## Fallen logs: Vector3(x, z, yaw).
var logs: Array[Vector3] = []


func _init() -> void:
	_noise.seed = 9
	_noise.frequency = 0.022
	_noise.fractal_octaves = 3
	_detail.seed = 21
	_detail.frequency = 0.11
	_build_road()


# ---------------------------------------------------------------- road and ground

func _build_road() -> void:
	var curve := Curve3D.new()
	for i in ROAD_POINTS.size():
		var point: Vector3 = ROAD_POINTS[i]
		var before: Vector3 = ROAD_POINTS[maxi(i - 1, 0)]
		var after: Vector3 = ROAD_POINTS[mini(i + 1, ROAD_POINTS.size() - 1)]
		var tangent := (after - before) * 0.22
		curve.add_point(point, -tangent, tangent)
	curve.bake_interval = 0.25
	var baked := curve.get_baked_points()
	var count := int(MAX.y - MIN.y) + 1
	_road_x.resize(count)
	var cursor := 0
	for i in count:
		var z := MAX.y - i
		while cursor < baked.size() - 2 and baked[cursor + 1].z > z:
			cursor += 1
		var a := baked[cursor]
		var b := baked[mini(cursor + 1, baked.size() - 1)]
		var t := 0.0 if absf(b.z - a.z) < 0.0001 else clampf((z - a.z) / (b.z - a.z), 0.0, 1.0)
		_road_x[i] = lerpf(a.x, b.x, t) if z >= ROAD_POINTS[-1].z else lerpf(ROAD_POINTS[-1].x, CLEARING.x, smoothstep(ROAD_POINTS[-1].z, CLEARING.z, z))
	_road_slope.resize(count)
	for i in count:
		_road_slope[i] = (_road_x[mini(i + 1, count - 1)] - _road_x[maxi(i - 1, 0)]) * 0.5
	# The road's own height: the raw ground under it, smoothed over a dozen metres.
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in count:
		raw[i] = _raw_height(_road_x[i], MAX.y - i)
	_road_y.resize(count)
	for i in count:
		var sum := 0.0
		var n := 0
		for k in range(-7, 8):
			var j := clampi(i + k, 0, count - 1)
			sum += raw[j]
			n += 1
		_road_y[i] = sum / n
	_clearing_y = _road_y[_index(CLEARING.z)]
	road.clear()
	for i in count:
		var z := MAX.y - i
		if z < CLEARING.z:
			break
		road.append(Vector3(_road_x[i], _road_y[i], z))


func _index(z: float) -> int:
	return clampi(int(round(MAX.y - z)), 0, _road_x.size() - 1)


func _raw_height(x: float, z: float) -> float:
	return _noise.get_noise_2d(x, z) * 3.2 + (MAX.y - z) * 0.012


## Lateral distance from the road's centre line.
func road_distance(x: float, z: float) -> float:
	var i := _index(z)
	return absf(x - _road_x[i]) / sqrt(1.0 + _road_slope[i] * _road_slope[i])


func road_x(z: float) -> float:
	return _road_x[_index(z)]


## Ground height, read from the metre grid build() fills (bilinear between samples).
func height(x: float, z: float) -> float:
	if _grid.is_empty():
		return _exact_height(x, z)
	var gx := clampf(x - MIN.x, 0.0, _grid_width - 1.001)
	var gz := clampf(z - MIN.y, 0.0, _grid_depth - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var a := lerpf(_grid[j * _grid_width + i], _grid[j * _grid_width + i + 1], fx)
	var b := lerpf(_grid[(j + 1) * _grid_width + i], _grid[(j + 1) * _grid_width + i + 1], fx)
	return lerpf(a, b, fz)


func _exact_height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	var d := road_distance(x, z)
	h = lerpf(h, _road_y[_index(z)], 1.0 - smoothstep(3.0, 9.0, d))
	var to_clearing := Vector2(x - CLEARING.x, z - CLEARING.z).length()
	h = lerpf(h, _clearing_y, 1.0 - smoothstep(CLEARING_RADIUS, CLEARING_RADIUS + 6.0, to_clearing))
	return h


func point(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)


func _ground_color(x: float, z: float) -> Color:
	var moss := Color(0.12, 0.18, 0.11).lerp(Color(0.17, 0.2, 0.12), _detail.get_noise_2d(x, z) * 0.5 + 0.5)
	var litter := smoothstep(0.15, 0.5, _noise.get_noise_2d(x * 2.0, z * 2.0))
	moss = moss.lerp(Color(0.24, 0.17, 0.11), litter * 0.6)
	var d := road_distance(x, z)
	var dirt := Color(0.27, 0.21, 0.16).lerp(Color(0.2, 0.16, 0.12), _detail.get_noise_2d(z, x) * 0.5 + 0.5)
	var on_road := 1.0 - smoothstep(ROAD_HALF - 0.3, ROAD_HALF + 0.9, d)
	if z < ROAD_POINTS[-1].z + 4.0:
		var to_clearing := Vector2(x - CLEARING.x, z - CLEARING.z).length()
		on_road = maxf(on_road, 1.0 - smoothstep(CLEARING_RADIUS - 4.0, CLEARING_RADIUS, to_clearing))
	return moss.lerp(dirt, on_road)


# ---------------------------------------------------------------- build

func _pace() -> void:
	if _tree != null and Time.get_ticks_usec() - _slice_start > SLICE_USEC:
		await _tree.process_frame
		_slice_start = Time.get_ticks_usec()


## Builds everything static under root: ground chunks, the ground's collision, vegetation,
## logs and rocks with their collision, invisible bounds. With a tree, the work is sliced
## across frames (await it); without, it all happens now.
func build(root: Node3D, tree: SceneTree = null) -> void:
	_tree = tree
	_slice_start = Time.get_ticks_usec()
	_grid_width = int(MAX.x - MIN.x) + 1
	_grid_depth = int(MAX.y - MIN.y) + 1
	var grid := PackedFloat32Array()
	grid.resize(_grid_width * _grid_depth)
	for j in _grid_depth:
		for i in _grid_width:
			grid[j * _grid_width + i] = _exact_height(MIN.x + i, MIN.y + j)
		await _pace()
	_grid = grid
	var ground_material := Props.vertex_material(0.95)
	var chunks := {}
	var columns := int(ceil((MAX.x - MIN.x) / CHUNK))
	var rows := int(ceil((MAX.y - MIN.y) / CHUNK))
	for cx in columns:
		for cz in rows:
			var chunk := Node3D.new()
			chunk.name = "Chunk_%d_%d" % [cx, cz]
			root.add_child(chunk)
			chunks[Vector2i(cx, cz)] = chunk
			var ground := MeshInstance3D.new()
			ground.name = "Ground"
			ground.mesh = _ground_mesh(MIN.x + cx * CHUNK, MIN.y + cz * CHUNK)
			ground.material_override = ground_material
			chunk.add_child(ground)
			_chunk_collision(chunk, MIN.x + cx * CHUNK, MIN.y + cz * CHUNK)
			await _pace()
	await _vegetation(root, chunks)
	_bounds(root)
	_tree = null


func _ground_mesh(x0: float, z0: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var step := 1.0
	var n := int(CHUNK / step)
	for i in n:
		for j in n:
			var x := x0 + i * step
			var z := z0 + j * step
			var p00 := point(x, z)
			var p10 := point(x + step, z)
			var p01 := point(x, z + step)
			var p11 := point(x + step, z + step)
			var c := _ground_color(x + step * 0.5, z + step * 0.5)
			tool.set_color(c)
			for v in [p00, p10, p01, p10, p11, p01]:
				tool.add_vertex(v)
	tool.generate_normals()
	return tool.commit()


## One height field per chunk: small shapes build quickly, so slicing keeps frames smooth.
func _chunk_collision(chunk: Node3D, x0: float, z0: float) -> void:
	var cells := int(CHUNK)
	var size := cells + 1
	var data := PackedFloat32Array()
	data.resize(size * size)
	var i0 := int(x0 - MIN.x)
	var j0 := int(z0 - MIN.y)
	for j in size:
		for i in size:
			var gi := mini(i0 + i, _grid_width - 1)
			var gj := mini(j0 + j, _grid_depth - 1)
			data[j * size + i] = _grid[gj * _grid_width + gi]
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	chunk.add_child(body)
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	holder.position = Vector3(x0 + cells * 0.5, 0, z0 + cells * 0.5)


## Walls of thicket at the edges of the map: impassable, and screened by the densest trees.
func _bounds(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Bounds"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var size := MAX - MIN
	for wall in [[Vector3(MIN.x + 2.0, 4, (MIN.y + MAX.y) * 0.5), Vector3(1, 14, size.y)],
			[Vector3(MAX.x - 2.0, 4, (MIN.y + MAX.y) * 0.5), Vector3(1, 14, size.y)],
			[Vector3((MIN.x + MAX.x) * 0.5, 4, MIN.y + 2.0), Vector3(size.x, 14, 1)],
			[Vector3((MIN.x + MAX.x) * 0.5, 4, MAX.y - 1.0), Vector3(size.x, 14, 1)]]:
		var shape := BoxShape3D.new()
		shape.size = wall[1]
		var holder := CollisionShape3D.new()
		holder.shape = shape
		body.add_child(holder)
		holder.position = wall[0]


## Density of trees: none on the road or in the clearing, thin in glades, a wall near the edges.
func _tree_density(x: float, z: float) -> float:
	var d := road_distance(x, z)
	if d < ROAD_CLEAR:
		return 0.0
	var to_clearing := Vector2(x - CLEARING.x, z - CLEARING.z).length()
	if to_clearing < CLEARING_RADIUS + 1.0:
		return 0.0
	if Vector2(x - _road_x[0], z - 8.0).length() < 7.0:
		return 0.0
	var edge := minf(minf(x - MIN.x, MAX.x - x), minf(z - MIN.y, MAX.y - z))
	var glade := smoothstep(0.25, 0.55, _detail.get_noise_2d(x * 0.35, z * 0.35))
	var density := lerpf(0.75, 0.2, glade) * smoothstep(ROAD_CLEAR, ROAD_CLEAR + 3.0, d)
	return maxf(density, 1.0 - smoothstep(4.0, 10.0, edge))


func _vegetation(root: Node3D, chunks: Dictionary) -> void:
	_rng.seed = 77
	var kinds := {
		"fir": [Props.fir(1), Props.fir(2)],
		"oak": [Props.oak(4), Props.oak(5)],
		"snag": [Props.snag(6)],
		"bush": [Props.bush(7)],
		"fern": [Props.fern(9)],
		"rock": [Props.rock(10)],
		"log": [Props.log_mesh(12)],
		"caps": [Props.mushrooms(13)],
	}
	var fern_material := Props.vertex_material()
	fern_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow := Props.vertex_material()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# chunk -> mesh -> [transforms, colours]
	var placed := {}
	var solids := {}
	var spacing := 3.1
	var x := MIN.x
	while x < MAX.x:
		var z := MIN.y
		while z < MAX.y:
			var px := x + _rng.randf_range(-1.2, 1.2)
			var pz := z + _rng.randf_range(-1.2, 1.2)
			if _rng.randf() < _tree_density(px, pz):
				var roll := _rng.randf()
				var kind := "fir" if roll < 0.62 else ("oak" if roll < 0.88 else "snag")
				var meshes: Array = kinds[kind]
				var scale := _rng.randf_range(0.8, 1.35)
				_place(placed, meshes[_rng.randi() % meshes.size()], px, pz, scale, _rng.randf() * TAU,
						Color(1, 1, 1).darkened(_rng.randf_range(0.0, 0.3)))
				var radius := (0.26 if kind == "fir" else (0.42 if kind == "oak" else 0.3)) * scale
				_solid_trunk(solids, px, pz, radius)
			z += spacing
		x += spacing
		await _pace()
	# Undergrowth and litter, thicker beside the road where lantern light catches it.
	for k in 4200:
		if k % 200 == 0:
			await _pace()
		var px := _rng.randf_range(MIN.x + 1.0, MAX.x - 1.0)
		var pz := _rng.randf_range(MIN.y + 1.0, MAX.y - 1.0)
		var d := road_distance(px, pz)
		if d < ROAD_HALF + 0.6:
			continue
		var roll := _rng.randf()
		if roll < 0.45:
			_place(placed, kinds["fern"][0], px, pz, _rng.randf_range(0.7, 1.4), _rng.randf() * TAU, Color.WHITE.darkened(_rng.randf_range(0, 0.25)), fern_material)
		elif roll < 0.8:
			_place(placed, kinds["bush"][0], px, pz, _rng.randf_range(0.7, 1.5), _rng.randf() * TAU, Color.WHITE.darkened(_rng.randf_range(0, 0.3)))
		elif roll < 0.9 and d > 3.0:
			_place(placed, kinds["caps"][0], px, pz, _rng.randf_range(0.8, 1.4), _rng.randf() * TAU, Color.WHITE, glow)
		elif roll < 0.97:
			var scale := _rng.randf_range(0.5, 1.6)
			_place(placed, kinds["rock"][0], px, pz, scale, _rng.randf() * TAU, Color.WHITE.darkened(_rng.randf_range(0, 0.2)))
			if scale > 1.0 and d > 3.0:
				_solid_trunk(solids, px, pz, 0.75 * scale)
		elif d > 4.0:
			var yaw := _rng.randf() * TAU
			_place(placed, kinds["log"][0], px, pz, 1.0, yaw, Color.WHITE)
			_solid_log(solids, px, pz, yaw)
	var growth := {}
	for key: Array in placed.keys():
		if not growth.has(key[0]):
			var cell := Node3D.new()
			cell.name = "Growth_%d_%d" % [key[0].x, key[0].y]
			root.add_child(cell)
			growth[key[0]] = cell
		var chunk: Node3D = growth[key[0]]
		var entry: Array = placed[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = key[1]
		multimesh.instance_count = entry[0].size()
		for i in entry[0].size():
			multimesh.set_instance_transform(i, entry[0][i])
			multimesh.set_instance_color(i, entry[1][i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = key[2]
		await _pace()
		var tall: bool = key[1] in kinds["fir"] or key[1] in kinds["oak"] or key[1] in kinds["snag"]
		if not tall:
			# Low growth vanishes into the fog early and casts no shadow worth its cost.
			instance.visibility_range_end = 38.0
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(instance)
	for chunk_key in solids:
		var body := StaticBody3D.new()
		body.name = "Trunks"
		body.collision_layer = 1
		body.collision_mask = 0
		chunks[chunk_key].add_child(body)
		for shape: Array in solids[chunk_key]:
			var holder := CollisionShape3D.new()
			holder.shape = shape[0]
			body.add_child(holder)
			holder.transform = shape[1]
		await _pace()


func _chunk_of(x: float, z: float) -> Vector2i:
	var columns := int(ceil((MAX.x - MIN.x) / CHUNK))
	var rows := int(ceil((MAX.y - MIN.y) / CHUNK))
	return Vector2i(clampi(int((x - MIN.x) / CHUNK), 0, columns - 1), clampi(int((z - MIN.y) / CHUNK), 0, rows - 1))


var _default_material: StandardMaterial3D


func _place(placed: Dictionary, mesh: Mesh, x: float, z: float, scale: float, yaw: float, tint: Color, material: Material = null) -> void:
	if material == null:
		if _default_material == null:
			_default_material = Props.vertex_material()
		material = _default_material
	var key := [Vector2i(int((x - MIN.x) / GROWTH_CHUNK), int((z - MIN.y) / GROWTH_CHUNK)), mesh, material]
	if not placed.has(key):
		placed[key] = [[], []]
	var sink := 0.15 * scale
	placed[key][0].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), point(x, z) - Vector3(0, sink, 0)))
	placed[key][1].append(tint)


func _solid_trunk(solids: Dictionary, x: float, z: float, radius: float) -> void:
	trunks.append(Vector4(x, height(x, z), z, radius))
	var chunk := _chunk_of(x, z)
	if not solids.has(chunk):
		solids[chunk] = []
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.0
	solids[chunk].append([shape, Transform3D(Basis.IDENTITY, point(x, z) + Vector3(0, 1.6, 0))])


func _solid_log(solids: Dictionary, x: float, z: float, yaw: float) -> void:
	logs.append(Vector3(x, z, yaw))
	var chunk := _chunk_of(x, z)
	if not solids.has(chunk):
		solids[chunk] = []
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.6, 4.0)
	solids[chunk].append([shape, Transform3D(Basis(Vector3.UP, yaw), point(x, z) + Vector3(0, 0.15, 0))])


## Navigation source built straight from the height grid and the obstacle lists, much faster
## than parsing thousands of collision shapes. Trunks, rocks and logs carve holes. Await it.
func navigation_source(tree: SceneTree = null) -> NavigationMeshSourceGeometryData3D:
	_tree = tree
	_slice_start = Time.get_ticks_usec()
	var data := NavigationMeshSourceGeometryData3D.new()
	for j in _grid_depth - 1:
		var faces := PackedVector3Array()
		for i in _grid_width - 1:
			var x := MIN.x + i
			var z := MIN.y + j
			var p00 := Vector3(x, _grid[j * _grid_width + i], z)
			var p10 := Vector3(x + 1, _grid[j * _grid_width + i + 1], z)
			var p01 := Vector3(x, _grid[(j + 1) * _grid_width + i], z + 1)
			var p11 := Vector3(x + 1, _grid[(j + 1) * _grid_width + i + 1], z + 1)
			faces.append_array([p00, p10, p01, p10, p11, p01])
		data.add_faces(faces, Transform3D.IDENTITY)
		if j % 8 == 0:
			await _pace()
	var count := 0
	for trunk in trunks:
		var ring := PackedVector3Array()
		for k in 6:
			var angle := TAU * k / 6.0
			ring.append(Vector3(trunk.x + cos(angle) * trunk.w, 0, trunk.z + sin(angle) * trunk.w))
		data.add_projected_obstruction(ring, trunk.y - 1.0, 5.0, true)
		count += 1
		if count % 300 == 0:
			await _pace()
	for log in logs:
		var basis := Basis(Vector3.UP, log.z)
		var corners := PackedVector3Array()
		for corner in [Vector3(-0.35, 0, -2.0), Vector3(0.35, 0, -2.0), Vector3(0.35, 0, 2.0), Vector3(-0.35, 0, 2.0)]:
			corners.append(basis * corner + Vector3(log.x, 0, log.y))
		data.add_projected_obstruction(corners, height(log.x, log.y) - 1.0, 3.0, true)
	_tree = null
	return data
