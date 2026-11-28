extends Node3D
## The Thornwood: the first open stretch beyond the ruins. The eclipse ring sets the player
## down at a ring of standing stones by the forest edge; a dirt road winds two hundred metres
## through firs and old oaks, lit by lanterns on posts and staked torches, to a clearing with
## a bonfire where a spear stands driven through the ashes. Things wait in the trees and leap
## out onto the road as the player passes. Resting at the bonfire restores the hero, makes it
## the place to rise after a death, and brings the forest's foes back.
##
## Runs standalone (forest.tscn) or streamed into the expedition, in which case the host owns
## sky, sun and the player and calls setup(player, true).

signal rested
signal enemy_defeated(enemy: CharacterBody3D)
signal ambushed(at: Vector3)
signal foe_spawned(foe: CharacterBody3D)
## The player moved between the forest and the zones beyond it (crossing, belfry).
signal zone_changed(zone: StringName, title: String)

const World = preload("res://scenes/forest/forest_world.gd")
const Compositions = preload("res://scenes/forest/thornwood_compositions.gd")
const Crossing = preload("res://scenes/zones/crossing_area.gd")
const Belfry = preload("res://scenes/zones/belfry_area.gd")
const Props = preload("res://scenes/forest/forest_props.gd")
const NoirLighting = preload("res://scenes/fx/noir_lighting.gd")
const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const KINDS := {
	&"hollow": ["res://scenes/expedition/enemies/husk.tscn", "HOLLOW WOODSMAN", Color(0.28, 0.33, 0.22)],
	&"crawler": ["res://scenes/expedition/enemies/ghoul.tscn", "THORN CRAWLER", Color(0.22, 0.32, 0.2)],
	&"brute": ["res://scenes/expedition/enemies/brute.tscn", "BRAMBLE BRUTE", Color(0.3, 0.28, 0.2)],
}
## Ambushes along the road: trigger distance from the entrance (metres of road) and the foes
## that leap out, each [kind, side (-1 left, 1 right), metres ahead of the trigger].
const AMBUSHES := [
	[34.0, [[&"hollow", -1, 7.0], [&"hollow", 1, 9.0]]],
	[70.0, [[&"crawler", 1, 6.0], [&"crawler", 1, 9.0]]],
	[108.0, [[&"brute", -1, 8.0], [&"hollow", 1, 6.0]]],
	[146.0, [[&"crawler", -1, 6.0], [&"crawler", 1, 7.0], [&"hollow", -1, 10.0]]],
	[184.0, [[&"hollow", 1, 7.0], [&"crawler", -1, 8.0]]],
]
const LANTERN_SPACING := 15.0
const REST_DISTANCE := 2.6
const MOON_ENERGY := 2.1

var world: World
var bonfire_lit := false
## True once setup has finished building (a streamed forest takes a few seconds).
var built := false
var compositions
## The zones that continue the forest on foot south of the clearing.
var crossing: Crossing
var belfry: Belfry
## Where the player is: &"forest", &"crossing" or &"belfry".
var zone: StringName = &"forest"
## Where a fallen hero rises: the forest edge, the bonfire, or the belfry's mouth.
var checkpoint: StringName = &"entrance"
## Breakable props along the road (crates, barrels, the niche grate).
var props: Array = []
## Ambushes and the bonfire only respond while the player is in the forest (a streamed forest
## is built ahead of time while the player is still in the ruins).
var active := true
var _night: AudioStreamPlayer
var player: CharacterBody3D
var _streamed: bool
var _bonfire: Node3D
var _prompt: Label3D
## Per ambush: triggered, and the foes it spawned.
var _ambush_state: Array = []
var _enemies: Node3D
var _navigation: NavigationRegion3D


## Streamed, the forest builds a little each frame (await setup); standalone, all at once.
func setup(hero: CharacterBody3D, streamed: bool) -> void:
	player = hero
	_streamed = streamed
	if world == null:
		await _build(get_tree() if streamed else null)
	await reset_foes(streamed)
	_night = AudioStreamPlayer.new()
	_night.name = "NightAmbience"
	var loop := load("res://assets/audio/ambience/forest_night.ogg") as AudioStream
	if loop is AudioStreamOggVorbis:
		(loop as AudioStreamOggVorbis).loop = true
	_night.stream = loop
	_night.bus = &"Ambience"
	_night.volume_db = -3.0
	add_child(_night)
	set_active(active)
	built = true
	if not streamed:
		_make_sky()
	var accents := [to_global(Vector3(world.road_x(-30.0) - 9.0, 3.0, -30.0)), to_global(Vector3(world.road_x(-120.0) + 10.0, 3.5, -120.0))]
	if streamed:
		await get_tree().process_frame
	NoirLighting.apply(self, accents)
	if streamed:
		await get_tree().process_frame
	for light in find_children("*", "DirectionalLight3D", true, false):
		tune_moon(light)
	_tune_fires()


func _build(tree: SceneTree) -> void:
	world = World.new()
	compositions = Compositions.new(world, AMBUSHES)
	world.exclusions = compositions.exclusions()
	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	await world.build(ground, tree)
	props = await compositions.build(self, tree)
	_register_obstacles()
	_place_lights()
	if tree != null:
		await tree.process_frame
	_place_arrival()
	await _build_zones(tree)
	_bonfire = Props.bonfire()
	add_child(_bonfire)
	_attach_bonfire_fire()
	_bonfire.position = world.point(World.CLEARING.x, World.CLEARING.z)
	_prompt = Label3D.new()
	_prompt.name = "RestPrompt"
	_prompt.text = "E / A   Rest at the bonfire"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 40
	_prompt.pixel_size = 0.004
	_prompt.outline_size = 8
	_prompt.modulate = Color(1.0, 0.86, 0.62)
	_prompt.visible = false
	add_child(_prompt)
	_prompt.position = _bonfire.position + Vector3(0, 1.7, 0)
	_enemies = Node3D.new()
	_enemies.name = "Enemies"
	add_child(_enemies)
	_navigation = NavigationRegion3D.new()
	_navigation.name = "Navigation"
	add_child(_navigation)
	await _bake_navigation(tree)


## The crossing starts where the corridor leaves the clearing, level with it; the belfry where
## the crossing's stone steps end.
func _build_zones(tree: SceneTree) -> void:
	crossing = Crossing.new()
	crossing.name = "FloodedCrossing"
	add_child(crossing)
	crossing.position = world.point(World.CLEARING.x, World.MIN.y)
	belfry = Belfry.new()
	belfry.name = "BelfryUnderRoots"
	add_child(belfry)
	belfry.position = crossing.position + Crossing.EXIT
	for area in [crossing, belfry]:
		area.foe_spawned.connect(func(foe: CharacterBody3D) -> void: foe_spawned.emit(foe))
		area.enemy_defeated.connect(func(foe: CharacterBody3D) -> void: enemy_defeated.emit(foe))
		await area.prepare(player, tree != null)


## The moon of the Thornwood: high, cold and strong, so the canopy throws hard shadows and the
## firelight pools read hot against blue.
static func tune_moon(light: DirectionalLight3D) -> void:
	light.light_color = Color(0.5, 0.64, 1.0)
	light.light_energy = MOON_ENERGY
	light.rotation_degrees = Vector3(-58, 24, 0)
	light.shadow_enabled = true
	light.shadow_opacity = 1.0
	light.directional_shadow_max_distance = 42.0


## Fire against moonlight: firelight here burns hotter and reaches further than the noir
## pass's defaults, so each lantern is a warm island in the blue.
func _tune_fires() -> void:
	for light in find_children("*", "OmniLight3D", true, false):
		var lamp := light as OmniLight3D
		if lamp.name.begins_with("Lamp"):
			lamp.light_color = Color(1.0, 0.6, 0.26)
			lamp.light_energy = 9.0
			lamp.omni_range = 8.5
			lamp.omni_attenuation = 1.2
		elif lamp.name.begins_with("WatchFire"):
			lamp.light_color = Color(1.0, 0.5, 0.18)
			lamp.light_energy = 8.0
			lamp.omni_range = 7.5
			lamp.omni_attenuation = 1.1
	for flicker in find_children("Flicker", "Node", true, false):
		flicker.set_base_energy((flicker.get_parent() as Light3D).light_energy)


static func environment() -> Environment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.015, 0.02, 0.06)
	sky_material.sky_horizon_color = Color(0.07, 0.12, 0.24)
	sky_material.sky_curve = 0.2
	sky_material.ground_horizon_color = Color(0.05, 0.08, 0.14)
	sky_material.ground_bottom_color = Color(0.01, 0.015, 0.03)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.24, 0.48)
	env.ambient_light_energy = 0.17
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.09, 0.18)
	env.fog_light_energy = 1.0
	env.fog_density = 0.034
	env.fog_sky_affect = 0.9
	env.fog_aerial_perspective = 0.3
	env.fog_height = 0.6
	env.fog_height_density = 0.18
	return env


func _make_sky() -> void:
	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = environment()
	add_child(holder)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	add_child(moon)


# ---------------------------------------------------------------- lights and landmarks

## Authored solids join the navigation's obstacle list (the cart, the great oak, the niche,
## props), so foes path around them; breaking a prop does not rebake.
func _register_obstacles() -> void:
	for body in get_node(^"Compositions").find_children("*", "StaticBody3D", true, false):
		var holder := body.get_child(0) as CollisionShape3D if body.get_child_count() > 0 else null
		if holder == null:
			continue
		var at := (body as Node3D).global_position - global_position
		var size := Vector3.ONE * 0.6
		if holder.shape is BoxShape3D:
			size = (holder.shape as BoxShape3D).size
		elif holder.shape is CylinderShape3D:
			size = Vector3.ONE * (holder.shape as CylinderShape3D).radius * 2.0
		world.trunks.append(Vector4(at.x, world.height(at.x, at.z), at.z, maxf(size.x, size.z) * 0.5))
	for prop in props:
		var at: Vector3 = prop.position
		world.trunks.append(Vector4(at.x, world.height(at.x, at.z), at.z, 0.45))


func _place_lights() -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	add_child(lights)
	var index := 0
	# The first lantern stands ten metres past the arrival stones and shows where the road goes.
	var travelled := 24.0
	var side := 1.0
	while travelled < world.road.size() - 18.0:
		var at: Vector3 = world.road[int(travelled)]
		var ahead: Vector3 = world.road[mini(int(travelled) + 2, world.road.size() - 1)]
		var along := (ahead - at).normalized()
		var across := along.cross(Vector3.UP).normalized() * side
		var lantern := Props.lantern(index)
		lights.add_child(lantern)
		var foot := at + across * 2.6
		lantern.position = world.point(foot.x, foot.z)
		# The arm reaches over the road.
		lantern.look_at(lantern.position - across.cross(Vector3.UP), Vector3.UP)
		index += 1
		side = -side
		travelled += LANTERN_SPACING
	# Torches mark the bends and frame the forest gate and the clearing.
	var torch_points := []
	for k in [3, 5, 7, 9]:
		var bend: Vector3 = World.ROAD_POINTS[k]
		var outward := 1.0 if bend.x < World.ROAD_POINTS[k - 1].x else -1.0
		torch_points.append(Vector3(world.road_x(bend.z) + outward * 2.9, 0, bend.z))
	for side_x in [-2.6, 2.6]:
		torch_points.append(Vector3(world.road_x(-2.0) + side_x, 0, -2.0))
	for k in 6:
		var angle := TAU * k / 6.0 + 0.5
		torch_points.append(World.CLEARING + Vector3(cos(angle), 0, sin(angle)) * (World.CLEARING_RADIUS - 1.5))
	for i in torch_points.size():
		var torch := Props.torch(i)
		lights.add_child(torch)
		torch.position = world.point(torch_points[i].x, torch_points[i].z)


## The far end of the eclipse: a ring of standing stones the player steps out of, dimly alight.
func _place_arrival() -> void:
	var arrival := Node3D.new()
	arrival.name = "ArrivalStones"
	add_child(arrival)
	var center := world.point(world.road_x(6.0), 6.0)
	arrival.position = center
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var stone := Color(0.2, 0.21, 0.23)
	# Stones stand to either side and a little ahead; straight behind stays open for the camera.
	for angle_deg in [-25.0, -60.0, -120.0, -155.0, 35.0, 145.0]:
		var angle := deg_to_rad(angle_deg)
		var at := Vector3(cos(angle) * 3.6, -0.1, sin(angle) * 3.6)
		Props.frustum(tool, at, 0.42, 0.28, rng.randf_range(1.9, 3.0), 5, stone.darkened(0.4), stone, rng.randf() * TAU)
	var ring := MeshInstance3D.new()
	tool.generate_normals()
	ring.mesh = tool.commit()
	ring.material_override = Props.vertex_material()
	arrival.add_child(ring)
	var glow := OmniLight3D.new()
	glow.name = "EclipseGlow"
	glow.light_color = Color(0.55, 0.42, 1.0)
	glow.light_energy = 2.2
	glow.omni_range = 6.0
	arrival.add_child(glow)
	glow.position = Vector3(0, 1.6, 0.0)


## Ground, collision, spawn: the player can be placed here.
func entry_ready() -> bool:
	return built


## Navigation baked: foes can land and hunt. Ambushes wait for it.
func combat_ready() -> bool:
	return built and has_meta(&"navigation_ready")


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		for area in [crossing, belfry]:
			if area != null and area.prepared:
				area.deactivate()
	if not on and get_node_or_null(^"/root/Weather") != null:
		get_node(^"/root/Weather").local_rain = 0.0
	if _night != null:
		if on and not _night.playing:
			_night.play()
		elif not on:
			_night.stop()


func entrance_transform() -> Transform3D:
	var at := world.point(world.road_x(6.0), 6.0) + Vector3(0, 0.05, 0)
	return global_transform * Transform3D(Basis.IDENTITY, at)


func bonfire_transform() -> Transform3D:
	var at := world.point(World.CLEARING.x, World.CLEARING.z + 2.4) + Vector3(0, 0.05, 0)
	return global_transform * Transform3D(Basis.IDENTITY, at)


func respawn_transform() -> Transform3D:
	if checkpoint == &"belfry" and belfry != null:
		return belfry.respawn_transform()
	return bonfire_transform() if bonfire_lit else entrance_transform()


func zone_title() -> String:
	match zone:
		&"crossing": return crossing.title
		&"belfry": return belfry.title
	return "THE THORNWOOD"


# ---------------------------------------------------------------- navigation

func _bake_navigation(tree: SceneTree) -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.5
	mesh.agent_max_climb = 0.5
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	var data: NavigationMeshSourceGeometryData3D = await world.navigation_source(tree)
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, data, _navigation_baked.bind(mesh))


func _navigation_baked(mesh: NavigationMesh) -> void:
	if not is_inside_tree() or mesh.get_polygon_count() == 0:
		return
	# Recast floats the mesh a cell or two above uneven ground; snap it back onto the terrain
	# and drop islands on top of trunks, rocks and bounds.
	var vertices := mesh.vertices
	var lifted := PackedByteArray()
	lifted.resize(vertices.size())
	var slice := Time.get_ticks_usec()
	for i in vertices.size():
		var ground := world.height(vertices[i].x, vertices[i].z)
		lifted[i] = 1 if vertices[i].y - ground > 1.2 else 0
		vertices[i].y = ground
		if i % 500 == 0 and Time.get_ticks_usec() - slice > 3500:
			# Spread over frames: this runs on the main thread.
			await get_tree().process_frame
			slice = Time.get_ticks_usec()
			if not is_inside_tree():
				return
	var settled := NavigationMesh.new()
	settled.cell_size = mesh.cell_size
	settled.cell_height = mesh.cell_height
	settled.agent_radius = mesh.agent_radius
	settled.agent_height = mesh.agent_height
	settled.agent_max_climb = mesh.agent_max_climb
	settled.vertices = vertices
	for p in mesh.get_polygon_count():
		var polygon := mesh.get_polygon(p)
		var keep := true
		for index in polygon:
			if lifted[index] == 1:
				keep = false
				break
		if keep:
			settled.add_polygon(polygon)
	_navigation.navigation_mesh = settled
	set_meta(&"navigation_ready", true)


# ---------------------------------------------------------------- foes and ambushes

func enemies() -> Array[Node]:
	return _enemies.get_children()


func engaged() -> bool:
	if not built:
		return false
	for area in [crossing, belfry]:
		if area != null and area.active and area.engaged():
			return true
	return enemies().any(func(enemy: Node) -> bool: return enemy.visible and enemy.is_engaged())


## Clears every foe and sets all ambushes again, each foe hidden in the trees.
func reset_foes(paced: bool = false) -> void:
	for area in [crossing, belfry]:
		if area != null and area.prepared:
			area.reset_foes()
	for prop in props:
		if is_instance_valid(prop):
			prop.reset()
	for foe in _enemies.get_children():
		foe.queue_free()
		_enemies.remove_child(foe)
	_ambush_state.clear()
	for ambush: Array in AMBUSHES:
		var foes := []
		for spec: Array in ambush[1]:
			foes.append(_spawn_hidden(ambush[0], spec))
			if paced:
				await get_tree().process_frame
		_ambush_state.append([false, foes])


func _spawn_hidden(trigger: float, spec: Array) -> CharacterBody3D:
	var kind: Array = KINDS[spec[0]]
	var foe: CharacterBody3D = load(kind[0]).instantiate()
	foe.title = kind[1]
	foe.player = player
	foe.ai_enabled = false
	foe.leash = 30.0
	foe.notice_distance = 11.0
	_enemies.add_child(foe)
	var land_index := clampi(int(trigger + spec[2]), 0, world.road.size() - 1)
	var landing: Vector3 = world.road[land_index]
	var along: Vector3 = (world.road[mini(land_index + 2, world.road.size() - 1)] - landing).normalized()
	var across := along.cross(Vector3.UP).normalized() * float(spec[1])
	var hide := _hiding_spot(landing, across)
	foe.position = hide
	foe.get_node("Heading").rotation.y = atan2(across.x, across.z)
	foe.set_meta(&"landing", landing + across * 0.8)
	var rig := foe.get_node("Heading/Rig")
	if rig.has_method(&"tint"):
		rig.tint(kind[2], 0.45)
	foe.get_node("Combat").defeated.connect(func() -> void: enemy_defeated.emit(foe))
	_hide(foe, true)
	foe_spawned.emit(foe)
	return foe


## A spot six to nine metres into the trees with a clear leap onto the road.
func _hiding_spot(landing: Vector3, across: Vector3) -> Vector3:
	for depth in [7.5, 6.5, 8.5, 5.5, 9.5]:
		for slide in [0.0, 1.5, -1.5, 3.0, -3.0]:
			var along := across.cross(Vector3.UP)
			var flat: Vector3 = landing + across * depth + along * slide
			var spot := world.point(flat.x, flat.z)
			if _clear_leap(spot, landing):
				return spot
	var fallback := landing + across * 6.0
	return world.point(fallback.x, fallback.z)


func _clear_leap(from: Vector3, to: Vector3) -> bool:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	for trunk in world.trunks:
		var c := Vector2(trunk.x, trunk.z)
		if c.distance_to(a) > 12.0:
			continue
		var t := clampf((c - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
		if (a + (b - a) * t).distance_to(c) < trunk.w + 0.7:
			return false
	return true


func _hide(foe: CharacterBody3D, hidden: bool) -> void:
	foe.visible = not hidden
	foe.process_mode = Node.PROCESS_MODE_DISABLED if hidden else Node.PROCESS_MODE_INHERIT
	foe.get_node("LockPoint").visible = not hidden
	if hidden:
		foe.remove_from_group(&"foes")
	else:
		foe.add_to_group(&"foes")


func _physics_process(_delta: float) -> void:
	if not built or player == null or not active:
		return
	_track_zone()
	if zone != &"forest":
		return
	# Drizzle reaches the road in the open stretches; under the crowns it barely does.
	var weather := get_node_or_null(^"/root/Weather")
	if weather != null:
		var here := to_local(player.global_position)
		weather.local_rain = 0.16 if compositions.open_at(World.MAX.y - here.z) else 0.03
	var local := to_local(player.global_position)
	var progress := float(World.MAX.y - local.z)
	if world.road_distance(local.x, local.z) > 14.0:
		progress -= 6.0
	for i in AMBUSHES.size():
		if not combat_ready():
			break
		var state: Array = _ambush_state[i]
		# Only near the spot: a player resting further on does not set off every ambush behind.
		if state[0] or progress < AMBUSHES[i][0] or progress > AMBUSHES[i][0] + 25.0:
			continue
		state[0] = true
		_spring(state[1])
	_update_prompt()


## The foes of an ambush break from the trees and leap onto the road around the player.
func _spring(foes: Array) -> void:
	var delay := 0.0
	for foe: CharacterBody3D in foes:
		if not is_instance_valid(foe):
			continue
		get_tree().create_timer(delay, false, true).timeout.connect(_leap_out.bind(foe))
		delay += 0.35
	if not foes.is_empty() and is_instance_valid(foes[0]):
		ambushed.emit(foes[0].global_position)


func _leap_out(foe: CharacterBody3D) -> void:
	if not is_instance_valid(foe):
		return
	_hide(foe, false)
	foe.reset_physics_interpolation()
	foe.ai_enabled = true
	var landing: Vector3 = to_global(foe.get_meta(&"landing"))
	foe.leap_in(landing, 0.8)
	# Leaves and dirt thrown up where it breaks cover.
	RetroFX.dust(foe.global_position + Vector3.UP * 0.3, 16, 0.8)


# ---------------------------------------------------------------- bonfire

func _update_prompt() -> void:
	var near := player.global_position.distance_to(_bonfire.global_position) < REST_DISTANCE + 0.6
	_prompt.text = "E / A   Rest at the bonfire" if bonfire_lit else "E / A   Kindle the bonfire"
	_prompt.visible = near and not _threatened()


func can_rest() -> bool:
	return active and built and player != null and player.global_position.distance_to(_bonfire.global_position) < REST_DISTANCE + 0.6 and not _threatened()


## As in Souls games: no rest while a hunting foe is close to the fire.
func _threatened() -> bool:
	for foe in enemies():
		if foe.visible and foe.is_engaged() and foe.global_position.distance_to(_bonfire.global_position) < 18.0:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and can_rest():
		rest()
		get_viewport().set_input_as_handled()


func _track_zone() -> void:
	var next: StringName = &"forest"
	if belfry != null and belfry.contains(player.global_position):
		next = &"belfry"
	elif crossing != null and crossing.contains(player.global_position):
		next = &"crossing"
	if next == zone:
		return
	zone = next
	for area in [crossing, belfry]:
		if area == null or not area.prepared:
			continue
		if area == crossing and zone == &"crossing" or area == belfry and zone == &"belfry":
			area.activate()
		else:
			area.deactivate()
	var weather := get_node_or_null(^"/root/Weather")
	if weather != null:
		weather.local_rain = 0.0
		weather.set_preset(&"forest" if zone == &"forest" else (crossing.weather_preset if zone == &"crossing" else belfry.weather_preset))
	if zone == &"belfry":
		# The safe side of the belfry's mouth becomes the place to rise.
		checkpoint = &"belfry"
	zone_changed.emit(zone, zone_title())


## Kindles the bonfire on first use; every rest brings the forest's foes back.
func rest() -> void:
	checkpoint = &"bonfire"
	if not bonfire_lit:
		bonfire_lit = true
		kindle()
	reset_foes()
	rested.emit()


## Embers, the big flames and the sparks share one ignition: the fire component multiplies
## the light by it and lets the flames out once it has caught.
func kindle() -> void:
	var light := _bonfire.get_node("Fire/BonfireLight") as OmniLight3D
	var fire_light := light.get_node("Flicker")
	var tween := create_tween()
	tween.tween_property(fire_light, ^"ignition", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(light, ^"omni_range", 9.5, 1.2)


## An unlit bonfire smoulders: the same fire at a seventh of its strength.
func _attach_bonfire_fire() -> void:
	var light := _bonfire.get_node("Fire/BonfireLight") as OmniLight3D
	# A hot pool around the fire with a hard falloff, so the clearing's edge stays moonlit blue.
	light.omni_attenuation = 1.6
	var fire_light := preload("res://scenes/fx/fire_light.gd").new()
	fire_light.name = "Flicker"
	fire_light.profile = &"bonfire"
	light.add_child(fire_light)
	fire_light.set_base_energy(9.0)
	fire_light.ignition = 0.13
