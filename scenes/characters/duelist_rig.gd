extends Node3D
## Original jointed court duelist. All action tracks use normalized one-second timelines.
## Combat owns the clock, including pauses, interruptions and recovery.
@export var guard_variant := false

@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var player: AnimationPlayer = $AnimationPlayer

var gait_clock := 0.0
var breath_clock := 0.0
var last_clip: StringName = &""
var cloth: StandardMaterial3D
var trim: StandardMaterial3D
var iron: StandardMaterial3D
var leather: StandardMaterial3D
var linen: StandardMaterial3D
var blade: StandardMaterial3D

func _ready() -> void:
	cloth = _material("875339" if guard_variant else "276258")
	trim = _material("ce9c65" if guard_variant else "d0aa68", 0.32)
	iron = _material("94715e" if guard_variant else "71818a", 0.48)
	leather = _material("3d3132")
	linen = _material("a08a72" if guard_variant else "9ab3ab")
	blade = _material("d5ddd6", 0.45)
	_dress()
	player.add_animation_library(&"", preload("res://scenes/characters/duelist_poses.gd").create(skeleton))
	apply_motion(&"locomotion", 0.0, Vector2.ZERO, 0.0)

func _material(html: String, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(html)
	mat.metallic = metal
	mat.roughness = 0.76 - metal * 0.7
	return mat

func _part(joint: String, label: String, mesh: Mesh, mat: Material, offset: Vector3,
		angles := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = mat
	skeleton.get_node(joint).add_child(part)
	part.position = offset
	part.rotation_degrees = angles
	return part

## Faceted loft. Each cross section is (height, half width, half depth, depth offset).
func _loft(joint: String, label: String, mat: Material, sections: Array, sides := 8,
		offset := Vector3.ZERO, angles := Vector3.ZERO) -> MeshInstance3D:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(-1)
	var rings: Array[PackedVector3Array] = []
	for section: Vector4 in sections:
		var ring := PackedVector3Array()
		for i in sides:
			var angle := TAU * (i + (0.0 if sides == 4 else 0.5)) / sides
			ring.append(Vector3(sin(angle) * section.y, section.x,
					cos(angle) * section.z + section.w))
		rings.append(ring)
	for j in range(rings.size() - 1):
		for i in sides:
			var n := (i + 1) % sides
			for p: Vector3 in [rings[j][i], rings[j + 1][i], rings[j][n],
					rings[j][n], rings[j + 1][i], rings[j + 1][n]]:
				builder.add_vertex(p)
	for i in range(1, sides - 1):
		for p: Vector3 in [rings[0][0], rings[0][i], rings[0][i + 1],
				rings[-1][0], rings[-1][i + 1], rings[-1][i]]:
			builder.add_vertex(p)
	builder.generate_normals()
	return _part(joint, label, builder.commit(), mat, offset, angles)

func _box(joint: String, label: String, size: Vector3, mat: Material, offset: Vector3,
		angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_part(joint, label, mesh, mat, offset, angles)

func _dress() -> void:
	_loft("Pelvis", "SplitTunic", cloth, [Vector4(-.21,.26,.18,.015),
			Vector4(-.02,.22,.15,0), Vector4(.1,.20,.14,0)])
	_loft("Chest", "Cuirass", iron, [Vector4(-.10,.20,.14,0), Vector4(.06,.245,.165,0),
			Vector4(.22,.30,.18,-.015), Vector4(.28,.18,.125,0)])
	_loft("Pelvis","WaistBelt",leather,[Vector4(.017,.222,.157,0),Vector4(.095,.212,.157,0)])
	_box("Pelvis","Clasp",Vector3(.08,.056,.028),trim,Vector3(.025,.057,-.153))
	_box("Chest","Baldric", Vector3(.063,.41,.032),leather,Vector3(0,.11,-.16), Vector3(-5,0,-33))
	_loft("Chest","Gorget",trim,[Vector4(.24,.18,.145,0),Vector4(.30,.16,.14,0)])
	_loft("Cape","FoldedMantle",cloth,[Vector4(-.56,.25,.046,.19),
			Vector4(-.42,.284,.068,.158), Vector4(-.17,.294,.10,.085),
			Vector4(-.02,.323,.145,.02), Vector4(.046,.17,.11,0)])
	for side in [-1,1]:
		var s := "L" if side < 0 else "R"
		_loft("Thigh"+s,"Leggings",leather,[Vector4(-.375,.09,.09,0),
				Vector4(-.09,.13,.125,0),Vector4(.05,.115,.11,0)])
		_loft("Shin"+s,"Greave",iron,[Vector4(-.32,.072,.072,0),
				Vector4(-.13,.096,.109,.014),Vector4(-.025,.09,.107,-.008),
				Vector4(.031,.058,.065,0)])
		_loft("Foot"+s,"Boot",leather,[Vector4(-.076,.105,.179,-.046),
				Vector4(-.036,.103,.176,-.044),Vector4(.085,.077,.082,.012)])
		_loft("Arm"+s,"Sleeve",cloth,[Vector4(-.268,.065,.068,0),
				Vector4(-.058,.104,.095,0), Vector4(.033,.093,.087,0)])
		var broad := 1.22 if side < 0 or guard_variant else 1.0
		_loft("Arm"+s,"Pauldron",iron,[Vector4(-.09,.119*broad,.114,0),
				Vector4(-.03,.125*broad,.129,0),Vector4(.065,.097*broad,.094,0),
				Vector4(.093,.052,.050,0)])
		_loft("Elbow"+s,"Gauntlet",iron,[Vector4(-.22,.060,.058,0),
				Vector4(-.092,.083,.078,0),Vector4(.012,.066,.063,0)])
		_loft("Hand"+s,"Glove",leather,[Vector4(-.083,.051,.050,-.006),
				Vector4(-.021,.068,.068,0),Vector4(.025,.061,.054,0)])
	if guard_variant:
		_loft("Head","Helm",iron,[Vector4(-.03,.154,.145,0),Vector4(.105,.177,.167,0),
				Vector4(.22,.15,.144,.009),Vector4(.29,.044,.065,.016)])
		_loft("Head","HelmetBrim",trim,[Vector4(.112,.185,.182,0),Vector4(.149,.181,.178,0)])
		_box("Head","VisorSlot",Vector3(.216,.032,.018),leather,Vector3(0,.088,-.151))
		_box("Head","Nasal",Vector3(.031,.11,.026),iron,Vector3(0,.07,-.167))
	else:
		_loft("Head","Hood",cloth,[Vector4(-.04,.173,.166,.012),Vector4(.105,.183,.182,.008),
				Vector4(.205,.145,.160,.035),Vector4(.259,.060,.09,.078)])
		_loft("Head","ShadowedFace",leather,[Vector4(-.009,.082,.029,0),
				Vector4(.092,.125,.036,0),Vector4(.162,.096,.031,0)],6,Vector3(0,0,-.145))
		_loft("Head","Scarf",linen,[Vector4(-.043,.151,.149,-.013),
				Vector4(.017,.149,.157,-.016),Vector4(.042,.140,.15,-.015)])
	# Grip along local -Z. The sword's diamond cross section carries light on each face.
	_box("HandR","Grip",Vector3(.036,.042,.19),leather,Vector3(0,-.035,-.013))
	_box("HandR","Pommel",Vector3(.062,.064,.063),trim,Vector3(0,-.035,.104),Vector3(0,0,45))
	_box("HandR","Crossguard",Vector3(.267,.043,.051),trim,Vector3(0,-.035,-.117))
	_loft("HandR","Sword",blade,[Vector4(0,.061,.021,0),Vector4(.10,.051,.016,0),
			Vector4(.76,.034,.011,0),Vector4(.91,.001,.001,0)],4,
			Vector3(0,-.035,-.133),Vector3(-90,0,0))

func apply_motion(clip: StringName, phase: float, local_motion: Vector2, delta: float) -> void:
	if not is_node_ready() and skeleton == null:
		return
	breath_clock = fmod(breath_clock + delta, TAU * 20.0)
	if clip == &"locomotion" or not player.has_animation(clip):
		if last_clip != &"locomotion":
			player.stop()
			skeleton.reset_bone_poses()
		_locomote(local_motion, delta)
		last_clip = &"locomotion"
		return
	if clip != last_clip:
		skeleton.reset_bone_poses()
		player.play(clip)
		last_clip = clip
	player.seek(clampf(phase, 0.0, 1.0), true)

func _rotate_bone(joint: String, angles: Vector3) -> void:
	skeleton.set_bone_pose_rotation(skeleton.find_bone(joint),
			Basis.from_euler(angles * (PI / 180.0)).get_rotation_quaternion())

func _locomote(motion: Vector2, delta: float) -> void:
	var speed := minf(motion.length(), 1.0)
	gait_clock = fmod(gait_clock + delta * lerpf(5.0, 10.0, speed), TAU)
	var step := sin(gait_clock)
	var breathe := sin(breath_clock * 2.7)
	var pelvis := skeleton.find_bone("Pelvis")
	var origin := skeleton.get_bone_rest(pelvis).origin
	origin.y += breathe * .007 + speed * (.013 * cos(gait_clock * 2.0) - .026)
	skeleton.set_bone_pose_position(pelvis, origin)
	_rotate_bone("Chest",Vector3(-4.0 - speed * 4.0, -9.0 + step * speed * 7.0, motion.x * -4))
	_rotate_bone("Cape",Vector3(-7.0 - speed * (10.0 + absf(step) * 8), 0, motion.x * 6))
	_rotate_bone("Head", Vector3(4.0 + breathe, 5.0, 0))
	for sign_value in [-1,1]:
		var side := "L" if sign_value < 0 else "R"
		var beat: float = step * sign_value
		var lift := maxf(0, beat) * speed
		_rotate_bone("Thigh"+side,Vector3(7 - beat * motion.y * 31 + lift * 10,
				0, sign_value * 4 + beat * motion.x * 26))
		_rotate_bone("Shin"+side,Vector3(-12 - lift * 29, 0, 0))
		_rotate_bone("Foot"+side,Vector3(5 + beat * motion.y * 15 + lift * 12,0,0))
		_rotate_bone("Arm"+side,Vector3(8 + beat * motion.y * 15,0,sign_value * 11))
		_rotate_bone("Elbow"+side,Vector3(28 if sign_value > 0 else 19,0,0))
