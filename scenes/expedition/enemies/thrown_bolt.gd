extends Node3D

const AttackData = preload("res://scenes/duel/combat/attack_data.gd")

var _thrower: Node
var _attack: AttackData
var _velocity: Vector3
var _collision_mask: int
var _distance_left: float


func launch(thrower: Node, attack: AttackData, origin: Vector3, direction: Vector3,
		target_mask: int) -> void:
	_thrower = thrower
	_attack = attack
	_velocity = direction * attack.projectile_speed
	_collision_mask = 1 | target_mask
	_distance_left = attack.reach
	global_position = origin
	look_at(origin + direction)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.62, 0.25)
	var bolt := BoxMesh.new()
	bolt.size = Vector3(0.05, 0.05, 0.86)
	bolt.material = glow
	var model := MeshInstance3D.new()
	model.mesh = bolt
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(model)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_thrower) or _thrower.action == &"dead":
		queue_free()
		return
	var start := global_position
	var motion := _velocity * delta
	var finish := start + motion.limit_length(_distance_left)
	var ray := PhysicsRayQueryParameters3D.create(start, finish, _collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var defender: Node = hit.collider.get_node_or_null("Combat")
		if defender != null:
			defender.receive_attack(_thrower, _attack, -_velocity.normalized())
		queue_free()
		return
	global_position = finish
	_distance_left -= motion.length()
	if _distance_left <= 0.0:
		queue_free()
