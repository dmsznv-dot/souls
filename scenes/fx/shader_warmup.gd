extends RefCounted
## Shader warm-up for the Compatibility renderer, which compiles a shader the first time
## something drawn with it reaches the screen (there is no pipeline precompilation in OpenGL).
## Compiled programs are kept in user://shader_cache, so this matters most on a first run, a new
## driver or a new build; it is cheap otherwise.
##
## gather(root) lists one of everything under root that can need its own shader: each material
## on each mesh format (skinned or not), multimesh formats, particles. run() draws them all for
## a few frames in a tiny SubViewport that shares the world, on a render layer the player's
## camera does not see, so the compile happens where the caller wants it (under a veil) instead
## of the first time each thing comes into view. Lights reach the layer like any other, so the
## warm-up runs at two spots, by a fire and in the dark, to compile both lighting variants.

const LAYER := 1 << 19
const SIZE := 0.25


## One entry per distinct shader use under root: [kind, node, material key].
static func gather(root: Node) -> Array:
	var seen := {}
	var items := []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if node is MeshInstance3D:
			var view := node as MeshInstance3D
			if view.mesh == null:
				continue
			for surface in view.mesh.get_surface_count():
				var material := view.material_override
				if material == null:
					material = view.get_surface_override_material(surface)
				if material == null:
					material = view.mesh.surface_get_material(surface)
				var key := [_material_key(material), _format(view.mesh, surface), view.skin != null, view.cast_shadow]
				if not seen.has(key):
					seen[key] = true
					items.append([&"mesh", view, surface, material])
		elif node is MultiMeshInstance3D:
			var many := node as MultiMeshInstance3D
			var multimesh := many.multimesh
			if multimesh == null or multimesh.mesh == null:
				continue
			var key := [&"multi", _material_key(many.material_override), _format(multimesh.mesh, 0),
					multimesh.use_colors, multimesh.use_custom_data]
			if not seen.has(key):
				seen[key] = true
				items.append([&"multi", many])
		elif node is CPUParticles3D or node is GPUParticles3D:
			var mesh: Mesh = node.mesh if node is CPUParticles3D else (node as GPUParticles3D).draw_pass_1
			if mesh == null:
				continue
			var key := [&"particles", node.get_class(), _material_key(mesh.surface_get_material(0)), _material_key(node.material_override)]
			if not seen.has(key):
				seen[key] = true
				items.append([&"particles", node])
	return items


## A mesh's vertex layout: generated meshes report theirs; primitives all share one.
static func _format(mesh: Mesh, surface: int) -> Variant:
	return (mesh as ArrayMesh).surface_get_format(surface) if mesh is ArrayMesh else mesh.get_class()


## Two materials that differ only in their parameters share a shader; the key keeps them apart
## only where the shader differs (for a standard material, the features that change its code).
static func _material_key(material: Material) -> Variant:
	if material == null:
		return null
	if material is ShaderMaterial:
		return (material as ShaderMaterial).shader
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		return [base.get_class(), base.transparency, base.shading_mode, base.diffuse_mode, base.specular_mode,
				base.blend_mode, base.cull_mode, base.depth_draw_mode, base.no_depth_test, base.vertex_color_use_as_albedo,
				base.billboard_mode, base.albedo_texture != null, base.normal_enabled, base.emission_enabled,
				base.disable_receive_shadows, base.disable_ambient_light, base.texture_filter, base.use_point_size,
				base.fixed_size, base.uv1_triplanar, base.roughness_texture != null, base.metallic_texture != null]
	return material


## Draws every item at each spot (global transforms looking at the items) for a few frames.
## Await it. Items are copies; the originals are not touched.
## stand_ins: scenes (foes) whose meshes only exist once they are in the tree; one of each is
## added, asleep and out of every group, at the last spot (meant to be far from the player).
static func run(host: Node, items: Array, spots: Array, frames: int = 3, stand_ins: Array = []) -> void:
	if (items.is_empty() and stand_ins.is_empty()) or not host.is_inside_tree():
		return
	var tree := host.get_tree()
	var main_camera := host.get_viewport().get_camera_3d()
	var saved_mask := 0
	if main_camera != null:
		saved_mask = main_camera.cull_mask
		main_camera.cull_mask &= ~LAYER
	var rigs: Array[Node] = []
	for spot: Transform3D in spots:
		var port := SubViewport.new()
		port.name = "ShaderWarmup"
		port.size = Vector2i(64, 64)
		port.world_3d = host.get_viewport().world_3d
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		host.add_child(port)
		var camera := Camera3D.new()
		camera.cull_mask = LAYER
		camera.fov = 70.0
		camera.far = 20.0
		port.add_child(camera)
		camera.global_transform = spot
		camera.current = true
		var holder := Node3D.new()
		holder.name = "Items"
		port.add_child(holder)
		holder.global_transform = spot * Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.6))
		for item: Array in items:
			var copy := _copy(item)
			if copy != null:
				holder.add_child(copy)
				_layer(copy)
				if item[0] == &"particles":
					copy.set(&"emitting", true)
		if spot == spots[-1]:
			for scene: PackedScene in stand_ins:
				var body := scene.instantiate()
				body.process_mode = Node.PROCESS_MODE_DISABLED
				holder.add_child(body)
				for group in body.get_groups():
					body.remove_from_group(group)
				if body is CollisionObject3D:
					(body as CollisionObject3D).collision_layer = 0
					(body as CollisionObject3D).collision_mask = 0
				_layer(body)
		rigs.append(port)
	for i in frames:
		await tree.process_frame
	for rig in rigs:
		if is_instance_valid(rig):
			rig.queue_free()
	if main_camera != null and is_instance_valid(main_camera):
		main_camera.cull_mask = saved_mask


static func _copy(item: Array) -> Node3D:
	match item[0]:
		&"mesh":
			var source := item[1] as MeshInstance3D
			if not is_instance_valid(source):
				return null
			var view := MeshInstance3D.new()
			view.mesh = source.mesh
			view.skin = source.skin
			view.material_override = item[3]
			view.cast_shadow = source.cast_shadow
			view.scale = Vector3.ONE * _fit(source.mesh.get_aabb())
			return view
		&"multi":
			var source := item[1] as MultiMeshInstance3D
			if not is_instance_valid(source):
				return null
			var multimesh := MultiMesh.new()
			multimesh.transform_format = source.multimesh.transform_format
			multimesh.use_colors = source.multimesh.use_colors
			multimesh.use_custom_data = source.multimesh.use_custom_data
			multimesh.mesh = source.multimesh.mesh
			multimesh.instance_count = 1
			multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _fit(multimesh.mesh.get_aabb())), Vector3.ZERO))
			if multimesh.use_colors:
				multimesh.set_instance_color(0, Color.WHITE)
			var many := MultiMeshInstance3D.new()
			many.multimesh = multimesh
			many.material_override = source.material_override
			many.cast_shadow = source.cast_shadow
			return many
		&"particles":
			var source := item[1] as Node3D
			if not is_instance_valid(source):
				return null
			var copy := source.duplicate(0) as Node3D
			for light in copy.find_children("*", "Light3D", true, false):
				light.free()
			copy.visible = true
			copy.set(&"emitting", false)
			copy.set(&"local_coords", true)
			copy.set(&"preprocess", 0.5)
			copy.set(&"amount", mini(int(copy.get(&"amount")), 4))
			return copy
	return null


static func _fit(box: AABB) -> float:
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	return SIZE / longest if longest > 0.001 else 1.0


static func _layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = LAYER
	for child in node.get_children():
		_layer(child)


## Where to warm up around root: by the fire nearest to near (lit by it) and far below near
## (no fire reaches; only the moon). Camera transforms looking at the spot.
static func spots(root: Node, near: Vector3) -> Array:
	var best: Light3D = null
	for light in root.find_children("*", "OmniLight3D", true, false):
		if best == null or (light as Node3D).global_position.distance_to(near) < best.global_position.distance_to(near):
			best = light
	var result := []
	if best != null:
		var eye := best.global_position + Vector3(0.0, -0.4, 1.7)
		result.append(Transform3D.IDENTITY.looking_at(best.global_position - eye, Vector3.UP).translated(eye))
	var dark := near + Vector3(0.0, -40.0, 0.0)
	result.append(Transform3D(Basis.IDENTITY, dark))
	return result
