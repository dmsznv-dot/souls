extends MeshInstance3D
## Ribbon between successive blade base and tip positions. The swing reads as coming from the
## edge: the arc is drawn exactly where the blade travelled during the strike.

const LIFETIME := 0.15
const MAX_SAMPLES := 24

var color: Color = Color(0.95, 0.88, 0.76, 0.55)
var _bases := PackedVector3Array()
var _tips := PackedVector3Array()
var _times := PackedFloat64Array()
var _immediate := ImmediateMesh.new()
var _clock: float


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _immediate
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material_override = mat


## Called once per physics step by the rig with the blade's current world segment.
func sample(base: Vector3, tip: Vector3, emitting: bool, delta: float) -> void:
	_clock += delta
	if emitting:
		_bases.append(base)
		_tips.append(tip)
		_times.append(_clock)
		if _bases.size() > MAX_SAMPLES:
			_bases.remove_at(0)
			_tips.remove_at(0)
			_times.remove_at(0)
	while not _times.is_empty() and _clock - _times[0] > LIFETIME:
		_bases.remove_at(0)
		_tips.remove_at(0)
		_times.remove_at(0)
	_draw()


func clear() -> void:
	_bases.clear()
	_tips.clear()
	_times.clear()
	_immediate.clear_surfaces()


func _draw() -> void:
	_immediate.clear_surfaces()
	if _bases.size() < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _bases.size():
		var fade := clampf(1.0 - (_clock - _times[i]) / LIFETIME, 0.0, 1.0)
		var tip_color := Color(color, color.a * fade)
		var base_color := Color(color, 0.0)
		_immediate.surface_set_color(base_color)
		_immediate.surface_add_vertex(_bases[i])
		_immediate.surface_set_color(tip_color)
		_immediate.surface_add_vertex(_tips[i])
	_immediate.surface_end()
