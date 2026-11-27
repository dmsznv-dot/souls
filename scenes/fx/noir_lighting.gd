extends RefCounted
## Neon-noir lighting in the manner of The Wolf Among Us, inside the retro look: a cold blue
## moon throwing hard, dense shadows, low blue ambience, saturated warm lantern pools that
## flicker, and magenta neon accents that rim silhouettes against a magenta horizon. Materials switch to toon diffuse so
## light falls off in bands instead of gradients.

const MOON := Color(0.52, 0.74, 1.0)
const LANTERN := Color(1.0, 0.66, 0.26)
const NEON := Color(1.0, 0.24, 0.62)
const FlickerScript := preload("res://scenes/fx/lamp_flicker.gd")


## Relights an area. accents: world-space points for magenta neon fills.
static func apply(root: Node, accents: Array = []) -> void:
	for light in root.find_children("*", "DirectionalLight3D", true, false):
		var moon := light as DirectionalLight3D
		moon.light_color = MOON
		moon.light_energy = 1.3
		moon.shadow_opacity = 0.95
		moon.light_angular_distance = 0.0
		moon.rotation_degrees = Vector3(-52, 38, 0)
	for light in root.find_children("*", "OmniLight3D", true, false):
		var lamp := light as OmniLight3D
		if not (lamp.name.begins_with("Lamp") or lamp.name.begins_with("WatchFire")):
			continue
		lamp.light_color = LANTERN
		lamp.light_energy = 6.0
		lamp.omni_range = maxf(lamp.omni_range, 5.0) * 1.7
		lamp.omni_attenuation = 0.9
		lamp.shadow_enabled = false
		if not lamp.has_node("Flicker"):
			var flicker := Node.new()
			flicker.name = "Flicker"
			flicker.set_script(FlickerScript)
			lamp.add_child(flicker)
	for i in accents.size():
		var neon := OmniLight3D.new()
		neon.name = "NeonAccent%d" % i
		neon.light_color = NEON
		neon.light_energy = 3.6
		neon.omni_range = 8.0
		neon.omni_attenuation = 1.1
		root.add_child(neon)
		neon.global_position = accents[i]
	toon(root)


## Toon diffuse and specular on every standard material under root.
static func toon(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		_toon_material(geometry.material_override)
		var mesh_instance := geometry as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			_toon_material(mesh_instance.get_surface_override_material(surface))
			_toon_material(mesh_instance.mesh.surface_get_material(surface))


static func _toon_material(material: Material) -> void:
	var standard := material as BaseMaterial3D
	if standard == null or standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	standard.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	standard.specular_mode = BaseMaterial3D.SPECULAR_TOON
