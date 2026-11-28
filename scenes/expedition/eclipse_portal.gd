extends Node3D
## The eclipse ring above the shrine becomes a way out once the ruins are cleared. Its interior
## burns open from the centre in ember cells, like the court's seal, onto a violet vortex.
## Standing at the shrine's foot and pressing interact sends the player through.

signal opened
signal entered

const PORTAL_SHADER := preload("res://scenes/expedition/gate/eclipse_portal.gdshader")
## Ring centre and opening radius in area space (measured from the shrine mesh).
const CENTER := Vector3(0.0, 4.97, -31.2)
const RADIUS := 1.86
## Where the player stands to step through: the foot of the shrine below the ring.
const THRESHOLD := Vector3(0.0, 0.0, -28.3)
const REACH := 3.2

var player: Node3D
var is_open := false
## The host says whether the far side can take the player now (entry ready). The prompt and the
## action use the same check.
var destination_ready: Callable = func() -> bool: return true
## Set once the player steps in, so repeated presses do not start a second crossing.
var locked := false
var amount: float:
	set(value):
		amount = value
		_material.set_shader_parameter(&"open_amount", value)

var _material := ShaderMaterial.new()
var _light: OmniLight3D
var _embers: CPUParticles3D
var _prompt: Label3D


func _ready() -> void:
	_material.shader = PORTAL_SHADER
	var disc := MeshInstance3D.new()
	disc.name = "Vortex"
	var quad := QuadMesh.new()
	quad.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	disc.mesh = quad
	disc.material_override = _material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	disc.position = CENTER
	_light = OmniLight3D.new()
	_light.name = "EclipseLight"
	_light.light_color = Color(0.58, 0.42, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 11.0
	add_child(_light)
	_light.position = CENTER + Vector3(0, 0, 1.2)
	_embers = _make_embers()
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.text = "E / A   Step into the eclipse"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 40
	_prompt.pixel_size = 0.004
	_prompt.outline_size = 8
	_prompt.modulate = Color(0.85, 0.78, 1.0)
	_prompt.visible = false
	add_child(_prompt)
	_prompt.position = THRESHOLD + Vector3(0, 1.8, 0)
	amount = 0.0


func open(duration: float = 3.2) -> void:
	if is_open:
		return
	is_open = true
	_embers.emitting = true
	var tween := create_tween()
	tween.tween_property(self, ^"amount", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_light, ^"light_energy", 4.5, duration)
	tween.tween_callback(func() -> void: opened.emit())


func can_enter() -> bool:
	if locked or not is_open or amount < 0.6 or not is_instance_valid(player):
		return false
	var combat := player.get_node_or_null(^"Combat")
	if combat != null and (combat.health <= 0.0 or combat.action == &"dead"):
		return false
	return to_local(player.global_position).distance_to(THRESHOLD) < REACH and bool(destination_ready.call())


## A crossing that could not finish (the hero died, the far side went away) frees the portal.
func unlock() -> void:
	locked = false


func _process(_delta: float) -> void:
	_prompt.visible = can_enter()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and can_enter():
		get_viewport().set_input_as_handled()
		locked = true
		entered.emit()


func _make_embers() -> CPUParticles3D:
	var embers := CPUParticles3D.new()
	embers.name = "Embers"
	embers.emitting = false
	embers.amount = 40
	embers.lifetime = 2.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = glow
	embers.mesh = quad
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	embers.emission_ring_axis = Vector3(0, 0, 1)
	embers.emission_ring_radius = RADIUS
	embers.emission_ring_inner_radius = RADIUS * 0.85
	embers.emission_ring_height = 0.1
	embers.direction = Vector3(0, 0, 1)
	embers.spread = 60.0
	embers.gravity = Vector3(0, 0.6, 0)
	embers.initial_velocity_min = 0.2
	embers.initial_velocity_max = 0.7
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.35, 1.0))
	ramp.add_point(0.5, Color(0.7, 0.45, 1.0, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.3, 0.2, 0.6, 0.0))
	embers.color_ramp = ramp
	add_child(embers)
	embers.position = CENTER
	return embers
