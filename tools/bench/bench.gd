extends Node3D
## Benchmark run: plays the expedition from the cleared court along the whole route without
## input and reports frame times per stretch. Run it on the machine you want to measure:
##
##   Godot editor: open tools/bench/bench.tscn, Run Current Scene (F6 / Cmd+R)
##   Command line: <godot> --path <project> res://tools/bench/bench.tscn
##
## Vsync is off for the run so the numbers show how much time a frame really takes (headroom),
## not the display's 16.7 ms. The hero cannot die; foes fight as usual. The report goes to the
## console and to user://bench.txt (macOS: ~/Library/Application Support/Godot/app_userdata/
## souls/bench.txt; Windows: %APPDATA%/Godot/app_userdata/souls/bench.txt).
##
## Stretches:
##   streaming   the forest and both zones build in the background while the hero waits in the court
##   portal      the pass through the eclipse and the first seconds in the forest
##   forest      the road from the stones to the bonfire clearing, ambushes included
##   crossing    down the slope, over both walks and up the steps
##   belfry      the gorge, the tunnel, the chamber, the stairs, the bell hall, the exit

const EXPEDITION := "res://scenes/expedition/boss_court.tscn"
const SPEED := 5.5
const REPORT := "user://bench.txt"

var host: Node
var hero: CharacterBody3D
var _stretch := ""
var _samples := {}
var _order: Array[String] = []
var _last_usec := 0
var _path: Array[Vector3] = []
var _path_index := 0
var _lines: Array[String] = []


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	host = (load(EXPEDITION) as PackedScene).instantiate()
	add_child(host)
	hero = host.get_node("Player")
	_run.call_deferred()


func _run() -> void:
	await _frames(30)
	var combat := hero.get_node("Combat")
	combat.max_health = 1e9
	combat.health = 1e9
	_say("Souls benchmark · %s · %s · %s · %d x %d · physics %d Hz" % [Time.get_datetime_string_from_system(), OS.get_name(),
			RenderingServer.get_video_adapter_name(), get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y, Engine.physics_ticks_per_second])
	# Streaming: the court is won, the gate opens and the forest builds behind it.
	_begin("streaming")
	host._finish(&"victory")
	host.open_gate()
	var waited := 0
	while (host.forest == null or not host.forest.built or not host.forest.combat_ready()) and waited < 3000:
		await get_tree().process_frame
		waited += 1
	await _frames(90)
	# Portal: through the eclipse, then a few seconds standing at the stones.
	_begin("portal")
	host._enter_forest()
	await _frames(240)
	# The road, the crossing and the belfry on foot.
	hero.set_physics_process(false)
	var forest: Node3D = host.forest
	var world = forest.world
	var road: Array[Vector3] = []
	var z := 6.0
	while z > world.CLEARING.z:
		road.append(forest.to_global(world.point(world.road_x(z), z)))
		z -= 4.0
	road.append(forest.to_global(world.point(world.CLEARING.x, world.CLEARING.z)))
	await _walk("forest", road)
	var crossing: Node3D = forest.crossing
	var walk: Array[Vector3] = [forest.to_global(world.point(world.CLEARING.x, world.MIN.y + 6.0))]
	for p in [Vector3(0, 0, -1.5), Vector3(0, -3, -14), Vector3(0, -3, -40), Vector3(0, -3, -58), Vector3(0, -3, -84.5),
			Vector3(0, 1, -92.5), Vector3(0, 1, -97.5)]:
		walk.append(crossing.to_global(p))
	await _walk("crossing", walk)
	var belfry: Node3D = forest.belfry
	walk = []
	for p in [Vector3(0, 0, -1), Vector3(0, 0, -6), Vector3(0, -4, -18), Vector3(0, -4, -26), Vector3(0, -4, -33.4),
			Vector3(0, -1, -38.4), Vector3(0, -1, -45), Vector3(0, -1, -51.1), Vector3(0, 2, -56.1), Vector3(0, 2, -59)]:
		walk.append(belfry.to_global(p))
	await _walk("belfry", walk)
	_report()
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _walk(stretch: String, points: Array[Vector3]) -> void:
	hero.global_position = points[0]
	hero.reset_physics_interpolation()
	_path = points
	_path_index = 1
	_begin(stretch)
	while _path_index < _path.size():
		await get_tree().physics_frame
	_path = []


## Carries the hero along the path at a running pace, the camera looking ahead.
func _physics_process(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		return
	var target := _path[_path_index]
	var step := target - hero.global_position
	var travel := SPEED * delta
	if step.length() <= travel:
		hero.global_position = target
		_path_index += 1
		return
	hero.global_position += step.normalized() * travel
	var flat := Vector3(step.x, 0, step.z)
	if flat.length() > 0.01:
		var yaw := atan2(-flat.x, -flat.z)
		hero.get_node("Heading").rotation.y = yaw
		var rig := hero.get_node("CameraRig") as Node3D
		rig.rotation.y = lerp_angle(rig.rotation.y, yaw, 1.0 - exp(-3.0 * delta))


func _begin(stretch: String) -> void:
	_close_stretch()
	_stretch = stretch
	if not _samples.has(stretch):
		_samples[stretch] = {"ms": [], "slow": [], "shaders_at_start": _shader_count(), "shaders": 0, "cpu": 0.0, "gpu": 0.0, "draws": 0, "max_draws": 0, "objects": 0}
		_order.append(stretch)
	_last_usec = Time.get_ticks_usec()


func _close_stretch() -> void:
	if _samples.has(_stretch):
		_samples[_stretch].shaders = _shader_count() - int(_samples[_stretch].shaders_at_start)


## Compiled shader programs in the on-disk cache: the growth over a stretch is how many shaders
## were compiled there (on a first run, or with the cache cleared).
static func _shader_count(path: String = "user://shader_cache") -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var count := dir.get_files().size()
	for sub in dir.get_directories():
		count += _shader_count(path.path_join(sub))
	return count


func _process(_delta: float) -> void:
	if _stretch.is_empty():
		return
	var now := Time.get_ticks_usec()
	var sample: Dictionary = _samples[_stretch]
	var ms := (now - _last_usec) / 1000.0
	(sample["ms"] as Array).append(ms)
	_last_usec = now
	if ms > 16.7:
		# What the build and the game marked in this frame and the one before (Perf.mark).
		var perf := get_node_or_null(^"/root/Perf")
		var marks := PackedStringArray()
		if perf != null:
			for f in [perf._frame - 1, perf._frame]:
				if perf._marks.has(f):
					marks.append_array(perf._marks[f])
		(sample["slow"] as Array).append([ms, ", ".join(marks)])
	var viewport := get_viewport().get_viewport_rid()
	sample.cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
	sample.gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	sample.draws += draws
	sample.max_draws = maxi(sample.max_draws, draws)
	sample.objects += int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))


func _report() -> void:
	_say("")
	_say("%-10s %6s %6s %6s %6s %7s %5s %5s %6s %6s %6s %6s" % ["stretch", "frames", "avg", "p50", "p95", "p99", "max", ">20", ">33", "render", "gpu", "draws"])
	for stretch in _order:
		var sample: Dictionary = _samples[stretch]
		var ms: Array = sample.ms
		if ms.is_empty():
			continue
		var sorted := ms.duplicate()
		sorted.sort()
		var total := 0.0
		var over20 := 0
		var over33 := 0
		for v in ms:
			total += v
			over20 += 1 if v > 20.0 else 0
			over33 += 1 if v > 33.3 else 0
		var n := ms.size()
		_say("%-10s %6d %6.1f %6.1f %6.1f %7.1f %5.0f %5d %5d %6.1f %6.1f %6.0f %7d" % [stretch, n, total / n, sorted[n / 2],
				sorted[mini(n - 1, int(n * 0.95))], sorted[mini(n - 1, int(n * 0.99))], sorted[n - 1], over20, over33,
				sample.cpu / n, sample.gpu / n, float(sample.draws) / n, sample.shaders])
	_say("")
	_say("Slowest frames and what was marked in them:")
	for stretch in _order:
		var slow: Array = _samples[stretch].slow
		slow.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for entry: Array in slow.slice(0, 5):
			_say("  %-10s %6.1f ms  %s" % [stretch, entry[0], entry[1] if not String(entry[1]).is_empty() else "-"])
	_say("")
	_say("Times in ms per frame, vsync off. 60 fps needs every frame under 16.7 ms; >20 and >33 count")
	_say("frames slower than that. render and gpu are the renderer's own CPU and GPU time; draws is draw")
	_say("calls per frame; shaders is how many shader programs were compiled during the stretch")
	_say("(only meaningful on a first run: delete user://shader_cache to measure it again).")
	_say("Hitches with their causes are also in user://hitches.log. Run with -- --no-warmup to")
	_say("skip the shader warm-up at the portal, for comparison.")
	var file := FileAccess.open(REPORT, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		_say("Report saved to " + ProjectSettings.globalize_path(REPORT))


func _say(line: String) -> void:
	_lines.append(line)
	print(line)
