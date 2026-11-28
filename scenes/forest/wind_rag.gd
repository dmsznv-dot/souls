extends Node3D
## A strip of torn cloth tied to a post: four segments that stream out with the shared wind and
## snap on gusts. The first readable gust on the patrol trail.

var _segments: Array[Node3D] = []
var _clock := randf() * 10.0


func _ready() -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.45, 0.12, 0.1)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var parent: Node3D = self
	for i in 4:
		var joint := Node3D.new()
		parent.add_child(joint)
		joint.position = Vector3(0, 0, 0) if i == 0 else Vector3(0, 0, 0.22)
		var quad := MeshInstance3D.new()
		var plane := QuadMesh.new()
		plane.size = Vector2(0.22, 0.16 - i * 0.02)
		quad.mesh = plane
		quad.material_override = cloth
		joint.add_child(quad)
		quad.position = Vector3(0, 0, 0.11)
		quad.rotation_degrees = Vector3(0, 90, 0)
		_segments.append(joint)
		parent = joint


func _process(delta: float) -> void:
	_clock += delta
	var weather := get_node_or_null(^"/root/Weather")
	var wind: float = weather.wind if weather != null else 0.3
	var gust: float = weather.gust if weather != null else 0.0
	var direction: Vector3 = weather.wind_direction if weather != null else Vector3.FORWARD
	var local := global_basis.inverse() * direction
	var yaw := atan2(local.x, local.z)
	for i in _segments.size():
		var flutter := sin(_clock * (6.0 + gust * 8.0) - i * 1.1) * (0.25 + 0.5 * gust)
		var droop := (1.0 - clampf(wind + gust * 0.5, 0.0, 1.0)) * 0.5
		_segments[i].rotation = Vector3(droop * (1.0 if i == 0 else 0.3), (yaw if i == 0 else 0.0) + flutter * 0.6, 0.0)
