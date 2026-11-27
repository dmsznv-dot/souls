extends Control
## Thin health bars over ordinary foes, drawn in screen space so they stay crisp and the same
## size at any distance. A bar shows once a foe is fighting or hurt, trails a pale "chip" of
## recent damage behind the red, and fades with distance. Bosses (and any foe marked with the
## "boss_bar" meta) keep the large bar at the top of the screen instead.

const RANGE := 16.0
const WIDTH := 58.0
const HEIGHT := 4.0
const CHIP_DELAY := 0.45
const CHIP_RATE := 0.9
const SIGHT_INTERVAL := 0.2
const BACK := Color(0.04, 0.035, 0.05, 0.82)
const FILL := Color(0.78, 0.13, 0.11)
const CHIP := Color(0.95, 0.82, 0.62)
const EDGE := Color(0.95, 0.88, 0.7, 0.9)

## id -> [shown health fraction for the chip, seconds since last damage, last health, seen, sight timer]
var _state: Dictionary = {}
var _bars: Array = []


static func install(parent: Node) -> Control:
	var bars := new()
	bars.name = &"FoeBars"
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bars)
	parent.move_child(bars, 0)
	return bars


func _process(delta: float) -> void:
	_bars.clear()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		queue_redraw()
		return
	var lock: Node3D = null
	var rig := camera.get_parent()
	while rig != null and not &"lock_target" in rig:
		rig = rig.get_parent()
	if rig != null and is_instance_valid(rig.lock_target):
		lock = rig.lock_target
	var alive := {}
	for foe in get_tree().get_nodes_in_group(&"foes"):
		var combat := foe.get_node_or_null(^"Combat")
		if combat == null or bool(foe.get(&"boss_enabled")) or foe.has_meta(&"boss_bar"):
			continue
		var id: int = foe.get_instance_id()
		alive[id] = true
		var fraction: float = clampf(combat.health / combat.max_health, 0.0, 1.0)
		if not _state.has(id):
			_state[id] = [fraction, 10.0, combat.health, false, 0.0]
		var entry: Array = _state[id]
		if combat.health < entry[2]:
			entry[1] = 0.0
		entry[2] = combat.health
		entry[1] += delta
		if entry[1] > CHIP_DELAY:
			entry[0] = move_toward(entry[0], fraction, CHIP_RATE * delta)
		entry[0] = maxf(entry[0], fraction)
		if combat.health <= 0.0 and entry[0] <= fraction + 0.001:
			continue
		var engaged: bool = foe.has_method(&"is_engaged") and foe.is_engaged()
		if not engaged and fraction >= 1.0 and entry[1] > 5.0:
			continue
		var marker := foe.get_node_or_null(^"LockPoint") as Node3D
		var top: Vector3 = (marker.global_position if marker != null else foe.global_position + Vector3.UP * 1.2)
		top += Vector3.UP * (0.55 + 0.35 * maxf(0.0, foe.get_node(^"Heading/Rig").scale.y - 1.0))
		var distance := camera.global_position.distance_to(top)
		if distance > RANGE or camera.is_position_behind(top):
			continue
		entry[4] -= delta
		if entry[4] <= 0.0:
			entry[4] = SIGHT_INTERVAL
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position, top, 1)
			entry[3] = camera.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		if not entry[3]:
			continue
		var alpha := 1.0 - smoothstep(RANGE * 0.7, RANGE, distance)
		var width := WIDTH * (1.35 if combat.max_health >= 120.0 else 1.0)
		_bars.append([camera.unproject_position(top), width, fraction, entry[0], alpha, marker == lock and lock != null])
	for id in _state.keys():
		if not alive.has(id):
			_state.erase(id)
	queue_redraw()


func _draw() -> void:
	for bar: Array in _bars:
		var center: Vector2 = bar[0]
		var width: float = bar[1]
		var origin := (center - Vector2(width * 0.5, HEIGHT * 0.5)).round()
		var alpha: float = bar[4]
		draw_rect(Rect2(origin - Vector2.ONE, Vector2(width, HEIGHT) + Vector2(2, 2)), Color(BACK, BACK.a * alpha))
		draw_rect(Rect2(origin, Vector2(width * bar[3], HEIGHT)), Color(CHIP, alpha))
		draw_rect(Rect2(origin, Vector2(width * bar[2], HEIGHT)), Color(FILL, alpha))
		if bar[5]:
			draw_rect(Rect2(origin - Vector2(2, 2), Vector2(width, HEIGHT) + Vector2(4, 4)), Color(EDGE, alpha), false, 1.0)
