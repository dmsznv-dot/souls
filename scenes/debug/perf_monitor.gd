extends CanvasLayer
## Autoload "Perf". Catches hitches on the player's own machine: any frame much longer than the
## recent median is logged with the gameplay events marked in that frame and the two before it,
## the render time, the physics steps it ran and the display refresh rate.
##
## F4 shows the overlay. The log is user://hitches.log
## (macOS: ~/Library/Application Support/Godot/app_userdata/souls/hitches.log).

const LOG_PATH := "user://hitches.log"
const WINDOW := 120
const MIN_HITCH_MS := 25.0

var _times := PackedFloat32Array()
var _last_usec: int
var _frame: int
var _marks: Dictionary = {}
var _recent: Array[String] = []
var _label: Label
var _log: FileAccess
var _last_physics_frames: int
var _hitches: int


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.visible = false
	_label.position = Vector2(12, 96)
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	add_child(_label)
	RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
	if not OS.has_feature("headless") and DisplayServer.get_name() != "headless":
		_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if _log != null:
			_log.store_line("# Souls hitch log · %s · %s · %s · refresh %.0f Hz · physics %d Hz · interpolation %s" % [
				Time.get_datetime_string_from_system(), OS.get_name(), RenderingServer.get_video_adapter_name(),
				DisplayServer.screen_get_refresh_rate(), Engine.physics_ticks_per_second,
				ProjectSettings.get_setting("physics/common/physics_interpolation", false)])
			_log.flush()
	_last_usec = Time.get_ticks_usec()


## Tag the current frame with a gameplay event, so a hitch can be traced to its cause.
func mark(label: StringName) -> void:
	if not _marks.has(_frame):
		_marks[_frame] = PackedStringArray()
	_marks[_frame].append(String(label))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F4:
		_label.visible = not _label.visible


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_frame += 1
	var physics_steps := Engine.get_physics_frames() - _last_physics_frames
	_last_physics_frames = Engine.get_physics_frames()
	var median := _median()
	if _times.size() >= 30 and ms > maxf(MIN_HITCH_MS, median * 1.8):
		_hitches += 1
		var events := PackedStringArray()
		for f in [_frame - 2, _frame - 1, _frame]:
			if _marks.has(f):
				events.append_array(_marks[f])
		var render := RenderingServer.viewport_get_measured_render_time_cpu(get_tree().root.get_viewport_rid())
		var line := "%8.2fs  frame %6.1f ms (median %5.1f)  render %5.1f ms  physics steps %d  events: %s" % [
			now / 1e6, ms, median, render, physics_steps, ", ".join(events) if not events.is_empty() else "-"]
		_recent.push_front(line)
		if _recent.size() > 6:
			_recent.pop_back()
		if _log != null:
			_log.store_line(line)
			_log.flush()
	_times.append(ms)
	if _times.size() > WINDOW:
		_times.remove_at(0)
	for f in _marks.keys():
		if f < _frame - 3:
			_marks.erase(f)
	if _label.visible:
		_label.text = "%.0f fps  ·  %.1f ms (median %.1f)  ·  %d hitches\n%s" % [
			Engine.get_frames_per_second(), ms, median, _hitches, "\n".join(_recent)]


func _median() -> float:
	if _times.is_empty():
		return 16.6
	var sorted := _times.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
