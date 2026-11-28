extends "res://scenes/zones/zone_area.gd"
## The Flooded Crossing, past the bonfire clearing. A wet slope between trunks runs down to a
## mud bank; a plank walk on piles crosses dark water to an islet with the warden's hut, its
## lantern swinging on a pole; a second walk reaches the far bank and stone steps climb to the
## belfry's gorge. West of the islet a shallow ford loops round to the far bank (about 22 m).
## Deep water is death: the hero rises at the last fire. The fight is on the islet's open
## front, 6 x 8 m, wider than the walk.
##
## Local space: entry at the top of the slope, the route runs toward -Z, the walk deck at -3 m.

const WATER_Y := -3.35
const DECK_Y := -3.0
## Below this the hero has gone under in deep water.
const DROWN_Y := -4.1
## Shallow ford: rectangles (x0, z0, x1, z1) where the floor is just under the surface.
const FORD := [Rect2(-11.0, -62.0, 3.5, 13.0), Rect2(-10.0, -75.0, 3.0, 13.5)]
const EXIT := Vector3(0.0, 1.0, -98.0)
const Detail = preload("res://scenes/zones/zone_detail.gd")
const WALKS := [[-22.0, -40.0], [-58.0, -74.0]]
const HUT := Vector3(5.0, DECK_Y, -52.5)
const STELE := Vector3(-2.3, EXIT.y, -93.0)

var _splash_timer := 0.0
var _lantern_pivot: Node3D
var _clock := 0.0


func _init() -> void:
	zone_id = "crossing"
	weather_preset = &"crossing"
	title = "THE FLOODED CROSSING"
	bounds = AABB(Vector3(-20, -10, -100), Vector3(40, 20, 101))
	entry_local = Vector3(0, 0, -1.5)
	respawn_local = Vector3(0, 0, -1.5)
	foes_spec = [
		[&"spearman", Vector3(3.2, DECK_Y, -48.5), PI * 0.5],
		[&"ghoul", Vector3(-2.5, DECK_Y, -47.0), 0.0, Color(0.22, 0.32, 0.2)],
	]


func _layout() -> void:
	var mud := material("mud", Color(0.2, 0.17, 0.13), 0.6)
	# The slope down from the clearing, walled by trunks and an invisible rail of thicket.
	ramp(Vector3(0, 0, 0), Vector3(0, DECK_Y, -14), 5.0, 2.0, mud)
	for side: float in [-1.0, 1.0]:
		box(Vector3(side * 3.4, -1.0, -7.0), Vector3(0.4, 6.0, 15.0), null)
		for k in 4:
			_tree(Vector3(side * (3.6 + k % 2), -1.0 - k * 0.6, -2.0 - k * 3.4), k + int(side * 3.0))
	# Banks and islet: collision here, their surfaces come from the detail pass.
	box(Vector3(0, DECK_Y - 0.6, -18.5), Vector3(26, 1.2, 9), null)
	box(Vector3(0.5, DECK_Y - 0.6, -49.0), Vector3(17, 1.2, 18), null)
	box(Vector3(0, DECK_Y - 0.6, -80.0), Vector3(26, 1.2, 12), null)
	# The water and the deep bed under it.
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 76)
	water.mesh = plane
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://scenes/zones/water.gdshader")
	water.material_override = surface
	add_child(water)
	water.position = Vector3(0, WATER_Y, -50)
	box(Vector3(0, -7.0, -50), Vector3(60, 1.0, 76), null)
	# The shallow ford: a floor a hand under the surface.
	for rect: Rect2 in FORD:
		# Top a hand under the surface and within a step of the banks, so it can be walked.
		box(Vector3(rect.position.x + rect.size.x * 0.5, WATER_Y - 0.35, rect.position.y + rect.size.y * 0.5),
				Vector3(rect.size.x, 0.5, rect.size.y), mud)
	# Plank walks on piles: the deck's collision here, planks and piles in the detail pass.
	for walk: Array in WALKS:
		var length: float = walk[0] - walk[1]
		box(Vector3(0, DECK_Y - 0.1, (walk[0] + walk[1]) * 0.5), Vector3(2.4, 0.2, length), null)
	_hut(HUT)
	# Far bank: stone steps up to the gorge, a landing at the top.
	stairs(Vector3(0, DECK_Y, -84.5), Vector3(0, 0, -1), 8.0, EXIT.y - DECK_Y, 4.0, 14, stone())
	box(Vector3(0, EXIT.y - 0.5, -95.0), Vector3(6, 1.0, 6.5), stone())
	for side: float in [-1.0, 1.0]:
		box(Vector3(side * 2.6, 0.0, -88.5), Vector3(0.6, 3.5, 8.0), stone())
		_tree(Vector3(side * 7.0, DECK_Y, -79.0), 11 + int(side))
		_tree(Vector3(side * 10.0, DECK_Y, -20.0), 13 + int(side))
	# Bounds: thicket along both sides and behind the banks.
	box(Vector3(-16.0, -1.0, -50), Vector3(1.0, 12.0, 100), null)
	box(Vector3(16.0, -1.0, -50), Vector3(1.0, 12.0, 100), null)
	box(Vector3(0, -1.0, -99.5), Vector3(32, 12.0, 1.0), null)
	# Two crates by the hut, kept off the fighting ground.
	breakable(&"crate", "hut/crate_0", Vector3(7.2, DECK_Y, -48.5), 0.3)
	breakable(&"crate", "hut/crate_1", Vector3(6.9, DECK_Y, -56.0), -0.4)
	dress(Vector3(-5.5, DECK_Y, -55.0), [{"kind": "rubble", "at": Vector3.ZERO, "radius": 0.9, "count": 6, "collide": false},
			{"kind": "bones", "at": Vector3(1.5, 0, 1.0), "radius": 0.6, "count": 5, "skulls": 0}], 41)
	loop_sound("res://assets/audio/ambience/water.ogg", Vector3(0, WATER_Y + 0.5, -40), -6.0, 12.0)
	loop_sound("res://assets/audio/ambience/water.ogg", Vector3(-8, WATER_Y + 0.5, -68), -9.0, 10.0)


func _tree(at: Vector3, seed: int) -> void:
	var tree := MeshInstance3D.new()
	tree.mesh = Props.fir(seed + 100) if seed % 3 != 0 else Props.snag(seed + 100)
	tree.material_override = Props.vertex_material()
	add_child(tree)
	tree.position = at - Vector3(0, 0.2, 0)
	tree.rotation.y = seed * 1.3
	var trunk := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = 5.0
	trunk.shape = shape
	_geometry.add_child(trunk)
	trunk.position = at + Vector3(0, 2.3, 0)


## The warden's hut: plank walls, a door toward the fighting ground, a warm window and a
## lantern on a pole that swings with the wind.
func _hut(at: Vector3) -> void:
	# Walls as collision; boards, gable roof and porch come from the detail pass.
	box(at + Vector3(0, 1.2, 1.5), Vector3(3.2, 2.4, 0.2), null)
	box(at + Vector3(0, 1.2, -1.5), Vector3(3.2, 2.4, 0.2), null)
	box(at + Vector3(1.5, 1.2, 0), Vector3(0.2, 2.4, 3.2), null)
	box(at + Vector3(-1.5, 1.2, 1.0), Vector3(0.2, 2.4, 1.2), null)
	box(at + Vector3(-1.5, 1.2, -1.0), Vector3(0.2, 2.4, 1.2), null)
	# A rain barrel at the south-west corner.
	box(at + Vector3(-1.95, 0.45, -1.95), Vector3(0.6, 0.9, 0.6), null)
	var window := MeshInstance3D.new()
	var glass := QuadMesh.new()
	glass.size = Vector2(0.6, 0.45)
	window.mesh = glass
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.66, 0.3)
	window.material_override = glow
	window.name = "Glass"
	add_child(window)
	window.position = at + Vector3(0, 1.5, 1.66)
	lamp(at + Vector3(0, 1.4, 0), 5.0, 5.5, Color(1.0, 0.58, 0.26), &"lantern")
	# The swinging lantern by the end of the first walk.
	var pole_at := Vector3(1.9, DECK_Y, -41.5)
	_lantern_pivot = Node3D.new()
	_lantern_pivot.name = "LanternPivot"
	add_child(_lantern_pivot)
	_lantern_pivot.position = pole_at + Vector3(-0.7, 2.5, 0)
	var cage := MeshInstance3D.new()
	var cage_mesh := BoxMesh.new()
	cage_mesh.size = Vector3(0.18, 0.26, 0.18)
	cage.mesh = cage_mesh
	var cage_glow := StandardMaterial3D.new()
	cage_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cage_glow.albedo_color = Color(1.0, 0.72, 0.35)
	cage.material_override = cage_glow
	cage.name = "Glass"
	_lantern_pivot.add_child(cage)
	cage.position = Vector3(0, -0.4, 0)
	var light := OmniLight3D.new()
	light.name = "LampSwing"
	light.light_color = Color(1.0, 0.6, 0.26)
	light.light_energy = 8.0
	light.omni_range = 8.0
	light.omni_attenuation = 1.2
	_lantern_pivot.add_child(light)
	light.position = Vector3(0, -0.45, 0)
	var fire := preload("res://scenes/fx/fire_light.gd").new()
	fire.name = "Flicker"
	fire.profile = &"lantern"
	light.add_child(fire)


# ---------------------------------------------------------------- detail

## Lights, solid pieces and air for the detail pass (main thread, cheap).
func _detail_nodes() -> void:
	for side: float in [-1.0, 1.0]:
		# Stone posts with lanterns at the foot of the steps.
		box(Vector3(side * 2.75, DECK_Y + 0.9, -83.6), Vector3(0.5, 1.8, 0.5), null)
		lamp(Vector3(side * 2.75, DECK_Y + 2.2, -83.6), 4.5, 5.5, Color(1.0, 0.6, 0.28), &"lantern", "StepLamp")
	# The waymark stele at the head of the steps.
	box(STELE + Vector3(0, 0.75, 0), Vector3(0.6, 1.5, 0.3), null)
	# Two leaning dead trees over the water, landmarks against the sky.
	for spec in [[Vector3(-11.5, DECK_Y - 0.2, -24.0), -0.38, 81], [Vector3(10.5, DECK_Y - 0.2, -75.0), 0.32, 103]]:
		var snag := MeshInstance3D.new()
		snag.name = "LeaningSnag"
		snag.mesh = Props.snag(spec[2])
		snag.material_override = Props.vertex_material()
		_visual.add_child(snag)
		snag.position = spec[0]
		snag.rotation = Vector3(spec[1], 0.0, 0.12)
	# Mist low over the water and fireflies over the ford.
	ambient(Detail.mist(Vector3(0, WATER_Y + 0.6, -50.0), Vector3(14.0, 0.3, 24.0), 26))
	ambient(Detail.fireflies(Vector3(-8.5, WATER_Y + 1.1, -61.0), Vector3(3.0, 0.7, 12.0), 22))


## Everything that makes the crossing read as a place rather than blocks, in three regions
## (shore, islet, far bank) so no merged mesh spans too many lights. Pure geometry: runs on a
## worker thread when the zone is streamed.
func _detail_regions() -> Array:
	var regions := []
	var mud_top := Color(0.14, 0.125, 0.09)
	var mud_side := Color(0.1, 0.085, 0.07)
	var plank := Color(0.29, 0.22, 0.15)
	var pile := Color(0.15, 0.12, 0.09)
	var rope := Color(0.32, 0.27, 0.19)
	var moss := Color(0.16, 0.2, 0.12)

	# Shore: the near bank, the slope's sides, the first half of the walk.
	var d: Detail = Detail.new(301)
	d.landmass(Vector3(0, 0, -18.5), Vector2(13, 4.5), DECK_Y, 1.6, mud_top, mud_side)
	for k in 7:
		# Stones and roots along the slope's sides, outside the walkable strip.
		for side: float in [-1.0, 1.0]:
			var z := -1.5 - k * 2.0
			var y := DECK_Y * clampf(-z / 14.0, 0.0, 1.0)
			d.blob(d.opaque, Vector3(side * d.rng.randf_range(2.7, 3.1), y + 0.05, z), d.rng.randf_range(0.25, 0.45),
					Vector3(1.2, 0.7, 1.0), Color(0.24, 0.23, 0.21))
	d.root(Vector3(-3.4, -1.2, -6.5), Vector3(-2.4, -1.95, -9.8), 0.12, Color(0.2, 0.15, 0.11))
	d.root(Vector3(3.3, -0.4, -3.5), Vector3(2.5, -1.3, -6.0), 0.1, Color(0.2, 0.15, 0.11))
	_walk_detail(d, WALKS[0][0], -31.0, plank, pile, rope)
	for x: float in [-11.0, -8.0, -5.0, -3.0, 3.0, 5.5, 8.5, 11.5]:
		d.reeds(Vector3(x + d.rng.randf_range(-0.6, 0.6), WATER_Y, -23.6), 0.9, 9)
	d.lily_pads(Vector3(-6.0, 0, -28.0), 2.5, 9, WATER_Y)
	d.lily_pads(Vector3(7.5, 0, -33.0), 2.0, 6, WATER_Y)
	_floating_log(d, Vector3(-4.5, WATER_Y, -31.0), 0.6)
	regions.append([d, "DetailShore"])

	# Islet: the ground, the hut, the swinging lantern's pole, mooring posts, the ford.
	d = Detail.new(302)
	d.landmass(Vector3(0.5, 0, -49.0), Vector2(8.5, 9.0), DECK_Y, 1.5, mud_top.lightened(0.03), mud_side)
	_walk_detail(d, -31.0, WALKS[0][1], plank, pile, rope)
	_hut_detail(d, HUT, plank)
	var pole_at := Vector3(1.9, DECK_Y, -41.5)
	d.frustum(d.opaque, pole_at, 0.09, 0.07, 2.65, 5, pile, pile.lightened(0.1))
	d.rod(d.opaque, pole_at + Vector3(0.05, 2.55, 0), pole_at + Vector3(-0.78, 2.55, 0), 0.045, 0.04, pile)
	d.rod(d.opaque, pole_at + Vector3(0, 2.0, 0), pole_at + Vector3(-0.45, 2.53, 0), 0.03, 0.03, pile)
	# The old mooring line: posts in the water, ropes sagging between the first three.
	var posts := []
	for k in 6:
		var at := Vector3(4.5 + (k % 2) * 0.4, WATER_Y - 1.2, -26.0 - k * 6.0)
		var height := 2.1 + d.rng.randf_range(-0.3, 0.3)
		d.frustum(d.opaque, at, 0.16, 0.12, height, 6, pile.darkened(0.3), pile, Vector3(d.rng.randf_range(-0.12, 0.12), 0, d.rng.randf_range(-0.12, 0.12)))
		posts.append(at + Vector3(0, height - 0.25, 0))
	for k in 2:
		d.rope(posts[k], posts[k + 1], 0.5, rope)
	# The broken old walk beside the new one: planks tipped into the water.
	for k in 7:
		var tilt := Basis.from_euler(Vector3(0.12 * (k % 2), 0.15 * (k - 3), 0.32 if k % 3 == 1 else -0.18))
		d.block(d.opaque, Vector3(3.6, WATER_Y + 0.04 - (k % 3) * 0.1, -59.5 - k * 1.0), Vector3(1.8, 0.07, 0.26), pile.lightened(0.05), tilt)
	for k in 3:
		d.frustum(d.opaque, Vector3(3.6 + (k - 1) * 0.9, WATER_Y - 1.0, -61.0 - k * 2.4), 0.1, 0.08, 1.3 - k * 0.25, 5, pile.darkened(0.3), pile)
	_rowboat(d, Vector3(10.6, WATER_Y, -45.5), 0.35)
	d.rope(Vector3(9.2, DECK_Y + 0.55, -45.0), Vector3(10.0, WATER_Y + 0.35, -45.3), 0.12, rope)
	d.frustum(d.opaque, Vector3(8.9, DECK_Y - 0.2, -45.0), 0.08, 0.07, 0.85, 5, pile, pile)
	# Reeds round the islet, thick where the ford leaves it so the way reads from the walk.
	for k in 14:
		var angle := TAU * k / 14.0
		var at := Vector3(0.5 + cos(angle) * 9.2, WATER_Y, -49.0 + sin(angle) * 9.6)
		if absf(at.x) < 2.0:
			continue
		d.reeds(at, 0.7, 7)
	for rect: Rect2 in FORD:
		for z in range(int(rect.position.y) + 1, int(rect.end.y), 2):
			d.reeds(Vector3(rect.position.x - 0.5, WATER_Y, z), 0.4, 5)
			d.reeds(Vector3(rect.end.x + 0.6, WATER_Y, z + 1.0), 0.4, 4)
			if z % 4 == 0:
				d.blob(d.opaque, Vector3(rect.get_center().x + d.rng.randf_range(-1, 1), WATER_Y - 0.12, z), 0.35,
						Vector3(1.4, 0.5, 1.1), Color(0.25, 0.25, 0.23))
	d.lily_pads(Vector3(-7.0, 0, -42.0), 2.5, 10, WATER_Y)
	d.lily_pads(Vector3(10.5, 0, -55.0), 2.0, 7, WATER_Y)
	_floating_log(d, Vector3(-3.5, WATER_Y, -64.0), 2.2)
	regions.append([d, "DetailIslet"])

	# Far bank and the steps: the second walk's far half, a lantern on each stone post at the
	# foot of the steps, moss and a cracked balustrade, a waymark at the top.
	d = Detail.new(303)
	d.landmass(Vector3(0, 0, -80.0), Vector2(13, 6.0), DECK_Y, 1.6, mud_top, mud_side)
	_walk_detail(d, WALKS[1][0], WALKS[1][1], plank, pile, rope)
	for x: float in [-11.5, -8.5, -6.0, -3.0, 3.0, 6.0, 9.0, 11.0]:
		d.reeds(Vector3(x + d.rng.randf_range(-0.6, 0.6), WATER_Y, -73.5), 0.9, 9)
	for i in 14:
		# Moss along each step's nose, thicker toward the sides.
		var z := -84.5 - (i + 0.1) * 8.0 / 14.0
		var y := DECK_Y + (EXIT.y - DECK_Y) * (i + 1) / 14.0
		for side: float in [-1.0, 1.0]:
			d.block(d.opaque, Vector3(side * d.rng.randf_range(1.3, 1.85), y + 0.015, z), Vector3(d.rng.randf_range(0.3, 0.8), 0.03, 0.18), moss)
	for side: float in [-1.0, 1.0]:
		# The side walls get coping stones, a few missing.
		for k in 8:
			if d.rng.randf() < 0.2:
				continue
			d.block(d.opaque, Vector3(side * 2.6, 1.82, -84.9 - k * 1.0), Vector3(0.75, 0.16, 0.9),
					Color(0.27, 0.27, 0.26), Basis(Vector3.UP, d.rng.randf_range(-0.05, 0.05)))
		var post := Vector3(side * 2.75, DECK_Y, -83.6)
		d.block(d.opaque, post + Vector3(0, 0.9, 0), Vector3(0.5, 1.8, 0.5), Color(0.26, 0.26, 0.25))
		d.block(d.opaque, post + Vector3(0, 1.86, 0), Vector3(0.62, 0.12, 0.62), Color(0.3, 0.3, 0.29))
		d.frustum(d.opaque, post + Vector3(0, 1.92, 0), 0.1, 0.08, 0.12, 6, Color(0.12, 0.12, 0.13), Color(0.12, 0.12, 0.13))
		d.block(d.glow, post + Vector3(0, 2.16, 0), Vector3(0.14, 0.22, 0.14), Color(1.0, 0.7, 0.34))
		d.frustum(d.opaque, post + Vector3(0, 2.27, 0), 0.12, 0.0, 0.14, 4, Color(0.12, 0.12, 0.13), Color(0.12, 0.12, 0.13))
		d.blob(d.opaque, Vector3(side * 8.5, DECK_Y, -84.0), 0.7, Vector3(1.4, 0.8, 1.1), Color(0.24, 0.24, 0.22))
		d.blob(d.opaque, Vector3(side * 11.0, DECK_Y, -77.0), 0.9, Vector3(1.2, 0.9, 1.3), Color(0.22, 0.22, 0.2))
	# The waymark: a worn stele at the head of the steps, a violet mark like the arch's.
	var stele := STELE
	d.block(d.opaque, stele + Vector3(0, 0.75, 0), Vector3(0.6, 1.5, 0.3), Color(0.25, 0.25, 0.26), Basis(Vector3.FORWARD, 0.06))
	d.block(d.glow, stele + Vector3(0.02, 1.0, 0.16), Vector3(0.12, 0.4, 0.02), Color(0.5, 0.38, 0.9))
	regions.append([d, "DetailFarBank"])
	return regions


## Planks and piles for the stretch of a walk from z0 to z1 (z0 > z1): piles every 3 m, every
## other one standing up past the deck with a rope rail on the hut's side.
func _walk_detail(d: Detail, z0: float, z1: float, plank: Color, pile: Color, rope: Color) -> void:
	d.plank_walk(0.0, z0, z1, DECK_Y, 2.4, plank)
	var rail := []
	var z := ceilf(z0 / 3.0) * 3.0 - 1.5
	while z > z1:
		for side: float in [-1.0, 1.0]:
			var tall: bool = int(absf(z) / 3.0) % 2 == 0
			var top := DECK_Y + (0.95 if tall else -0.05)
			var from := Vector3(side * 1.35, WATER_Y - 1.4, z)
			d.frustum(d.opaque, from, 0.13, 0.11, top - from.y, 6, pile.darkened(0.35), pile)
			if tall and side > 0.0:
				rail.append(Vector3(side * 1.35, top - 0.08, z))
		z -= 3.0
	for i in rail.size() - 1:
		if rail[i].distance_to(rail[i + 1]) < 6.5:
			d.rope(rail[i], rail[i + 1], 0.22, rope)


## Boards over the hut's walls, a gable roof, a porch, a half-open door, the rain barrel and a
## net hung to dry on the east side.
func _hut_detail(d: Detail, at: Vector3, plank: Color) -> void:
	var board := plank.darkened(0.25)
	# Each wall: a run of vertical boards just outside its collision face.
	var walls := [
		[Vector3(0, 0, 1.62), Vector3.RIGHT, 3.3, []],
		[Vector3(0, 0, -1.62), Vector3.RIGHT, 3.3, []],
		[Vector3(1.62, 0, 0), Vector3.BACK, 3.3, []],
		# West wall with the door gap between -0.4 and 0.4.
		[Vector3(-1.62, 0, 0), Vector3.BACK, 3.3, [-0.42, 0.42]],
	]
	for wall: Array in walls:
		var along: Vector3 = wall[1]
		var length: float = wall[2]
		var gap: Array = wall[3]
		var u := -length * 0.5 + 0.11
		while u < length * 0.5:
			if gap.is_empty() or u < gap[0] or u > gap[1]:
				var height := 2.4 + d.rng.randf_range(-0.06, 0.04)
				var lean := Basis(along.cross(Vector3.UP), d.rng.randf_range(-0.015, 0.015))
				var size := along.abs() * 0.2 + (Vector3.ONE - along.abs()) * 0.06
				size.y = height
				d.block(d.opaque, at + wall[0] + along * u + Vector3(0, height * 0.5, 0), size, d._jitter(board, 0.1), lean)
			u += 0.22
		# A rail across the boards at knee and lintel height.
		for y: float in [0.5, 2.05]:
			d.block(d.opaque, at + wall[0] * 1.04 + Vector3(0, y, 0), Vector3(0.1, 0.12, 0.1) + along.abs() * (length - 0.1), board.darkened(0.2))
	# Gable roof: ridge along z, two slopes of overlapping shingle strips.
	var roof := Color(0.14, 0.12, 0.1)
	for side: float in [-1.0, 1.0]:
		for strip in 4:
			var x := side * (0.35 + strip * 0.55)
			var y := 3.05 - strip * 0.3
			d.block(d.opaque, at + Vector3(x, y, 0), Vector3(0.68, 0.08, 4.0 + d.rng.randf_range(-0.1, 0.1)), d._jitter(roof, 0.1),
					Basis(Vector3.BACK, -side * 0.5))
	d.block(d.opaque, at + Vector3(0, 3.2, 0), Vector3(0.16, 0.16, 4.1), roof.darkened(0.2))
	for end: float in [-1.0, 1.0]:
		d.triangle(d.opaque, at + Vector3(-1.65, 2.38, end * 1.63), at + Vector3(1.65, 2.38, end * 1.63), at + Vector3(0, 3.22, end * 1.63), board.darkened(0.1))
	# Porch boards before the door, the door itself half open.
	for k in 4:
		d.block(d.opaque, at + Vector3(-1.95, 0.03, -0.75 + k * 0.5), Vector3(0.75, 0.05, 0.45), d._jitter(plank, 0.1),
				Basis(Vector3.UP, d.rng.randf_range(-0.05, 0.05)))
	# Hinged at the gap's north edge, swung out a radian.
	var swing := Basis(Vector3.UP, 1.0)
	d.block(d.opaque, at + Vector3(-1.62, 1.05, 0.42) + swing * Vector3(0, 0, -0.39), Vector3(0.05, 2.0, 0.78), board.lightened(0.05), swing)
	# The rain barrel.
	var barrel := at + Vector3(-1.95, 0, -1.95)
	d.frustum(d.opaque, barrel, 0.26, 0.3, 0.45, 8, plank.darkened(0.3), plank.darkened(0.1))
	d.frustum(d.opaque, barrel + Vector3(0, 0.45, 0), 0.3, 0.26, 0.45, 8, plank.darkened(0.1), plank.darkened(0.3))
	d.block(d.opaque, barrel + Vector3(0, 0.86, 0), Vector3(0.44, 0.02, 0.44), Color(0.06, 0.08, 0.1))
	# A net hung on two poles to the east, sagging, with a float or two.
	var p0 := at + Vector3(2.4, 0, -1.2)
	var p1 := at + Vector3(2.4, 0, 1.3)
	for p: Vector3 in [p0, p1]:
		d.frustum(d.opaque, p, 0.05, 0.04, 1.9, 5, plank.darkened(0.4), plank.darkened(0.2))
	for row in 5:
		var y := 1.8 - row * 0.28
		d.rope(p0 + Vector3(0, y, 0), p1 + Vector3(0, y, 0), 0.18 + row * 0.03, Color(0.2, 0.19, 0.17))
	for col in 6:
		var z := lerpf(p0.z, p1.z, (col + 0.5) / 6.0)
		d.rod(d.foliage, Vector3(p0.x, at.y + 1.8 - 0.2, z), Vector3(p0.x + 0.02, at.y + 0.65, z), 0.012, 0.012, Color(0.2, 0.19, 0.17), 3)
	d.blob(d.opaque, at + Vector3(2.45, 0.95, 0.1), 0.08, Vector3.ONE, Color(0.55, 0.35, 0.15))


func _rowboat(d: Detail, at: Vector3, roll: float) -> void:
	var hull := Color(0.2, 0.16, 0.12)
	var basis := Basis.from_euler(Vector3(0.08, 0.5, roll))
	d.block(d.opaque, at + basis * Vector3(0, -0.05, 0), Vector3(0.95, 0.08, 3.0), hull.darkened(0.2), basis)
	for side: float in [-1.0, 1.0]:
		d.block(d.opaque, at + basis * Vector3(side * 0.55, 0.15, 0), Vector3(0.07, 0.42, 3.0), hull, basis * Basis(Vector3.BACK, side * 0.35))
	d.block(d.opaque, at + basis * Vector3(0, 0.15, 1.55), Vector3(0.8, 0.4, 0.08), hull, basis)
	d.block(d.opaque, at + basis * Vector3(0, 0.12, -1.52), Vector3(0.5, 0.36, 0.08), hull, basis * Basis(Vector3.RIGHT, 0.4))
	d.block(d.opaque, at + basis * Vector3(0, 0.18, 0.2), Vector3(1.0, 0.06, 0.28), hull.lightened(0.08), basis)
	d.rod(d.opaque, at + basis * Vector3(0.3, 0.25, -0.6), at + basis * Vector3(-0.9, -0.2, 1.4), 0.03, 0.03, hull.lightened(0.1))


func _floating_log(d: Detail, at: Vector3, yaw: float) -> void:
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	d.rod(d.opaque, at - dir * 1.4 + Vector3(0, -0.04, 0), at + dir * 1.4, 0.2, 0.16, Color(0.17, 0.14, 0.11), 6)
	d.rod(d.opaque, at + dir * 0.4, at + dir * 0.4 + Vector3(dir.z, 0.35, -dir.x) * 0.9, 0.05, 0.02, Color(0.17, 0.14, 0.11), 4)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _lantern_pivot != null:
		var weather := get_node_or_null(^"/root/Weather")
		var push: float = (weather.wind * 0.12 + weather.gust * 0.25) if weather != null else 0.1
		_lantern_pivot.rotation = Vector3(sin(_clock * 1.9) * push, 0, sin(_clock * 1.3 + 0.7) * push * 0.6)
	if not active or not prepared or not is_instance_valid(player):
		return
	var here := to_local(player.global_position)
	var combat := player.get_node_or_null(^"Combat")
	if here.y < DROWN_Y and combat != null and combat.health > 0.0 and not _in_ford(here):
		combat.fall_to_death()
	_splash_timer -= delta
	if _splash_timer <= 0.0 and _in_ford(here) and player.velocity.length() > 1.0:
		_splash_timer = 0.22
		_fx().sparks(player.global_position + Vector3(0, 0.1, 0), Color(0.6, 0.7, 0.8), 4)


func _in_ford(here: Vector3) -> bool:
	for rect: Rect2 in FORD:
		if rect.grow(0.4).has_point(Vector2(here.x, here.z)):
			return true
	return false


## The RetroFX autoload, looked up at run time so this script also compiles where autoload
## names are not known (headless test scripts that preload it).
func _fx() -> Node:
	return get_node(^"/root/RetroFX")
