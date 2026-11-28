extends RefCounted
## Authored groups along the Thornwood road, placed by distance along the road from the
## arrival stones (ARRIVAL metres from the map's north edge). Each group has an anchor, a side
## and an offset, a radius kept clear of generated growth, and its interactions. Nothing here
## stands within 3 m of an ambush landing, the arrival point or the bonfire.
##
##   0-18 m    arrival: wet stones, drips from the crowns, one lantern ahead
##   18-55 m   patrol trail: a post with a rag in the wind, a lean-to with crates
##   55-95 m   dead oak: a pocket off the road, a glowing stump, a niche behind a rotten grate
##   95-140 m  lowland: puddles, fallen branches, dripping canopy, drizzle in the open
##   140-195 m abandoned convoy: a cart run into a ditch beside a fallen trunk, cargo to break
##   end       clearing: wet stones, someone else's cold camp, one violet echo at the edge

const SetDressing = preload("res://scenes/environment/set_dressing.gd")
const Props = preload("res://scenes/forest/forest_props.gd")
const Breakable = preload("res://scenes/environment/breakable_prop.gd")
const WindRag = preload("res://scenes/forest/wind_rag.gd")

## Road index (metres from the map's north edge) of the arrival stones. Every anchor below is
## metres of road from there.
const ARRIVAL := 12
const PATROL_POST := Vector3i(36, -1, 32)   # [metres from arrival, side, offset in dm]
const LEAN_TO := 44
const OAK_POCKET := 75
const LOWLAND := Vector2i(95, 140)
const CONVOY := 160
## Open stretches (metres from arrival) where drizzle reaches the road.
const OPEN_STRETCHES := [Vector2(-12, 20), Vector2(95, 140), Vector2(210, 260)]

var world
var ambushes: Array


func _init(forest_world, ambush_list: Array) -> void:
	world = forest_world
	ambushes = ambush_list


## A point beside the road: index metres from the north edge, side -1 left / 1 right.
func beside(index: float, side: float, offset: float) -> Vector3:
	var i := clampi(int(index), 0, world.road.size() - 2)
	var at: Vector3 = world.road[i]
	var along: Vector3 = (world.road[i + 1] - at).normalized()
	var across := along.cross(Vector3.UP).normalized() * side
	var flat := at + across * offset
	return world.point(flat.x, flat.z)


func facing_road(index: float, side: float) -> float:
	var i := clampi(int(index), 0, world.road.size() - 2)
	var along: Vector3 = (world.road[i + 1] - world.road[i]).normalized()
	var across := along.cross(Vector3.UP).normalized() * side
	return atan2(across.x, across.z)


func exclusions() -> Array[Vector3]:
	var zones: Array[Vector3] = []
	var add := func(p: Vector3, r: float) -> void: zones.append(Vector3(p.x, p.z, r))
	add.call(beside(ARRIVAL + PATROL_POST.x, PATROL_POST.y, 3.2), 1.0)
	add.call(beside(ARRIVAL + LEAN_TO, 1, 5.5), 2.6)
	var pocket := beside(ARRIVAL + OAK_POCKET, -1, 14.0)
	add.call(pocket, 7.0)
	for offset in [5.5, 8.0, 10.5]:
		add.call(beside(ARRIVAL + OAK_POCKET + 2, -1, offset), 2.4)
	add.call(beside(ARRIVAL + CONVOY, 1, 6.5), 5.5)
	# The way south out of the clearing, kept open to the edge of the map.
	var z: float = world.CLEARING.z - world.CLEARING_RADIUS
	while z > world.MIN.y - 1.0:
		zones.append(Vector3(world.CLEARING.x, z, world.EXIT_HALF + 1.0))
		z -= 2.0
	# Fighting room around every ambush landing: a pocket 5-7 m across beside the road.
	for ambush: Array in ambushes:
		for spec: Array in ambush[1]:
			add.call(beside(ambush[0] + spec[2], spec[1], 4.5), 3.0)
	return zones


## Builds every group under root (the forest area) and returns the breakable props. With a
## tree, one group per frame (await it).
func build(root: Node3D, tree: SceneTree = null) -> Array:
	var holder := Node3D.new()
	holder.name = "Compositions"
	root.add_child(holder)
	var props: Array = []
	for step in [_arrival.bind(holder), _patrol.bind(holder, props), _dead_oak.bind(holder, props),
			_lowland.bind(holder), _convoy.bind(holder, props), _clearing.bind(holder)]:
		step.call()
		if tree != null:
			await tree.process_frame
	return props


func _glossy(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.12
	material.metallic = 0.25
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return material


func _disc(parent: Node3D, at: Vector3, radius: float, material: Material, squash := Vector2.ONE) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.03
	mesh.radial_segments = 8
	disc.mesh = mesh
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(disc)
	disc.position = at + Vector3(0, 0.03, 0)
	disc.scale = Vector3(squash.x, 1, squash.y)
	disc.rotation.y = at.x * 1.7


func _breakable(parent: Node3D, kind: StringName, id: String, at: Vector3, yaw: float, props: Array) -> Node3D:
	var prop := Breakable.new()
	prop.kind = kind
	prop.prop_id = "thornwood/" + id
	prop.name = id.replace("/", "_")
	parent.add_child(prop)
	prop.position = at
	prop.rotation.y = yaw
	props.append(prop)
	return prop


func _arrival(holder: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Arrival"
	holder.add_child(group)
	var wet := _glossy(Color(0.13, 0.14, 0.16))
	for k in 7:
		var side := -1.0 if k % 2 == 0 else 1.0
		_disc(group, beside(ARRIVAL + k * 2.5 - 4, side, 1.0 + (k % 3) * 0.6), 0.5 + (k % 3) * 0.2, wet, Vector2(1.3, 0.8))
	# Drops falling from the crowns around the stones.
	var drops := CPUParticles3D.new()
	drops.name = "CanopyDrops"
	drops.amount = 24
	drops.lifetime = 1.1
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(5, 0.2, 5)
	drops.gravity = Vector3(0, -14, 0)
	drops.initial_velocity_min = 0.0
	drops.initial_velocity_max = 0.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.015, 0.14)
	var glint := StandardMaterial3D.new()
	glint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	glint.albedo_color = Color(0.6, 0.7, 0.9, 0.5)
	glint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = glint
	drops.mesh = mesh
	group.add_child(drops)
	drops.position = beside(ARRIVAL, 0, 0) + Vector3(0, 6.5, 0)


func _patrol(holder: Node3D, props: Array) -> void:
	var group := Node3D.new()
	group.name = "PatrolTrail"
	holder.add_child(group)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var wood := Color(0.22, 0.17, 0.12)
	# The patrol's old marker post, a rag tied at the top.
	var post := beside(ARRIVAL + PATROL_POST.x, PATROL_POST.y, 3.2)
	Props.frustum(tool, post, 0.07, 0.06, 2.1, 5, wood.darkened(0.3), wood)
	Props.frustum(tool, post + Vector3(0, 1.85, 0), 0.04, 0.04, 0.5, 4, wood, wood, 0.0, Vector3(0.45, -0.5, 0))
	# A lean-to of two forked posts and a slanted roof of boards, crates kept dry beneath.
	var shelter := beside(ARRIVAL + LEAN_TO, 1, 5.6)
	var yaw := facing_road(ARRIVAL + LEAN_TO, 1)
	var basis := Basis(Vector3.UP, yaw)
	for side in [-1.0, 1.0]:
		Props.frustum(tool, shelter + basis * Vector3(side * 1.0, 0, -0.6), 0.06, 0.05, 1.9, 5, wood.darkened(0.3), wood)
	for k in 5:
		var board := basis * Vector3(-1.1 + k * 0.55, 1.75, -0.6)
		Props.frustum(tool, shelter + board, 0.12, 0.12, 0.06, 4, wood, wood.darkened(0.2), yaw + PI * 0.25, basis * Vector3(0, -0.7, 1.4))
	tool.generate_normals()
	var structures := MeshInstance3D.new()
	structures.name = "Structures"
	structures.mesh = tool.commit()
	structures.material_override = Props.vertex_material()
	group.add_child(structures)
	var rag := WindRag.new()
	rag.name = "PatrolRag"
	group.add_child(rag)
	rag.position = post + Vector3(0, 2.0, 0)
	_breakable(group, &"crate", "patrol/crate_0", shelter + basis * Vector3(-0.4, 0, 0.1), yaw + 0.2, props)
	_breakable(group, &"crate", "patrol/crate_1", shelter + basis * Vector3(0.45, 0, -0.1), yaw - 0.35, props)


func _dead_oak(holder: Node3D, props: Array) -> void:
	var group := Node3D.new()
	group.name = "DeadOak"
	holder.add_child(group)
	var pocket := beside(ARRIVAL + OAK_POCKET, -1, 14.0)
	var yaw := facing_road(ARRIVAL + OAK_POCKET, -1)
	var basis := Basis(Vector3.UP, yaw)
	# The great dead oak at the back of the pocket, leaning, its fork against the sky.
	var oak := MeshInstance3D.new()
	oak.name = "GreatSnag"
	oak.mesh = Props.snag(31)
	oak.material_override = Props.vertex_material()
	group.add_child(oak)
	oak.position = pocket + basis * Vector3(0, -0.2, 3.5)
	oak.scale = Vector3.ONE * 2.2
	oak.rotation = Vector3(0.12, yaw, -0.08)
	var trunk := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.7
	cylinder.height = 6.0
	shape.shape = cylinder
	trunk.add_child(shape)
	group.add_child(trunk)
	trunk.position = oak.position + Vector3(0, 3.0, 0)
	# A stump with faintly glowing caps: seen up close, lighting nothing around it.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var stump_at := pocket + basis * Vector3(-2.4, 0, 0.5)
	Props.frustum(tool, stump_at - Vector3(0, 0.1, 0), 0.55, 0.45, 0.6, 7, Color(0.2, 0.16, 0.12), Color(0.3, 0.24, 0.17))
	# The niche: three walls of stone under the oak's roots, opening toward the road.
	var niche := pocket + basis * Vector3(2.6, 0, 1.2)
	for wall in [[Vector3(-0.95, 0, 0.75), Vector3(0.25, 1.7, 1.6)], [Vector3(0.95, 0, 0.75), Vector3(0.25, 1.7, 1.6)], [Vector3(0, 0, 1.5), Vector3(2.1, 1.7, 0.25)], [Vector3(0, 1.7, 0.75), Vector3(2.1, 0.25, 1.75)]]:
		var center: Vector3 = niche + basis * (wall[0] as Vector3)
		var size: Vector3 = wall[1]
		var body := StaticBody3D.new()
		var holder_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		holder_shape.shape = box
		body.add_child(holder_shape)
		group.add_child(body)
		body.position = center + Vector3(0, size.y * 0.5, 0)
		body.rotation.y = yaw
		var block := MeshInstance3D.new()
		var block_mesh := BoxMesh.new()
		block_mesh.size = size
		block.mesh = block_mesh
		block.material_override = SetDressing.DARK_STONE
		body.add_child(block)
	tool.generate_normals()
	var stump := MeshInstance3D.new()
	stump.name = "Stump"
	stump.mesh = tool.commit()
	stump.material_override = Props.vertex_material()
	group.add_child(stump)
	var caps := MeshInstance3D.new()
	caps.name = "StumpCaps"
	caps.mesh = Props.mushrooms(44)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.albedo_color = Color(0.8, 0.8, 0.8)
	caps.material_override = glow
	group.add_child(caps)
	caps.position = stump_at + Vector3(0, 0.5, 0)
	# A slow 3-6 % breathing of the glow, its own phase.
	var breathe := caps.create_tween().set_loops()
	breathe.tween_property(glow, ^"albedo_color", Color(0.85, 0.85, 0.85), 2.1).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(glow, ^"albedo_color", Color(0.8, 0.8, 0.8), 2.1).set_trans(Tween.TRANS_SINE)
	# Inside the niche: what a lost patrolman left, and the caps that grew over it.
	var relic := Node3D.new()
	relic.name = "NicheRelic"
	group.add_child(relic)
	relic.position = niche + basis * Vector3(0, 0, 0.9)
	SetDressing.dress(relic, [{"kind": "bones", "at": Vector3.ZERO, "radius": 0.45, "count": 5, "skulls": 1}], 17)
	var grate := _breakable(group, &"grate", "dead_oak/niche_grate", niche + basis * Vector3(0, 0, -0.05), yaw, props)
	grate.set_meta(&"keeps_open", true)


func _lowland(holder: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Lowland"
	holder.add_child(group)
	var puddle := _glossy(Color(0.05, 0.06, 0.08))
	for k in 9:
		var index := LOWLAND.x + 6 + k * 4.5
		var side := -1.0 if k % 3 == 0 else 1.0
		var offset := 0.6 + (k * 37 % 7) * 0.35
		_disc(group, beside(ARRIVAL + index, side, offset), 0.6 + (k % 4) * 0.25, puddle, Vector2(1.6, 0.9))
	var branches := Node3D.new()
	group.add_child(branches)
	# Stones and debris at the water's edge, no collision: nothing to snag on in a fight.
	var entries := []
	for k in 5:
		entries.append({"kind": "rubble", "at": beside(ARRIVAL + LOWLAND.x + 8 + k * 8, -1.0 if k % 2 else 1.0, 3.6), "radius": 0.6, "count": 4, "collide": false})
	SetDressing.dress(branches, entries, 23)
	var drips := AudioStreamPlayer3D.new()
	drips.name = "CanopyDrips"
	var loop := load("res://assets/audio/ambience/drips.ogg") as AudioStream
	if loop is AudioStreamOggVorbis:
		(loop as AudioStreamOggVorbis).loop = true
	drips.stream = loop
	drips.bus = &"Ambience"
	drips.unit_size = 9.0
	drips.max_distance = 30.0
	drips.volume_db = -4.0
	group.add_child(drips)
	drips.position = beside(ARRIVAL + (LOWLAND.x + LOWLAND.y) * 0.5, 0, 0) + Vector3(0, 4.0, 0)
	drips.autoplay = true


func _convoy(holder: Node3D, props: Array) -> void:
	var group := Node3D.new()
	group.name = "Convoy"
	holder.add_child(group)
	var at := beside(ARRIVAL + CONVOY, 1, 6.8)
	var yaw := facing_road(ARRIVAL + CONVOY, 1)
	var basis := Basis(Vector3.UP, yaw)
	# The cart ran off the road into the ditch, nose down, when the trunk came down beside it.
	var tilted := Node3D.new()
	tilted.name = "Cart"
	group.add_child(tilted)
	tilted.position = at
	tilted.rotation = Vector3(-0.22, yaw + 0.5, 0.12)
	SetDressing.dress(tilted, [{"kind": "cart", "at": Vector3.ZERO, "broken": true, "load": false}], 29)
	var fallen := MeshInstance3D.new()
	fallen.name = "FallenTrunk"
	fallen.mesh = Props.log_mesh(57)
	fallen.material_override = Props.vertex_material()
	group.add_child(fallen)
	fallen.position = at + basis * Vector3(1.8, 0.1, 2.4)
	fallen.rotation.y = yaw + 1.2
	fallen.scale = Vector3(1.5, 1.5, 1.7)
	var trunk_body := StaticBody3D.new()
	var trunk_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 6.8)
	trunk_shape.shape = box
	trunk_body.add_child(trunk_shape)
	group.add_child(trunk_body)
	trunk_body.position = fallen.position + Vector3(0, 0.45, 0)
	trunk_body.rotation.y = fallen.rotation.y
	# A sodden tarp slumped over the cart bed.
	var tarp := MeshInstance3D.new()
	tarp.name = "WetTarp"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.9)
	plane.subdivide_width = 2
	plane.subdivide_depth = 2
	tarp.mesh = plane
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.22, 0.17)
	cloth.roughness = 0.35
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	tarp.material_override = cloth
	tilted.add_child(tarp)
	tarp.position = Vector3(0.1, 1.0, 0.1)
	tarp.rotation = Vector3(0.1, 0.2, 0.25)
	# Cargo that spilled toward the road: something to break, never blocking the way.
	_breakable(group, &"crate", "convoy/crate_0", beside(ARRIVAL + CONVOY - 5, 1, 4.9), yaw + 0.3, props)
	_breakable(group, &"barrel", "convoy/barrel_0", beside(ARRIVAL + CONVOY - 2, 1, 5.0), yaw, props)
	_breakable(group, &"crate", "convoy/crate_1", beside(ARRIVAL + CONVOY + 4, 1, 5.2), yaw - 0.4, props)


func _clearing(holder: Node3D) -> void:
	var group := Node3D.new()
	group.name = "ClearingTraces"
	holder.add_child(group)
	var center: Vector3 = world.point(world.CLEARING.x, world.CLEARING.z)
	var wet := _glossy(Color(0.14, 0.14, 0.15))
	for k in 8:
		var angle := TAU * k / 8.0 + 0.2
		var p := center + Vector3(cos(angle), 0, sin(angle)) * 5.0
		_disc(group, world.point(p.x, p.z), 0.45, wet, Vector2(1.2, 0.8))
	# Someone else rested here once: a cold fire pit, a bedroll, log seats.
	var camp := Node3D.new()
	camp.name = "ColdCamp"
	group.add_child(camp)
	var spot := center + Vector3(-8.0, 0, 3.5)
	camp.position = world.point(spot.x, spot.z)
	SetDressing.dress(camp, [{"kind": "campfire", "at": Vector3.ZERO, "lit": false, "camp": true}], 31)
	# One violet echo of the Eclipse at the edge: a small stela and a faint glow.
	var echo := center + Vector3(10.5, 0, -4.0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	Props.frustum(tool, world.point(echo.x, echo.z) - Vector3(0, 0.1, 0), 0.3, 0.2, 1.6, 5, Color(0.18, 0.18, 0.21), Color(0.28, 0.27, 0.32))
	tool.generate_normals()
	var stela := MeshInstance3D.new()
	stela.name = "EchoStela"
	stela.mesh = tool.commit()
	stela.material_override = Props.vertex_material()
	group.add_child(stela)
	var glint := OmniLight3D.new()
	glint.name = "EclipseEcho"
	glint.light_color = Color(0.55, 0.42, 1.0)
	glint.light_energy = 0.9
	glint.omni_range = 3.0
	group.add_child(glint)
	glint.position = world.point(echo.x, echo.z) + Vector3(0, 1.3, 0.3)


func open_at(index: float) -> bool:
	for stretch: Vector2 in OPEN_STRETCHES:
		if index >= stretch.x + ARRIVAL and index <= stretch.y + ARRIVAL:
			return true
	return false
