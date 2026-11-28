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
	var planks := wood()
	var dark_wood := material("dark_wood", Color(0.15, 0.12, 0.1))
	# The slope down from the clearing, walled by trunks and an invisible rail of thicket.
	ramp(Vector3(0, 0, 0), Vector3(0, DECK_Y, -14), 5.0, 2.0, mud)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 3.4, -1.0, -7.0), Vector3(0.4, 6.0, 15.0), null)
		for k in 4:
			_tree(Vector3(side * (3.6 + k % 2), -1.0 - k * 0.6, -2.0 - k * 3.4), k + int(side * 3.0))
	# Banks and islet.
	box(Vector3(0, DECK_Y - 0.6, -18.5), Vector3(26, 1.2, 9), mud)
	box(Vector3(0.5, DECK_Y - 0.6, -49.0), Vector3(17, 1.2, 18), mud)
	box(Vector3(0, DECK_Y - 0.6, -80.0), Vector3(26, 1.2, 12), mud)
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
	# Plank walks on piles.
	for walk in [[-22.0, -40.0], [-58.0, -74.0]]:
		var length: float = walk[0] - walk[1]
		box(Vector3(0, DECK_Y - 0.1, (walk[0] + walk[1]) * 0.5), Vector3(2.4, 0.2, length), planks)
		var z: float = walk[0] - 1.5
		while z > walk[1]:
			for side in [-1.0, 1.0]:
				box(Vector3(side * 1.35, -4.9, z), Vector3(0.22, 4.0, 0.22), dark_wood, 0.0, false)
			z -= 3.0
	# A mooring post line out of the water ahead: the crossing's landmark.
	for k in 6:
		box(Vector3(4.5 + (k % 2) * 0.4, -3.8, -26.0 - k * 6.0), Vector3(0.3, 2.6, 0.3), dark_wood, 0.0, false)
	# An old walk beside the new one, broken: planks tipped into the water, no footing.
	for k in 6:
		var view := box(Vector3(3.6, WATER_Y + 0.05 - (k % 3) * 0.12, -60.0 - k * 1.1), Vector3(1.8, 0.12, 0.9), dark_wood, 0.0, false)
		view.rotation = Vector3(0.1 * (k % 2), 0.15 * (k - 3), 0.3 if k % 3 == 1 else -0.15)
	_hut(Vector3(5.0, DECK_Y, -52.5))
	# Far bank: stone steps up to the gorge, a landing at the top.
	stairs(Vector3(0, DECK_Y, -84.5), Vector3(0, 0, -1), 8.0, EXIT.y - DECK_Y, 4.0, 14, stone())
	box(Vector3(0, EXIT.y - 0.5, -95.0), Vector3(6, 1.0, 6.5), stone())
	for side in [-1.0, 1.0]:
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
	var planks := material("hut", Color(0.21, 0.16, 0.12))
	box(at + Vector3(0, 1.2, 1.5), Vector3(3.2, 2.4, 0.2), planks)
	box(at + Vector3(0, 1.2, -1.5), Vector3(3.2, 2.4, 0.2), planks)
	box(at + Vector3(1.5, 1.2, 0), Vector3(0.2, 2.4, 3.2), planks)
	box(at + Vector3(-1.5, 1.2, 1.0), Vector3(0.2, 2.4, 1.2), planks)
	box(at + Vector3(-1.5, 1.2, -1.0), Vector3(0.2, 2.4, 1.2), planks)
	var roof := box(at + Vector3(0, 2.6, 0), Vector3(3.8, 0.15, 3.8), material("roof", Color(0.13, 0.11, 0.1)))
	roof.rotation.z = 0.18
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
	window.position = at + Vector3(0, 1.5, 1.62)
	lamp(at + Vector3(0, 1.4, 0), 5.0, 5.5, Color(1.0, 0.58, 0.26), &"lantern")
	# The swinging lantern by the end of the first walk.
	var pole_at := Vector3(1.9, DECK_Y, -41.5)
	box(pole_at + Vector3(0, 1.3, 0), Vector3(0.14, 2.6, 0.14), material("pole", Color(0.18, 0.14, 0.1)), 0.0, false)
	box(pole_at + Vector3(-0.35, 2.55, 0), Vector3(0.8, 0.08, 0.08), material("pole", Color(0.18, 0.14, 0.1)), 0.0, false)
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
