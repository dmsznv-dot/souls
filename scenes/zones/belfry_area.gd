extends "res://scenes/zones/zone_area.gd"
## The Belfry under the Roots, beyond the crossing. A gorge between rock walls narrows into a
## tilted crypt that runs down to a lower chamber lit by one fire, cold glints at the roots.
## The fight is on the chamber floor. A rotten grate in the west wall hides a niche whose
## passage loops back into the chamber. A gallery climbs the east wall to the bell hall;
## ahead, a ritual arch (violet, dormant) marks the stairs up. The bell hangs from the roots
## in a shaft of moonlight and rings when a gust gets in; the chamber below answers with a
## fading hum. Stairs climb to the exit, visible from the hall.
##
## Local space: entry at the gorge mouth (y 0), the route runs toward -Z.

const FLOOR_Y := -4.0
const HALL_Y := -1.0
const BELL := Vector3(0.0, 3.2, -44.0)
const EXIT := Vector3(0.0, 2.0, -58.0)

var _bell: Node3D
var _bell_voice: AudioStreamPlayer3D
var _echo_voice: AudioStreamPlayer3D
var _bell_rest := 4.0
var _bell_swing := 0.0
var rings := 0


func _init() -> void:
	zone_id = "belfry"
	weather_preset = &"belfry"
	title = "THE BELFRY UNDER THE ROOTS"
	bounds = AABB(Vector3(-15, -8, -62), Vector3(28, 20, 64))
	entry_local = Vector3(0, 0, -2.0)
	respawn_local = Vector3(0, 0, -2.0)
	foes_spec = [
		[&"shieldbearer", Vector3(0.5, FLOOR_Y, -26.0), 0.0],
		[&"husk", Vector3(6.5, HALL_Y, -34.0), 0.0, Color(0.28, 0.33, 0.22)],
	]


func _layout() -> void:
	var rock := stone()
	var root_color := material("root", Color(0.22, 0.17, 0.13))
	# The gorge: a level mouth between rock faces, roots arching overhead.
	box(Vector3(0, -0.5, -3.0), Vector3(7.0, 1.0, 6.0), rock)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 3.2, 2.5, -3.0), Vector3(1.0, 6.0, 6.0), rock)
	for k in 3:
		_root(Vector3(-3.0, 4.2 - k * 0.3, -1.0 - k * 2.0), Vector3(3.0, 4.6 - k * 0.2, -1.6 - k * 2.0), 0.22, root_color)
	# The crypt arch, then a tunnel that tilts down to the chamber.
	for side in [-1.0, 1.0]:
		box(Vector3(side * 1.9, 1.6, -6.2), Vector3(0.6, 3.2, 0.6), rock)
	box(Vector3(0, 3.35, -6.2), Vector3(4.4, 0.5, 0.7), rock)
	ramp(Vector3(0, 0, -6.0), Vector3(0, FLOOR_Y, -18.0), 3.6, 1.0, rock)
	ramp(Vector3(0, 3.6, -6.0), Vector3(0, FLOOR_Y + 3.6, -18.0), 4.2, 0.6, rock)
	for side in [-1.0, 1.0]:
		var wall_from := Vector3(side * 2.0, 1.8, -6.0)
		var wall_to := Vector3(side * 2.0, FLOOR_Y + 1.8, -18.0)
		var center := (wall_from + wall_to) * 0.5
		var tilt := atan2(wall_from.y - wall_to.y, wall_from.z - wall_to.z)
		var view := box(center, Vector3(0.4, 4.0, 12.6), rock, 0.0, false)
		view.rotation.x = -tilt
	box(Vector3(-2.0, -1.0, -12.0), Vector3(0.4, 9.0, 12.6), null)
	box(Vector3(2.0, -1.0, -12.0), Vector3(0.4, 9.0, 12.6), null)
	# The lower chamber.
	box(Vector3(0, FLOOR_Y - 0.5, -25.5), Vector3(17.0, 1.0, 15.0), rock)
	box(Vector3(0, FLOOR_Y + 7.3, -25.5), Vector3(17.0, 0.6, 15.0), rock)
	box(Vector3(8.6, FLOOR_Y + 3.5, -25.5), Vector3(0.6, 7.0, 15.0), rock)
	# West wall in pieces around the niche's two openings (z -21 grate, z -29 open).
	box(Vector3(-8.6, FLOOR_Y + 3.5, -18.9), Vector3(0.6, 7.0, 1.8), rock)
	box(Vector3(-8.6, FLOOR_Y + 3.5, -25.0), Vector3(0.6, 7.0, 6.4), rock)
	box(Vector3(-8.6, FLOOR_Y + 3.5, -31.6), Vector3(0.6, 7.0, 2.8), rock)
	box(Vector3(-8.6, FLOOR_Y + 5.0, -21.0), Vector3(0.6, 4.0, 1.6), rock)
	box(Vector3(-8.6, FLOOR_Y + 5.0, -29.0), Vector3(0.6, 4.0, 1.6), rock)
	# Back wall of the chamber beside the stairs, front wall around the crypt mouth.
	# Back wall: left of the stairs and between the stairs and the gallery.
	box(Vector3(-5.4, FLOOR_Y + 3.5, -33.1), Vector3(6.2, 7.0, 0.6), rock)
	box(Vector3(3.9, FLOOR_Y + 3.5, -33.1), Vector3(3.2, 7.0, 0.6), rock)
	# The well between the chamber and the hall: a floor below, walls and a roof around the
	# stairs and the gallery so nothing opens onto the void.
	box(Vector3(3.15, FLOOR_Y - 0.5, -36.4), Vector3(10.9, 1.0, 6.6), rock)
	box(Vector3(-2.45, FLOOR_Y + 4.5, -36.4), Vector3(0.3, 9.0, 6.6), rock)
	box(Vector3(8.6, FLOOR_Y + 4.5, -36.4), Vector3(0.6, 9.0, 6.6), rock)
	box(Vector3(3.15, FLOOR_Y + 9.5, -36.4), Vector3(11.5, 0.6, 6.6), rock)
	box(Vector3(-5.3, FLOOR_Y + 3.5, -17.9), Vector3(6.6, 7.0, 0.6), rock)
	box(Vector3(5.3, FLOOR_Y + 3.5, -17.9), Vector3(6.6, 7.0, 0.6), rock)
	box(Vector3(0, 1.45, -17.9), Vector3(4.0, 3.7, 0.6), rock)
	_niche(rock)
	# The gallery: up the east wall from the chamber floor to the bell hall's level.
	ramp(Vector3(6.6, FLOOR_Y, -19.5), Vector3(6.6, HALL_Y, -29.5), 2.0, 0.6, rock)
	box(Vector3(6.6, HALL_Y - 0.3, -35.5), Vector3(2.0, 0.6, 12.0), rock)
	box(Vector3(5.45, HALL_Y + 0.3, -33.0), Vector3(0.25, 0.6, 7.0), rock)
	# The ritual arch at the foot of the stairs, violet and dormant.
	for side in [-1.0, 1.0]:
		box(Vector3(side * 2.3, FLOOR_Y + 1.8, -32.6), Vector3(0.5, 3.6, 0.5), rock)
	box(Vector3(0, FLOOR_Y + 3.8, -32.6), Vector3(5.1, 0.5, 0.6), rock)
	cold_light(Vector3(0, FLOOR_Y + 2.6, -32.0), 1.4, 4.0, Color(0.55, 0.42, 1.0))
	stairs(Vector3(0, FLOOR_Y, -33.4), Vector3(0, 0, -1), 5.0, HALL_Y - FLOOR_Y, 4.0, 12, rock)
	# The bell hall, a shaft open to the sky over the bell.
	box(Vector3(0, HALL_Y - 0.5, -44.6), Vector3(16.0, 1.0, 13.2), rock)
	box(Vector3(-8.0, HALL_Y + 4.0, -45.0), Vector3(0.6, 9.0, 11.0), rock)
	box(Vector3(8.0, HALL_Y + 4.0, -45.0), Vector3(0.6, 9.0, 11.0), rock)
	box(Vector3(-5.1, HALL_Y + 4.0, -39.4), Vector3(5.8, 9.0, 0.4), rock)
	box(Vector3(3.85, HALL_Y + 4.0, -39.4), Vector3(3.3, 9.0, 0.4), rock)
	box(Vector3(-5.0, HALL_Y + 8.3, -45.0), Vector3(6.0, 0.6, 11.0), rock)
	box(Vector3(5.0, HALL_Y + 8.3, -45.0), Vector3(6.0, 0.6, 11.0), rock)
	box(Vector3(0, HALL_Y + 8.3, -41.2), Vector3(4.0, 0.6, 3.0), rock)
	box(Vector3(0, HALL_Y + 8.3, -48.8), Vector3(4.0, 0.6, 3.0), rock)
	box(Vector3(-4.95, HALL_Y + 4.0, -50.8), Vector3(6.1, 9.0, 0.6), rock)
	box(Vector3(4.95, HALL_Y + 4.0, -50.8), Vector3(6.1, 9.0, 0.6), rock)
	for k in 3:
		_root(Vector3(-7.5, 7.0 - k * 0.4, -42.0 - k * 2.0), Vector3(7.5, 7.4 - k * 0.3, -43.0 - k * 1.5), 0.3, root_color)
	_make_bell()
	# Moonlight down the shaft: a cold wash on the bell so its silhouette reads from the stairs.
	cold_light(BELL + Vector3(0.6, 2.5, 1.5), 2.2, 9.0, Color(0.5, 0.64, 0.95))
	# Stairs to the exit, a landing under the open sky, a lantern at the door.
	stairs(Vector3(0, HALL_Y, -51.1), Vector3(0, 0, -1), 5.0, EXIT.y - HALL_Y, 3.6, 10, rock)
	box(Vector3(0, EXIT.y - 0.5, -59.0), Vector3(5.0, 1.0, 5.6), rock)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 2.2, EXIT.y + 1.6, -56.4), Vector3(0.5, 3.2, 0.5), rock)
		box(Vector3(side * 2.4, EXIT.y + 2.0, -59.0), Vector3(0.4, 4.0, 5.6), rock)
	box(Vector3(0, EXIT.y + 2.0, -61.8), Vector3(5.0, 4.0, 0.4), null)
	lamp(Vector3(1.8, EXIT.y + 2.1, -56.9), 6.0, 6.0, Color(1.0, 0.58, 0.25), &"lantern")
	# One fire in the chamber; cold glints at the roots; draughts in the openings.
	dress(Vector3(-4.0, FLOOR_Y, -27.0), [{"kind": "campfire", "at": Vector3.ZERO, "lit": true, "camp": false}], 53)
	cold_light(Vector3(6.5, FLOOR_Y + 5.5, -20.0), 1.1, 6.0, Color(0.45, 0.62, 0.7))
	cold_light(Vector3(-6.0, HALL_Y + 6.0, -48.0), 1.0, 7.0, Color(0.45, 0.6, 0.75))
	# Two different spills of debris and a pair of crates in the chamber's corner.
	dress(Vector3(4.5, FLOOR_Y, -31.0), [{"kind": "rubble", "at": Vector3.ZERO, "radius": 1.0, "count": 9, "collide": false}], 61)
	dress(Vector3(-5.0, HALL_Y, -48.5), [{"kind": "bones", "at": Vector3.ZERO, "radius": 1.0, "count": 9, "skulls": 2},
			{"kind": "rubble", "at": Vector3(1.5, 0, 0.5), "radius": 0.6, "count": 5, "collide": false}], 67)
	breakable(&"crate", "chamber/crate_0", Vector3(-6.8, FLOOR_Y, -31.4), 0.2)
	breakable(&"barrel", "chamber/barrel_0", Vector3(-7.2, FLOOR_Y, -19.4), 0.0)
	loop_sound("res://assets/audio/ambience/drips.ogg", Vector3(0, FLOOR_Y + 4.0, -25.0), -5.0, 10.0)
	loop_sound("res://assets/audio/ambience/rain.ogg", Vector3(0, 2.0, -1.0), -8.0, 6.0)


## The niche: a passage behind the west wall from the grate (z -21) round to an open mouth
## (z -29). Bones and caps inside: a find, never the way on.
func _niche(rock: Material) -> void:
	var x := -10.6
	box(Vector3(x, FLOOR_Y - 0.5, -25.0), Vector3(4.0, 1.0, 10.0), rock)
	box(Vector3(x, FLOOR_Y + 2.8, -25.0), Vector3(4.0, 0.5, 10.0), rock)
	box(Vector3(-12.8, FLOOR_Y + 1.5, -25.0), Vector3(0.5, 3.0, 10.0), rock)
	box(Vector3(x, FLOOR_Y + 1.5, -20.2), Vector3(4.0, 3.0, 0.5), rock)
	box(Vector3(x, FLOOR_Y + 1.5, -29.8), Vector3(4.0, 3.0, 0.5), rock)
	box(Vector3(-10.3, FLOOR_Y + 1.5, -25.0), Vector3(2.0, 3.0, 5.4), rock)
	breakable(&"grate", "niche/grate", Vector3(-8.6, FLOOR_Y, -21.0), PI * 0.5)
	dress(Vector3(-11.8, FLOOR_Y, -25.0), [{"kind": "bones", "at": Vector3.ZERO, "radius": 0.5, "count": 6, "skulls": 1}], 71)
	var caps := MeshInstance3D.new()
	caps.name = "NicheCaps"
	caps.mesh = Props.mushrooms(88)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	caps.material_override = glow
	add_child(caps)
	caps.position = Vector3(-12.2, FLOOR_Y, -27.0)


func _root(from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var run := to - from
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.7
	mesh.bottom_radius = radius
	mesh.height = run.length()
	mesh.radial_segments = 6
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = mat
	add_child(view)
	view.transform = Transform3D(Basis.looking_at(run.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), (from + to) * 0.5)


func _make_bell() -> void:
	_bell = Node3D.new()
	_bell.name = "Bell"
	add_child(_bell)
	_bell.position = BELL + Vector3(0, 2.0, 0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var bronze := Color(0.36, 0.28, 0.16)
	Props.frustum(tool, Vector3(0, -2.0, 0), 1.0, 0.85, 0.25, 10, bronze.darkened(0.3), bronze)
	Props.frustum(tool, Vector3(0, -1.75, 0), 0.85, 0.45, 1.5, 10, bronze, bronze.lightened(0.15))
	Props.frustum(tool, Vector3(0, -0.25, 0), 0.45, 0.12, 0.3, 10, bronze.lightened(0.15), bronze)
	Props.frustum(tool, Vector3(0, 0.0, 0), 0.05, 0.05, 2.0, 4, Color(0.15, 0.15, 0.16), Color(0.15, 0.15, 0.16))
	tool.generate_normals()
	var view := MeshInstance3D.new()
	view.mesh = tool.commit()
	view.material_override = Props.vertex_material(0.35)
	_bell.add_child(view)
	_bell_voice = AudioStreamPlayer3D.new()
	_bell_voice.stream = load("res://assets/audio/sfx/bell_toll.wav")
	_bell_voice.bus = &"SFX"
	_bell_voice.unit_size = 14.0
	_bell_voice.max_distance = 60.0
	_bell.add_child(_bell_voice)
	_echo_voice = AudioStreamPlayer3D.new()
	_echo_voice.stream = load("res://assets/audio/sfx/bell_echo.wav")
	_echo_voice.bus = &"SFX"
	_echo_voice.unit_size = 10.0
	_echo_voice.max_distance = 40.0
	add_child(_echo_voice)
	_echo_voice.position = Vector3(0, FLOOR_Y + 2.0, -25.0)


## A gust that reaches the shaft swings the bell and rings it; the chamber answers below.
func ring() -> void:
	rings += 1
	_bell_rest = 9.0
	_bell_swing = 1.0
	if _bell_voice != null:
		_bell_voice.play()
	get_tree().create_timer(0.7, false).timeout.connect(func() -> void:
		if is_instance_valid(_echo_voice):
			_echo_voice.play())


func _physics_process(delta: float) -> void:
	if _bell == null:
		return
	_bell_swing = maxf(0.0, _bell_swing - delta * 0.25)
	_bell.rotation.x = sin(Time.get_ticks_msec() * 0.003) * 0.12 * _bell_swing
	_bell_rest = maxf(0.0, _bell_rest - delta)
	if not active:
		return
	var weather := get_node_or_null(^"/root/Weather")
	if weather != null and weather.gust > 0.55 and _bell_rest <= 0.0:
		ring()
	# Rain shows at the gorge mouth only.
	if weather != null and is_instance_valid(player):
		weather.local_rain = 0.45 if to_local(player.global_position).z > -7.0 else 0.0
