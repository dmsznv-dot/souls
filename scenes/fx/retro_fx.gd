extends CanvasLayer
## Autoload. Draws the retro post-process between the 3D frame and the HUD (HUD layers are 1+).
## F3 toggles the effect. flash() tints the frame for heavy impacts without strobing.

const SHADER := preload("res://scenes/fx/retro.gdshader")
const MAX_FLASHES_PER_SECOND := 3.0

var enabled: bool = true:
	set(value):
		enabled = value
		if _rect != null:
			_rect.visible = value

var _rect: ColorRect
var _material: ShaderMaterial
var _flash: float
var _last_flash_ms: int = -100000


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "RetroScreen"
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		enabled = not enabled


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / maxf(Engine.time_scale, 0.05) * 5.0)
		_material.set_shader_parameter(&"flash", _flash)


## Brief full-screen tint. Rate-limited to stay under three flashes per second (WCAG 2.3.1).
func flash(strength: float, color: Color = Color(1.0, 0.55, 0.3)) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_flash_ms < 1000.0 / MAX_FLASHES_PER_SECOND:
		return
	_last_flash_ms = now
	_flash = clampf(strength, 0.0, 0.35)
	_material.set_shader_parameter(&"flash_color", color)
	_material.set_shader_parameter(&"flash", _flash)


func set_parameter(parameter: StringName, value: Variant) -> void:
	_material.set_shader_parameter(parameter, value)
