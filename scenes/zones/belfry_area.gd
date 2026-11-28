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
## Pillars in the chamber (holding up the roots) and sarcophagi in the bell hall: [at, yaw].
const PILLARS := [Vector3(-4.0, FLOOR_Y, -22.5), Vector3(4.0, FLOOR_Y, -22.5)]
const SARCOPHAGI := [[Vector3(-6.4, HALL_Y, -42.3), 0.0], [Vector3(-6.4, HALL_Y, -45.2), 0.0], [Vector3(6.4, HALL_Y, -46.6), 0.0]]

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
	await pace()
	# The gorge: a level mouth between rock faces, roots arching overhead.
	box(Vector3(0, -0.5, -3.0), Vector3(7.0, 1.0, 6.0), rock)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 3.2, 2.5, -3.0), Vector3(1.0, 6.0, 6.0), rock)
	for k in 3:
		_root(Vector3(-3.0, 4.2 - k * 0.3, -1.0 - k * 2.0), Vector3(3.0, 4.6 - k * 0.2, -1.6 - k * 2.0), 0.22, root_color)
	await pace()
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
	await pace()
	# The lower chamber.
	box(Vector3(0, FLOOR_Y - 0.5, -25.5), Vector3(17.0, 1.0, 15.0), rock)
	box(Vector3(0, FLOOR_Y + 7.3, -25.5), Vector3(17.0, 0.6, 15.0), rock)
	box(Vector3(8.6, FLOOR_Y + 3.5, -25.5), Vector3(0.6, 7.0, 15.0), rock)
	await pace()
	# West wall in pieces around the niche's two openings (z -21 grate, z -29 open).
	box(Vector3(-8.6, FLOOR_Y + 3.5, -18.9), Vector3(0.6, 7.0, 1.8), rock)
	box(Vector3(-8.6, FLOOR_Y + 3.5, -25.0), Vector3(0.6, 7.0, 6.4), rock)
	box(Vector3(-8.6, FLOOR_Y + 3.5, -31.6), Vector3(0.6, 7.0, 2.8), rock)
	box(Vector3(-8.6, FLOOR_Y + 5.0, -21.0), Vector3(0.6, 4.0, 1.6), rock)
	box(Vector3(-8.6, FLOOR_Y + 5.0, -29.0), Vector3(0.6, 4.0, 1.6), rock)
	await pace()
	# Back wall of the chamber beside the stairs, front wall around the crypt mouth.
	await pace()
	# Back wall: left of the stairs and between the stairs and the gallery.
	box(Vector3(-5.4, FLOOR_Y + 3.5, -33.1), Vector3(6.2, 7.0, 0.6), rock)
	box(Vector3(3.9, FLOOR_Y + 3.5, -33.1), Vector3(3.2, 7.0, 0.6), rock)
	await pace()
	# The well between the chamber and the hall: a floor below, walls and a roof around the
	await pace()
	# stairs and the gallery so nothing opens onto the void.
	box(Vector3(3.15, FLOOR_Y - 0.5, -36.4), Vector3(10.9, 1.0, 6.6), rock)
	box(Vector3(-2.45, FLOOR_Y + 4.5, -36.4), Vector3(0.3, 9.0, 6.6), rock)
	box(Vector3(8.6, FLOOR_Y + 4.5, -36.4), Vector3(0.6, 9.0, 6.6), rock)
	box(Vector3(3.15, FLOOR_Y + 9.5, -36.4), Vector3(11.5, 0.6, 6.6), rock)
	box(Vector3(-5.3, FLOOR_Y + 3.5, -17.9), Vector3(6.6, 7.0, 0.6), rock)
	box(Vector3(5.3, FLOOR_Y + 3.5, -17.9), Vector3(6.6, 7.0, 0.6), rock)
	box(Vector3(0, 1.45, -17.9), Vector3(4.0, 3.7, 0.6), rock)
	_niche(rock)
	await pace()
	await pace()
	# The gallery: up the east wall from the chamber floor to the bell hall's level.
	ramp(Vector3(6.6, FLOOR_Y, -19.5), Vector3(6.6, HALL_Y, -29.5), 2.0, 0.6, rock)
	box(Vector3(6.6, HALL_Y - 0.3, -35.5), Vector3(2.0, 0.6, 12.0), rock)
	box(Vector3(5.45, HALL_Y + 0.3, -33.0), Vector3(0.25, 0.6, 7.0), rock)
	await pace()
	# The ritual arch at the foot of the stairs, violet and dormant.
	for side in [-1.0, 1.0]:
		box(Vector3(side * 2.3, FLOOR_Y + 1.8, -32.6), Vector3(0.5, 3.6, 0.5), rock)
	box(Vector3(0, FLOOR_Y + 3.8, -32.6), Vector3(5.1, 0.5, 0.6), rock)
	cold_light(Vector3(0, FLOOR_Y + 2.6, -32.0), 1.4, 4.0, Color(0.55, 0.42, 1.0))
	stairs(Vector3(0, FLOOR_Y, -33.4), Vector3(0, 0, -1), 5.0, HALL_Y - FLOOR_Y, 4.0, 12, rock)
	await pace()
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
	await pace()
	await pace()
	# Moonlight down the shaft: a cold wash on the bell so its silhouette reads from the stairs.
	cold_light(BELL + Vector3(0.6, 2.5, 1.5), 2.2, 9.0, Color(0.5, 0.64, 0.95))
	await pace()
	# Stairs to the exit, a landing under the open sky, a lantern at the door.
	stairs(Vector3(0, HALL_Y, -51.1), Vector3(0, 0, -1), 5.0, EXIT.y - HALL_Y, 3.6, 10, rock)
	box(Vector3(0, EXIT.y - 0.5, -59.0), Vector3(5.0, 1.0, 5.6), rock)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 2.2, EXIT.y + 1.6, -56.4), Vector3(0.5, 3.2, 0.5), rock)
		box(Vector3(side * 2.4, EXIT.y + 2.0, -59.0), Vector3(0.4, 4.0, 5.6), rock)
	box(Vector3(0, EXIT.y + 2.0, -61.8), Vector3(5.0, 4.0, 0.4), null)
	lamp(Vector3(1.8, EXIT.y + 2.1, -56.9), 6.0, 6.0, Color(1.0, 0.58, 0.25), &"lantern")
	await pace()
	# One fire in the chamber; cold glints at the roots; draughts in the openings.
	dress(Vector3(-4.0, FLOOR_Y, -27.0), [{"kind": "campfire", "at": Vector3.ZERO, "lit": true, "camp": false}], 53)
	cold_light(Vector3(6.5, FLOOR_Y + 5.5, -20.0), 1.1, 6.0, Color(0.45, 0.62, 0.7))
	cold_light(Vector3(-6.0, HALL_Y + 6.0, -48.0), 1.0, 7.0, Color(0.45, 0.6, 0.75))
	await pace()
	# Two different spills of debris and a pair of crates in the chamber's corner.
	dress(Vector3(4.5, FLOOR_Y, -31.0), [{"kind": "rubble", "at": Vector3.ZERO, "radius": 1.0, "count": 9, "collide": false}], 61)
	dress(Vector3(-5.0, HALL_Y, -48.5), [{"kind": "bones", "at": Vector3.ZERO, "radius": 1.0, "count": 9, "skulls": 2},
			{"kind": "rubble", "at": Vector3(1.5, 0, 0.5), "radius": 0.6, "count": 5, "collide": false}], 67)
	breakable(&"crate", "chamber/crate_0", Vector3(-6.8, FLOOR_Y, -31.4), 0.2)
	breakable(&"barrel", "chamber/barrel_0", Vector3(-7.2, FLOOR_Y, -19.4), 0.0)
	loop_sound("res://assets/audio/ambience/drips.ogg", Vector3(0, FLOOR_Y + 4.0, -25.0), -5.0, 10.0)
	loop_sound("res://assets/audio/ambience/rain.ogg", Vector3(0, 2.0, -1.0), -8.0, 6.0)
	for at: Vector3 in PILLARS:
		box(at + Vector3(0, 3.5, 0), Vector3(0.9, 7.0, 0.9), null)
	for spec: Array in SARCOPHAGI:
		box(spec[0] + Vector3(0, 0.45, 0), Vector3(0.95, 0.9, 2.15), null, spec[1])


# ---------------------------------------------------------------- detail

func _warmup_samples(holder: Node3D) -> void:
	holder.add_child(Detail.dust(Vector3.ZERO, Vector3.ONE, 2))
	holder.add_child(Detail.light_shaft(Vector3(0, 1, 0), Vector3.ZERO, 0.3, 0.5, Color(0.5, 0.6, 0.85, 0.14)))
	holder.add_child(Props.flames(0.55, 4, 0.07))
	var bell := MeshInstance3D.new()
	bell.mesh = BoxMesh.new()
	bell.material_override = Props.vertex_material(0.35)
	holder.add_child(bell)


## Rock that stops reading as boxes, roots through it, the crypt's ribs and the hall's masonry,
## pillars, sarcophagi, candles, chains, the bell's beam and the shaft of moonlight. Built in
## regions (gorge and tunnel, chamber and niche, hall and exit) so no merged mesh spans too
## many lights. Pure geometry: runs on a worker thread when the zone is streamed.
func _detail_regions() -> Array:
	var regions := []
	# Close to the walls' own stone, so the skin reads as the same rock broken up.
	var rock := Color(0.27, 0.28, 0.25)
	var dressed := Color(0.25, 0.24, 0.23)
	var root_color := Color(0.2, 0.15, 0.11)
	var iron := Color(0.1, 0.1, 0.11)
	var violet := Color(0.45, 0.34, 0.9)

	# Gorge and tunnel.
	var d: Detail = Detail.new(401)
	for side: float in [-1.0, 1.0]:
		d.rock_skin(Vector3(side * 2.7, 2.5, -3.0), Vector3(-side, 0, 0), 6.0, 6.0, 1.4, rock)
		for k in 4:
			d.blob(d.opaque, Vector3(side * d.rng.randf_range(3.0, 3.6), 5.4, -0.8 - k * 1.5), d.rng.randf_range(0.5, 0.8), Vector3(1.2, 0.8, 1.1), rock.darkened(0.1))
		# Tendrils hanging from the arching roots.
		for k in 3:
			var top := Vector3(side * d.rng.randf_range(0.5, 2.2), 4.1 - k * 0.2, -1.2 - k * 2.0)
			d.root(top, top + Vector3(d.rng.randf_range(-0.3, 0.3), -d.rng.randf_range(1.0, 2.2), d.rng.randf_range(-0.3, 0.3)), 0.05, root_color)
		# The crypt arch: capitals, a keystone, a weathered course.
		d.block(d.opaque, Vector3(side * 1.9, 3.05, -6.2), Vector3(0.8, 0.2, 0.8), dressed)
		d.block(d.opaque, Vector3(side * 1.9, 0.1, -6.2), Vector3(0.8, 0.2, 0.8), dressed)
	d.block(d.opaque, Vector3(0, 3.45, -5.82), Vector3(0.6, 0.75, 0.1), dressed.lightened(0.05))
	d.block(d.glow, Vector3(0, 3.45, -5.76), Vector3(0.18, 0.3, 0.02), violet.darkened(0.3))
	for k in 6:
		# Ribs down the tunnel: posts and a beam under the tilted ceiling.
		var t := 0.08 + k * 0.165
		var floor := Vector3(0, -4.0 * t, -6.0 - 12.0 * t)
		for side: float in [-1.0, 1.0]:
			d.block(d.opaque, floor + Vector3(side * 1.7, 1.4, 0), Vector3(0.22, 2.8, 0.32), dressed.darkened(0.1))
		d.block(d.opaque, floor + Vector3(0, 2.86, 0), Vector3(3.7, 0.24, 0.32), dressed.darkened(0.1))
		for side: float in [-1.0, 1.0]:
			d.blob(d.opaque, floor + Vector3(side * 1.45, 0.05, d.rng.randf_range(-0.6, 0.6)), d.rng.randf_range(0.12, 0.22), Vector3(1.2, 0.6, 1.0), rock)
	regions.append([d, "DetailGorge"])

	# Chamber and niche.
	d = Detail.new(402)
	var floor_y := FLOOR_Y + 3.5
	d.rock_skin(Vector3(8.3, floor_y, -25.5), Vector3(-1, 0, 0), 15.0, 7.0, 1.5, rock)
	for piece: Vector2 in [Vector2(-18.0, -19.8), Vector2(-21.8, -28.2), Vector2(-30.2, -33.0)]:
		d.rock_skin(Vector3(-8.3, floor_y, (piece.x + piece.y) * 0.5), Vector3(1, 0, 0), absf(piece.x - piece.y), 7.0, 1.5, rock)
	for piece: Vector2 in [Vector2(-8.5, -2.1), Vector2(2.1, 8.5)]:
		d.rock_skin(Vector3((piece.x + piece.y) * 0.5, floor_y, -18.2), Vector3(0, 0, -1), piece.y - piece.x, 7.0, 1.5, rock)
	for piece: Vector2 in [Vector2(-8.5, -2.5), Vector2(2.5, 5.4)]:
		d.rock_skin(Vector3((piece.x + piece.y) * 0.5, floor_y, -32.8), Vector3(0, 0, 1), piece.y - piece.x, 7.0, 1.5, rock)
	# The ceiling: drips of stone and roots breaking through and down the walls.
	for k in 22:
		var top := Vector3(d.rng.randf_range(-7.8, 7.8), FLOOR_Y + 7.0, d.rng.randf_range(-18.8, -32.2))
		d.rod(d.opaque, top + Vector3(0, 0.1, 0), top - Vector3(0, d.rng.randf_range(0.3, 1.0), 0), d.rng.randf_range(0.12, 0.25), 0.01, rock.darkened(0.1), 5)
	for k in 7:
		var x := -7.5 + k * 2.5
		var from := Vector3(x, FLOOR_Y + 6.95, -18.6)
		var across := Vector3(x + d.rng.randf_range(-1.5, 1.5), FLOOR_Y + 6.8, -25.5 + d.rng.randf_range(-2.0, 2.0))
		d.root(from, across, 0.16, root_color)
		if k % 2 == 0:
			var wall_x := 8.2 if x > 0.0 else -8.2
			d.root(across, Vector3(wall_x, FLOOR_Y + d.rng.randf_range(1.5, 3.5), across.z + d.rng.randf_range(-1.0, 1.0)), 0.12, root_color)
	for at: Vector3 in PILLARS:
		d.pillar(at, 7.0, 0.38, dressed, root_color)
		d.blob(d.opaque, at + Vector3(0.4, 0.05, 0.4), 0.2, Vector3(1.3, 0.5, 1.0), rock)
	# Rubble along the walls and a broken flag floor round the fire; the middle stays clear.
	for k in 26:
		var along := d.rng.randf()
		var at: Vector3
		match k % 4:
			0: at = Vector3(7.9, FLOOR_Y, lerpf(-19.0, -32.0, along))
			1: at = Vector3(-7.9, FLOOR_Y, lerpf(-22.0, -28.0, along))
			2: at = Vector3(lerpf(-7.8, -2.6, along), FLOOR_Y, -32.4)
			_: at = Vector3(lerpf(2.6, 5.0, along), FLOOR_Y, -18.6)
		d.blob(d.opaque, at, d.rng.randf_range(0.12, 0.3), Vector3(1.2, 0.6, 1.0), rock.lightened(0.04))
	d.flagstones(Vector3(-4.0, FLOOR_Y, -27.0), Vector2(2.6, 2.4), Vector2(0.9, 0.7), dressed.darkened(0.15), 0.25)
	for k in 5:
		# Cracks: thin dark seams across the floor.
		var at := Vector3(d.rng.randf_range(-6.0, 6.0), FLOOR_Y + 0.005, d.rng.randf_range(-20.0, -31.0))
		d.block(d.opaque, at, Vector3(d.rng.randf_range(0.8, 1.8), 0.01, 0.04), Color(0.04, 0.04, 0.05), Basis(Vector3.UP, d.rng.randf() * PI))
	# Chains from the ceiling.
	for spec: Array in [[Vector3(2.2, FLOOR_Y + 7.0, -25.5), 3.2], [Vector3(-1.6, FLOOR_Y + 7.0, -29.0), 2.4], [Vector3(-6.0, FLOOR_Y + 7.0, -23.0), 3.8]]:
		d.iron_chain(spec[0], spec[1], iron)
	# The ritual arch: runes down both pillars, candles at their feet.
	for side: float in [-1.0, 1.0]:
		for k in 4:
			d.block(d.glow, Vector3(side * 2.3, FLOOR_Y + 0.8 + k * 0.6, -32.33), Vector3(0.08 + 0.06 * (k % 2), 0.26, 0.02), violet.darkened(0.2 + 0.1 * (k % 3)))
		d.candles(Vector3(side * 1.75, FLOOR_Y, -32.1), 5)
		# Torch sconces on the front wall either side of the crypt mouth.
		var sconce := Vector3(side * 5.0, FLOOR_Y + 2.3, -18.25)
		d.block(d.opaque, sconce + Vector3(0, 0, -0.08), Vector3(0.14, 0.4, 0.12), iron)
		d.rod(d.opaque, sconce + Vector3(0, 0.1, -0.1), sconce + Vector3(0, 0.45, -0.32), 0.04, 0.05, Color(0.22, 0.16, 0.1), 5)
	# The niche: roots in from the ceiling, candles by the bones.
	d.root(Vector3(-12.4, FLOOR_Y + 2.5, -21.0), Vector3(-11.6, FLOOR_Y + 0.2, -23.5), 0.1, root_color)
	d.root(Vector3(-9.6, FLOOR_Y + 2.5, -28.5), Vector3(-12.3, FLOOR_Y + 1.0, -27.0), 0.08, root_color)
	d.candles(Vector3(-12.2, FLOOR_Y, -24.0), 4)
	regions.append([d, "DetailChamber"])

	# Bell hall and exit.
	d = Detail.new(403)
	var hall_mid := HALL_Y + 3.5
	for side: float in [-1.0, 1.0]:
		d.masonry(Vector3(side * 7.7, hall_mid, -45.0), Vector3(-side, 0, 0), 10.8, 7.0, dressed)
	d.masonry(Vector3(-5.1, hall_mid, -39.6), Vector3(0, 0, -1), 5.8, 7.0, dressed)
	d.masonry(Vector3(3.85, hall_mid, -39.6), Vector3(0, 0, -1), 3.3, 7.0, dressed)
	d.masonry(Vector3(-4.9, hall_mid, -50.5), Vector3(0, 0, 1), 6.0, 7.0, dressed)
	d.masonry(Vector3(4.9, hall_mid, -50.5), Vector3(0, 0, 1), 6.0, 7.0, dressed)
	d.flagstones(Vector3(0, HALL_Y, -45.05), Vector2(7.6, 5.4), Vector2(1.1, 0.8), dressed.darkened(0.2), 0.08)
	for spec: Array in SARCOPHAGI:
		d.sarcophagus(spec[0], spec[1], dressed.darkened(0.05))
		d.candles(spec[0] + Basis(Vector3.UP, spec[1]) * Vector3(0.0, 0.92, 0.6), 3)
	# The bell's beam across the shaft, its ends under the roof, iron straps and roots round it.
	var beam_y := BELL.y + 3.65
	d.block(d.opaque, Vector3(0, beam_y, BELL.z), Vector3(6.4, 0.36, 0.42), Color(0.2, 0.15, 0.11))
	for x: float in [-0.35, 0.35]:
		d.block(d.opaque, Vector3(x, beam_y, BELL.z), Vector3(0.06, 0.42, 0.48), iron)
	d.root(Vector3(-2.6, beam_y + 0.3, BELL.z - 1.5), Vector3(1.2, beam_y + 0.1, BELL.z + 0.3), 0.12, root_color)
	d.root(Vector3(2.4, beam_y + 0.5, BELL.z + 2.0), Vector3(0.4, beam_y - 0.4, BELL.z - 0.2), 0.1, root_color)
	for k in 5:
		var top := Vector3(d.rng.randf_range(-2.0, 2.0), beam_y + 0.3, BELL.z + d.rng.randf_range(-2.2, 2.2))
		d.root(top, top + Vector3(d.rng.randf_range(-0.4, 0.4), -d.rng.randf_range(1.2, 2.6), d.rng.randf_range(-0.4, 0.4)), 0.05, root_color)
	# Shards of an older bell fallen by the wall.
	for k in 6:
		var at := Vector3(4.5 + d.rng.randf_range(-0.8, 0.8), HALL_Y + 0.06, -49.3 + d.rng.randf_range(-0.6, 0.6))
		d.block(d.opaque, at, Vector3(d.rng.randf_range(0.2, 0.5), 0.06, d.rng.randf_range(0.15, 0.35)), Color(0.3, 0.24, 0.14),
				Basis.from_euler(Vector3(d.rng.randf_range(-0.3, 0.3), d.rng.randf() * TAU, d.rng.randf_range(-0.3, 0.3))))
	d.frustum(d.opaque, Vector3(5.2, HALL_Y, -48.6), 0.7, 0.4, 0.7, 10, Color(0.26, 0.2, 0.12), Color(0.32, 0.25, 0.15), Vector3(0.25, -0.1, 0))
	# Sconces on the back wall either side of the exit stairs.
	for side: float in [-1.0, 1.0]:
		var sconce := Vector3(side * 3.4, HALL_Y + 2.3, -50.45)
		d.block(d.opaque, sconce + Vector3(0, 0, 0.08), Vector3(0.14, 0.4, 0.12), iron)
		d.rod(d.opaque, sconce + Vector3(0, 0.1, 0.1), sconce + Vector3(0, 0.45, 0.32), 0.04, 0.05, Color(0.22, 0.16, 0.1), 5)
	# The exit: a lintel over the door posts, worn threshold.
	d.block(d.opaque, Vector3(0, EXIT.y + 3.35, -56.4), Vector3(5.2, 0.4, 0.6), dressed)
	d.block(d.opaque, Vector3(0, EXIT.y + 3.62, -56.4), Vector3(1.0, 0.2, 0.62), dressed.lightened(0.05))
	d.block(d.glow, Vector3(0, EXIT.y + 3.35, -56.08), Vector3(0.5, 0.06, 0.02), violet.darkened(0.35))
	d.flagstones(Vector3(0, EXIT.y, -59.0), Vector2(2.4, 2.7), Vector2(0.9, 0.7), dressed.darkened(0.1), 0.15)
	regions.append([d, "DetailHall"])
	return regions


## The sconces' fire, the shaft of moonlight and the dust (main thread, cheap).
func _detail_nodes() -> void:
	for flame: Vector3 in [Vector3(-5.0, FLOOR_Y + 2.82, -18.6), Vector3(5.0, FLOOR_Y + 2.82, -18.6),
			Vector3(-3.4, HALL_Y + 2.82, -50.13), Vector3(3.4, HALL_Y + 2.82, -50.13)]:
		var inward := -0.1 if flame.z > -30.0 else 0.1
		lamp(flame + Vector3(0, 0.15, inward), 4.5 if flame.z > -30.0 else 4.0, 6.5, Color(1.0, 0.55, 0.22), &"torch", "Sconce")
		var fire := Props.flames(0.55, 12, 0.07)
		_content.add_child(fire)
		fire.position = flame
		await pace()
	# Moonlight down the shaft and dust turning in it and in the chamber.
	var shaft := Detail.light_shaft(Vector3(0, HALL_Y + 8.6, -45.0), Vector3(0.3, HALL_Y + 0.05, -44.6), 1.7, 2.6, Color(0.5, 0.6, 0.85, 0.14))
	_visual.add_child(shaft)
	ambient(Detail.dust(Vector3(0, HALL_Y + 3.5, -45.0), Vector3(1.8, 3.4, 1.8), 46))
	ambient(Detail.dust(Vector3(0, FLOOR_Y + 3.0, -25.5), Vector3(7.0, 2.5, 6.0), 30))


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
	_content.add_child(caps)
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
	_content.add_child(view)
	view.transform = Transform3D(Basis.looking_at(run.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), (from + to) * 0.5)


func _make_bell() -> void:
	_bell = Node3D.new()
	_bell.name = "Bell"
	_content.add_child(_bell)
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
	_content.add_child(_echo_voice)
	_echo_voice.position = Vector3(0, FLOOR_Y + 2.0, -25.0)


## A gust that reaches the shaft swings the bell and rings it; the chamber answers below.
func ring() -> void:
	rings += 1
	_bell_rest = 9.0
	_bell_swing = 1.0
	if is_instance_valid(_bell_voice):
		_bell_voice.play()
	get_tree().create_timer(0.7, false).timeout.connect(func() -> void:
		if is_instance_valid(_echo_voice):
			_echo_voice.play())


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_bell):
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
