extends MeshInstance3D
## Verlet cloth mantle. A grid of particles hangs from a row pinned across the back of the
## shoulders and is integrated in world space every physics step, so it trails the body through
## turns, rolls and stops by inertia alone. Gravity, the Weather wind and its gusts push it;
## spheres around the torso and legs and the floor keep it outside the body. The mesh is rebuilt
## each rendered frame from positions interpolated between the last two steps, matching the
## physics-interpolated body. The hem is torn: each column ends at its own length.

const COLUMNS := 6
const ROWS := 7
const ITERATIONS := 6
const DAMPING := 0.994
const GRAVITY := Vector3(0, -9.8, 0)
## Moves farther than this in one step (a respawn or a streamed teleport) reset the cloth.
const SNAP_DISTANCE := 1.5

## Skeleton whose bones carry the pins and the colliders.
var rig_skeleton: Skeleton3D
## Width of the pinned top edge and of the hem, and the cape's length, in metres.
var top_width := 0.38
var hem_width := 0.56
var length := 0.8
## Per-column hem trim (fraction of length): the torn edge.
var tears := PackedFloat32Array([0.04, 0.16, 0.0, 0.1, 0.02, 0.2])

var _points := PackedVector3Array()
var _previous := PackedVector3Array()
## Positions at the start of the latest step, for render interpolation.
var _rendered_from := PackedVector3Array()
var _rest := PackedVector3Array()
var _links: Array[Vector3i] = []
var _link_length := PackedFloat32Array()
var _mesh := ImmediateMesh.new()
var _ready_to_draw := false
var _last_anchor := Vector3.INF
var _clock := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Vertices are written in world space.
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_build_rest()


## Local rest layout in Chest-bone space: a trapezoid from the shoulders down the back.
func _build_rest() -> void:
	_rest.resize(COLUMNS * ROWS)
	for row in ROWS:
		var t := float(row) / (ROWS - 1)
		for column in COLUMNS:
			var u := float(column) / (COLUMNS - 1) - 0.5
			var trim := tears[column % tears.size()] * smoothstep(0.6, 1.0, t)
			var width := lerpf(top_width, hem_width, t)
			_rest[row * COLUMNS + column] = Vector3(u * width, 0.29 - t * length * (1.0 - trim), 0.2 + absf(u) * 0.06 + t * 0.04)
	_links.clear()
	_link_length.clear()
	for row in ROWS:
		for column in COLUMNS:
			var i := row * COLUMNS + column
			if column + 1 < COLUMNS:
				_add_link(i, i + 1)
			if row + 1 < ROWS:
				_add_link(i, i + COLUMNS)
				# Shear links keep the panel from folding into a rope.
				if column + 1 < COLUMNS:
					_add_link(i, i + COLUMNS + 1)
				if column > 0:
					_add_link(i, i + COLUMNS - 1)
			if row + 2 < ROWS:
				# Bend links: cloth resists folding sharply on itself.
				_add_link(i, i + COLUMNS * 2, 0.4)


func _add_link(a: int, b: int, stiffness: float = 1.0) -> void:
	_links.append(Vector3i(a, b, roundi(stiffness * 100.0)))
	_link_length.append(_rest[a].distance_to(_rest[b]))


func _chest() -> Transform3D:
	return rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(rig_skeleton.find_bone("Chest"))


func reset() -> void:
	var chest := _chest()
	_points.resize(_rest.size())
	for i in _rest.size():
		_points[i] = chest * _rest[i]
	_previous = _points.duplicate()
	_rendered_from = _points.duplicate()
	_last_anchor = chest.origin
	_ready_to_draw = true


func _physics_process(delta: float) -> void:
	if rig_skeleton == null or not is_visible_in_tree():
		return
	var chest := _chest()
	if not _ready_to_draw or chest.origin.distance_to(_last_anchor) > SNAP_DISTANCE:
		reset()
	_last_anchor = chest.origin
	_rendered_from = _points.duplicate()
	_clock += delta
	var wind := Vector3.ZERO
	var weather := get_node_or_null(^"/root/Weather")
	if weather != null:
		wind = weather.wind_direction * (weather.wind * 6.0 + weather.gust * 8.0)
	var floor_y: float = rig_skeleton.global_position.y + 0.02
	var scale_factor := rig_skeleton.global_basis.get_scale().y
	var colliders := _colliders(scale_factor)
	for i in _points.size():
		if i < COLUMNS:
			continue
		var row := i / COLUMNS
		var flutter := sin(_clock * 7.0 + row * 0.9 + (i % COLUMNS) * 1.7) * 0.5 + 0.5
		var force := GRAVITY + wind * (0.4 + 0.6 * flutter) * (float(row) / (ROWS - 1))
		var current := _points[i]
		var next := current + (current - _previous[i]) * DAMPING + force * delta * delta
		_previous[i] = current
		_points[i] = next
	for iteration in ITERATIONS:
		for column in COLUMNS:
			_points[column] = chest * _rest[column]
		for k in _links.size():
			var link := _links[k]
			var a := _points[link.x]
			var b := _points[link.y]
			var gap := b - a
			var distance := gap.length()
			var rest := _link_length[k] * scale_factor
			if distance < 0.0001 or (link.z < 100 and distance > rest):
				# Bend links only push apart; they never pull the cloth taut.
				continue
			var correction := gap * ((distance - rest) / distance) * 0.5 * (link.z / 100.0)
			var a_pinned := link.x < COLUMNS
			var b_pinned := link.y < COLUMNS
			if a_pinned and b_pinned:
				continue
			if a_pinned:
				_points[link.y] = b - correction * 2.0
			elif b_pinned:
				_points[link.x] = a + correction * 2.0
			else:
				_points[link.x] = a + correction
				_points[link.y] = b - correction
		for i in range(COLUMNS, _points.size()):
			var p := _points[i]
			for sphere: Array in colliders:
				var center: Vector3 = sphere[0]
				var radius: float = sphere[1]
				var offset := p - center
				if offset.length_squared() < radius * radius:
					# Pushed out without being flung: the push moves the particle's history too,
					# so a heel kicking up behind a sprint parts the cloth instead of launching it.
					var pushed := center + offset.normalized() * radius
					_previous[i] += pushed - p
					p = pushed
			if p.y < floor_y:
				p.y = floor_y
				# Friction: cloth lying on stone barely slides.
				_previous[i] = _previous[i].lerp(Vector3(p.x, _previous[i].y, p.z), 0.6)
			_points[i] = p


## Spheres around the back, hips and legs, in world space: [center, radius].
func _colliders(scale_factor: float) -> Array:
	var spheres := []
	var to_world := rig_skeleton.global_transform
	for entry in [["Chest", Vector3(0, 0.12, 0.02), 0.2], ["Chest", Vector3(0, -0.06, 0.02), 0.19],
			["Pelvis", Vector3(0, 0.02, 0.0), 0.19], ["ThighL", Vector3(0, -0.12, 0), 0.1],
			["ThighR", Vector3(0, -0.12, 0), 0.1], ["ShinL", Vector3(0, -0.05, 0), 0.085],
			["ShinR", Vector3(0, -0.05, 0), 0.085], ["ShinL", Vector3(0, -0.3, 0), 0.07],
			["ShinR", Vector3(0, -0.3, 0), 0.07]]:
		var bone := rig_skeleton.find_bone(entry[0])
		if bone < 0:
			continue
		var pose := to_world * rig_skeleton.get_bone_global_pose(bone)
		spheres.append([pose * (entry[1] as Vector3), entry[2] * scale_factor])
	return spheres


func _process(_delta: float) -> void:
	if not _ready_to_draw:
		return
	var fraction := Engine.get_physics_interpolation_fraction()
	var shown := PackedVector3Array()
	shown.resize(_points.size())
	for i in _points.size():
		shown[i] = _rendered_from[i].lerp(_points[i], fraction)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material_override)
	for row in ROWS - 1:
		for column in COLUMNS - 1:
			var a := shown[row * COLUMNS + column]
			var b := shown[row * COLUMNS + column + 1]
			var c := shown[(row + 1) * COLUMNS + column]
			var d := shown[(row + 1) * COLUMNS + column + 1]
			_triangle(a, c, b)
			_triangle(b, c, d)
	_mesh.surface_end()


func _triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		_mesh.surface_set_normal(normal)
		_mesh.surface_add_vertex(v)
