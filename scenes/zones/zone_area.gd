extends Node3D
## A playable zone built from code: grey-box geometry in the project's materials, lights, foes,
## breakable props and navigation. Contract:
##
##   prepare(player, streamed)  build everything (awaitable; a few ms per frame when streamed)
##   activate() / deactivate()  local sound loops, fire processing and foes only while active
##   entrance_transform(), respawn_transform(), bounds  where the player arrives, rises, is
##
## Subclasses override _layout() to place geometry with box(), ramp(), stairs() and the rest,
## and fill FOES with [kind, local position, yaw].

signal foe_spawned(foe: CharacterBody3D)
signal enemy_defeated(enemy: CharacterBody3D)
signal _navigation_baked

const SetDressing = preload("res://scenes/environment/set_dressing.gd")
const Breakable = preload("res://scenes/environment/breakable_prop.gd")
const Props = preload("res://scenes/forest/forest_props.gd")
const NoirLighting = preload("res://scenes/fx/noir_lighting.gd")
const ENEMY_SCENES := {
	&"spearman": "res://scenes/expedition/enemies/spearman.tscn",
	&"shieldbearer": "res://scenes/expedition/enemies/shieldbearer.tscn",
	&"husk": "res://scenes/expedition/enemies/husk.tscn",
	&"ghoul": "res://scenes/expedition/enemies/ghoul.tscn",
	&"brute": "res://scenes/expedition/enemies/brute.tscn",
}

## Zone id for prop ids and the HUD; its weather preset; its title.
var zone_id := "zone"
var weather_preset: StringName = &"forest"
var title := "ZONE"
## Local AABB the player is "in" this zone.
var bounds := AABB()
var player: CharacterBody3D
var active := false
var prepared := false
var props: Array = []
var foes_spec: Array = []
var entry_local := Vector3.ZERO
var respawn_local := Vector3.ZERO
var _geometry: StaticBody3D
var _visual: Node3D
var _enemies: Node3D
var _navigation: NavigationRegion3D
var _loops: Array[Node] = []
## Particles that drift only while the zone is active (mist, fireflies, dust).
var _ambient: Array[CPUParticles3D] = []
var _materials := {}


func prepare(hero: CharacterBody3D, streamed: bool) -> void:
	player = hero
	if prepared:
		return
	_geometry = StaticBody3D.new()
	_geometry.name = "Geometry"
	_geometry.collision_layer = 1
	_geometry.collision_mask = 0
	add_child(_geometry)
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_enemies = Node3D.new()
	_enemies.name = "Enemies"
	add_child(_enemies)
	_layout()
	if streamed:
		await get_tree().process_frame
	_detail_nodes()
	await _build_detail(streamed)
	if streamed:
		await get_tree().process_frame
		await get_tree().process_frame
	_navigation = NavigationRegion3D.new()
	_navigation.name = "Navigation"
	add_child(_navigation)
	await _bake_navigation(streamed)
	if streamed:
		await get_tree().process_frame
	await reset_foes(streamed)
	NoirLighting.toon(self)
	for flicker in find_children("Flicker", "Node", true, false):
		flicker.set_base_energy((flicker.get_parent() as Light3D).light_energy)
	prepared = true
	deactivate()


func _layout() -> void:
	pass


## Lights, solid pieces and particles that go with the detail pass (main thread).
func _detail_nodes() -> void:
	pass


## Detail geometry as [[ZoneDetail builder, region name], ...]. Pure geometry with no scene
## access: it runs on a worker thread when the zone is streamed.
func _detail_regions() -> Array:
	return []


func _bake_regions() -> Array:
	var regions := _detail_regions()
	for region: Array in regions:
		region[0].bake()
	return regions


## Builds the detail off the main thread when streamed (tens of milliseconds of geometry), then
## hands the finished meshes to the scene one region per frame.
func _build_detail(streamed: bool) -> void:
	var regions: Array = []
	if streamed:
		var task := WorkerThreadPool.add_task(func() -> void: regions.append_array(_bake_regions()))
		while not WorkerThreadPool.is_task_completed(task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
	else:
		regions = _bake_regions()
	for region: Array in regions:
		if not is_inside_tree():
			return
		region[0].attach(_visual, region[1])
		if streamed:
			await get_tree().process_frame


func activate() -> void:
	active = true
	for loop in _loops:
		if loop is AudioStreamPlayer3D and not loop.playing:
			loop.play()
	for air in _ambient:
		air.emitting = true
		air.visible = true
	for foe in enemies():
		foe.ai_enabled = true


func deactivate() -> void:
	active = false
	for loop in _loops:
		if loop is AudioStreamPlayer3D:
			loop.stop()
	for air in _ambient:
		air.emitting = false
		air.visible = false
	for foe in enemies():
		foe.ai_enabled = false


func contains(global_point: Vector3) -> bool:
	return bounds.has_point(to_local(global_point))


func entrance_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, entry_local + Vector3(0, 0.05, 0))


func respawn_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, respawn_local + Vector3(0, 0.05, 0))


func enemies() -> Array[Node]:
	return _enemies.get_children() if _enemies != null else []


func engaged() -> bool:
	return enemies().any(func(foe: Node) -> bool: return foe.is_engaged())


## Brings foes back to their posts and puts broken crates and barrels together again.
func reset_foes(paced: bool = false) -> void:
	for prop in props:
		if is_instance_valid(prop):
			prop.reset()
	for foe in enemies():
		foe.queue_free()
		_enemies.remove_child(foe)
	for spec: Array in foes_spec:
		var foe: CharacterBody3D = load(ENEMY_SCENES[spec[0]]).instantiate()
		foe.player = player
		foe.ai_enabled = active
		foe.leash = 14.0
		foe.notice_distance = 9.0
		_enemies.add_child(foe)
		foe.position = spec[1]
		foe.get_node("Heading").rotation.y = spec[2]
		if spec.size() > 3 and foe.get_node("Heading/Rig").has_method(&"tint"):
			foe.get_node("Heading/Rig").tint(spec[3], 0.4)
		foe.get_node("Combat").defeated.connect(func() -> void: enemy_defeated.emit(foe))
		foe_spawned.emit(foe)
		if paced:
			# A body with its rig takes several milliseconds: one per frame while streaming.
			await get_tree().process_frame


# ---------------------------------------------------------------- building blocks

func material(key: String, color: Color, roughness: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	if not _materials.has(key):
		var made := StandardMaterial3D.new()
		made.albedo_color = color
		made.roughness = roughness
		made.metallic = metal
		_materials[key] = made
	return _materials[key]


func stone() -> Material:
	return SetDressing.DARK_STONE


func wood() -> StandardMaterial3D:
	return material("wood", Color(0.24, 0.18, 0.13))


## A solid box: collision plus a visible block (pass null for an invisible wall).
func box(center: Vector3, size: Vector3, mat: Material, yaw: float = 0.0, solid: bool = true) -> MeshInstance3D:
	if solid:
		var holder := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		holder.shape = shape
		_geometry.add_child(holder)
		holder.position = center
		holder.rotation.y = yaw
	if mat == null:
		return null
	var mesh := BoxMesh.new()
	mesh.size = size
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = mat
	_visual.add_child(view)
	view.position = center
	view.rotation.y = yaw
	return view


## A sloped slab from `from` to `to` (centres of its top edge ends), width across.
func ramp(from: Vector3, to: Vector3, width: float, thickness: float, mat: Material) -> void:
	var run := to - from
	var length := run.length()
	var basis := Basis.looking_at(run.normalized(), Vector3.UP)
	var center := (from + to) * 0.5 - basis.y * thickness * 0.5
	var holder := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, length)
	holder.shape = shape
	_geometry.add_child(holder)
	holder.transform = Transform3D(basis, center)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = mat
	_visual.add_child(view)
	view.transform = holder.transform


## Steps from `from` (bottom front) climbing `rise` over `run` toward `direction`, width wide.
func stairs(from: Vector3, direction: Vector3, run: float, rise: float, width: float, steps: int, mat: Material) -> void:
	direction = direction.normalized()
	var yaw := atan2(direction.x, direction.z)
	for i in steps:
		var depth := run / steps
		var height := rise * (i + 1) / steps
		var center := from + direction * depth * (i + 0.5) + Vector3(0, height * 0.5, 0)
		box(center, Vector3(width, height, depth), mat, yaw)
	# A hidden ramp under the steps so bodies glide up instead of snagging on each riser.
	var low := from + Vector3(0, 0.02, 0)
	var high := from + direction * run + Vector3(0, rise, 0)
	var holder := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var length := (high - low).length()
	shape.size = Vector3(width, 0.1, length)
	holder.shape = shape
	_geometry.add_child(holder)
	holder.transform = Transform3D(Basis.looking_at((high - low).normalized(), Vector3.UP), (low + high) * 0.5 - Vector3(0, 0.05, 0))


func lamp(at: Vector3, energy: float, reach: float, color: Color, profile: StringName, name_prefix: String = "Lamp") -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "%s%d" % [name_prefix, get_child_count()]
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.2
	add_child(light)
	light.position = at
	if profile != &"":
		var fire := preload("res://scenes/fx/fire_light.gd").new()
		fire.name = "Flicker"
		fire.profile = profile
		light.add_child(fire)
	return light


func cold_light(at: Vector3, energy: float, reach: float, color: Color) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Cold%d" % get_child_count()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)
	light.position = at
	return light


func breakable(kind: StringName, id: String, at: Vector3, yaw: float) -> Node3D:
	var prop := Breakable.new()
	prop.kind = kind
	prop.prop_id = "%s/%s" % [zone_id, id]
	prop.name = id.replace("/", "_")
	add_child(prop)
	prop.position = at
	prop.rotation.y = yaw
	props.append(prop)
	return prop


func loop_sound(path: String, at: Vector3, volume_db: float, unit_size: float = 8.0) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	voice.stream = stream
	voice.bus = &"Ambience"
	voice.unit_size = unit_size
	voice.max_distance = 40.0
	voice.volume_db = volume_db
	add_child(voice)
	voice.position = at
	_loops.append(voice)
	return voice


func ambient(air: CPUParticles3D) -> CPUParticles3D:
	add_child(air)
	_ambient.append(air)
	return air


func dress(at: Vector3, entries: Array, seed: int) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.position = at
	SetDressing.dress(holder, entries, seed)


# ---------------------------------------------------------------- navigation

## Bakes from this zone's static colliders, then sets every vertex back onto the surface below
## it: Recast floats meshes a cell or two up, and agents compare waypoints in 3D.
func _bake_navigation(streamed: bool = false) -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.5
	mesh.agent_max_climb = 0.5
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, data, self)
	if streamed:
		# On a worker thread while the player is elsewhere; this frame stays light.
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, data, func() -> void: _navigation_baked.emit.call_deferred())
		await _navigation_baked
	else:
		NavigationServer3D.bake_from_source_geometry_data(mesh, data)
	if mesh.get_polygon_count() == 0:
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var vertices := mesh.vertices
	var hanging := PackedByteArray()
	hanging.resize(vertices.size())
	for i in vertices.size():
		var top := to_global(vertices[i] + Vector3(0, 0.3, 0))
		var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -2.5, 0), 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			hanging[i] = 1
		else:
			vertices[i] = to_local(hit.position)
	var settled := NavigationMesh.new()
	settled.cell_size = mesh.cell_size
	settled.cell_height = mesh.cell_height
	settled.agent_radius = mesh.agent_radius
	settled.agent_height = mesh.agent_height
	settled.agent_max_climb = mesh.agent_max_climb
	settled.vertices = vertices
	for p in mesh.get_polygon_count():
		var polygon := mesh.get_polygon(p)
		if Array(polygon).all(func(i: int) -> bool: return hanging[i] == 0):
			settled.add_polygon(polygon)
	_navigation.navigation_mesh = settled
	set_meta(&"navigation_ready", true)
