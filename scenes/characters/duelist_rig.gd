extends Node3D
## Original jointed court duelist. All action tracks use normalized one-second timelines.
## Combat owns the clock, including pauses, interruptions and recovery.
@export var guard_variant := false
@export_enum("Sword", "Spear", "Javelin", "SwordShield") var equipment: int = 0

const MOTION: AnimationLibrary = preload("res://assets/animations/quaternius_humanoid.res")
const POSES = preload("res://scenes/characters/duelist_poses.gd")

@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var player: AnimationPlayer = $AnimationPlayer

var gait_clock := 0.0
var breath_clock := 0.0
var stride := Vector2.ZERO
var blend_start: Array[Quaternion] = []
var blend_pelvis := Vector3.ZERO
var blend_remaining := 0.0
var blend_duration := 0.09
var held_javelin: Array[MeshInstance3D] = []
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
	player.add_animation_library(&"", POSES.create(skeleton))
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
	if equipment == 1 or equipment == 2:
		var length := 1.05 if equipment == 1 else 0.78
		held_javelin.append(_loft("HandR","AshShaft",leather,[Vector4(-.63,.024,.024,0),
				Vector4(length,.022,.022,0)],8,Vector3(0,-.035,0),Vector3(-90,0,0)))
		held_javelin.append(_loft("HandR","Socket",trim,[Vector4(length-.12,.035,.035,0),
				Vector4(length+.02,.031,.031,0)],8,Vector3(0,-.035,0),Vector3(-90,0,0)))
		held_javelin.append(_loft("HandR","LeafPoint",blade,[Vector4(length,.032,.018,0),
				Vector4(length+.055,.07,.022,0), Vector4(length+.29,.001,.001,0)],4,
				Vector3(0,-.035,0),Vector3(-90,0,0)))
		return
	if equipment == 3:
		_loft("ElbowL","Shield",iron,[Vector4(-.45,.026,.034,0),Vector4(-.28,.185,.056,0),
				Vector4(.085,.221,.063,0),Vector4(.155,.171,.055,0)],6,Vector3(-.065,-.065,-.09))
		_box("ElbowL","ShieldSpine",Vector3(.035,.46,.025),trim,Vector3(-.065,-.17,-.15))
	# Grip along local -Z. The sword's diamond cross section carries light on each face.
	_box("HandR","Grip",Vector3(.036,.042,.19),leather,Vector3(0,-.035,-.013))
	_box("HandR","Pommel",Vector3(.062,.064,.063),trim,Vector3(0,-.035,.104),Vector3(0,0,45))
	_box("HandR","Crossguard",Vector3(.267,.043,.051),trim,Vector3(0,-.035,-.117))
	_loft("HandR","Sword",blade,[Vector4(0,.061,.021,0),Vector4(.10,.051,.016,0),
			Vector4(.76,.034,.011,0),Vector4(.91,.001,.001,0)],4,
			Vector3(0,-.035,-.133),Vector3(-90,0,0))

func apply_motion(clip: StringName, phase: float, local_motion: Vector2, delta: float) -> void:
	if skeleton == null:
		return
	phase = clampf(phase, 0.0, 1.0)
	if clip != &"jump" and clip != &"locomotion" and not player.has_animation(clip):
		clip = &"locomotion"
	if clip != last_clip:
		blend_remaining = 0.0
		if not last_clip.is_empty():
			blend_duration = 0.11 if clip == &"locomotion" else 0.075
			blend_remaining = blend_duration
			blend_pelvis = skeleton.get_bone_pose_position(0)
			blend_start.clear()
			for i in skeleton.get_bone_count():
				blend_start.append(skeleton.get_bone_pose_rotation(i))
		player.stop()
		if player.has_animation(clip):
			player.play(clip)
		last_clip = clip
	breath_clock = fposmod(breath_clock + delta / 3.4, 1.0)
	match clip:
		&"locomotion":
			_locomote(local_motion,delta)
		&"jump":
			_jump(phase)
		_:
			player.seek(phase,true)
	if equipment == 2:
		for piece in held_javelin:
			piece.visible = clip != &"enemy_throw" or phase < 0.44 or phase > 0.94
	if blend_remaining > 0.0:
		blend_remaining = maxf(0.0, blend_remaining - delta)
		var weight := smoothstep(0,1,1.0 - blend_remaining / blend_duration)
		skeleton.set_bone_pose_position(0,blend_pelvis.lerp(skeleton.get_bone_pose_position(0),weight))
		for i in skeleton.get_bone_count():
			skeleton.set_bone_pose_rotation(i,blend_start[i].slerp(skeleton.get_bone_pose_rotation(i),weight))

func _jump(phase: float) -> void:
	# Overlap the three source clips so contact and flight meet without a pose cut.
	var launch := MOTION.get_animation(&"jump_start")
	var flight := MOTION.get_animation(&"jump_air")
	var land := MOTION.get_animation(&"jump_land")
	var a := launch if phase < .50 else flight
	var b := flight if phase < .50 else land
	var launch_t := clampf(phase/.25,0,1)
	var flight_t := clampf((phase-.19)/.64,0,1)
	var land_t := clampf((phase-.77)/.23,0,1)
	var t_a := launch_t if phase < .50 else flight_t
	var t_b := flight_t if phase < .50 else land_t
	var blend := smoothstep(.19,.25,phase) if phase < .50 else smoothstep(.77,.83,phase)
	skeleton.set_bone_pose_position(0,a.position_track_interpolate(0,t_a).lerp(
			b.position_track_interpolate(0,t_b),blend))
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(i,a.rotation_track_interpolate(i+1,t_a).slerp(
				b.rotation_track_interpolate(i+1,t_b),blend))
	_set_cape(-15.0 - 17.0 * sin(phase * PI), 0)

func _locomote(motion: Vector2, delta: float) -> void:
	stride = stride.move_toward(motion.limit_length(),delta * 8.0)
	var speed := stride.length()
	var direction := stride.normalized()
	var backward := -1.0 if direction.y > .35 else 1.0
	gait_clock = fposmod(gait_clock + backward * delta * (0.46 + speed * 1.48) * smoothstep(0,.12,speed),1.0)
	var walk := MOTION.get_animation(&"walk")
	var run := MOTION.get_animation(&"run")
	var idle := MOTION.get_animation(&"idle")
	var run_weight := smoothstep(.40,.91,speed)
	var moving := smoothstep(.01,.34,speed)
	var pelvis := walk.position_track_interpolate(0,gait_clock).lerp(
			run.position_track_interpolate(0,gait_clock),run_weight)
	skeleton.set_bone_pose_position(0,idle.position_track_interpolate(0,breath_clock).lerp(pelvis,moving))
	for i in skeleton.get_bone_count():
		var track := i + 1
		var gait := walk.rotation_track_interpolate(track,gait_clock).slerp(
				run.rotation_track_interpolate(track,gait_clock),run_weight)
		var still := idle.rotation_track_interpolate(track,breath_clock)
		var name_string := String(skeleton.get_bone_name(i))
		var pose := still.slerp(gait,moving)
		if name_string.begins_with("Thigh") and absf(direction.x) > .01:
			# Keep knees forward while the thigh carries each foot sideways across the ground.
			var swing := pose.get_euler()
			swing.z += swing.x * direction.x * moving * 0.88
			swing.x *= lerpf(1.0,.27,direction.x*direction.x)
			pose = Basis.from_euler(swing).get_rotation_quaternion()
		elif name_string in ["ArmR","ElbowR","ArmL","ElbowL"]:
			var stance: Vector3 = POSES.STANCE[name_string]
			var ready := Basis.from_euler(stance * (PI/180)).get_rotation_quaternion()
			var weapon_arm := name_string.ends_with("R") or equipment == 3
			pose = ready.slerp(pose,(.25 if weapon_arm else .70) + speed * .23)
		skeleton.set_bone_pose_rotation(i,pose)
	# The supporting boot sets the standing height after the change in limb lengths.
	var sole := INF
	for foot in ["FootL","FootR"]:
		var foot_pose := skeleton.get_bone_global_pose(skeleton.find_bone(foot))
		for z in [-.16,.08]:
			sole = minf(sole,(foot_pose * Vector3(0,-.076,z)).y)
	var height := skeleton.get_bone_pose_position(0)
	height.y -= clampf(sole,-.18,.18) * (1.0 - .40 * run_weight)
	skeleton.set_bone_pose_position(0,height)
	_set_cape(-7 - speed * (15 + 6*cos(gait_clock*TAU*2)), stride.x * 7)

func _set_cape(pitch: float, bank: float) -> void:
	skeleton.set_bone_pose_rotation(skeleton.find_bone("Cape"),
			Basis.from_euler(Vector3(pitch,0,bank) * (PI/180)).get_rotation_quaternion())
