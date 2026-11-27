extends Node3D
## Original jointed court duelist. All action tracks use normalized one-second timelines.
## Combat owns the clock, including pauses, interruptions and recovery.
## The Skeleton body style dresses the same rig as an armoured low-poly skeleton.
@export var guard_variant := false
@export_enum("Sword", "Spear", "Javelin", "SwordShield") var equipment: int = 0
@export_enum("Duelist", "Skeleton") var body_style: int = 0
## Held weapon. When empty, the equipment slot picks the matching default.
@export var weapon: SoulsWeapon

const MOTION: AnimationLibrary = preload("res://assets/animations/quaternius_humanoid.res")
const POSES = preload("res://scenes/characters/duelist_poses.gd")
const WeaponTrail = preload("res://scenes/combat/weapons/weapon_trail.gd")
const DEFAULT_WEAPONS: Array[SoulsWeapon] = [
	preload("res://scenes/combat/weapons/longsword.tres"),
	preload("res://scenes/combat/weapons/spear.tres"),
	preload("res://scenes/combat/weapons/javelin.tres"),
	preload("res://scenes/combat/weapons/longsword.tres"),
]
## Clips in which the blade cuts. The trail draws over the strike part of their timeline.
const STRIKE_CLIPS: Array[StringName] = [&"light", &"light_b", &"heavy", &"enemy_slash", &"enemy_thrust"]
## Blade paths in skeleton space (metres, facing -Z, right hand on +X). Each key is
## [phase, sword-hand position, blade direction, elbow pole]. Phases follow the combat clock:
## windup ends at 0.44 and the cutting interval runs to 0.66, so the edge crosses the space
## in front of the body exactly while hits can land.
const SWINGS := {
	&"light": [
		[0.0, Vector3(0.22, 0.98, -0.3), Vector3(0.12, 0.5, -1.0), Vector3(0.7, -0.6, 0.3)],
		[0.24, Vector3(0.44, 1.26, 0.04), Vector3(0.55, 0.45, 0.75), Vector3(0.6, -0.5, 0.6)],
		[0.44, Vector3(0.46, 1.12, -0.24), Vector3(0.96, 0.08, -0.3), Vector3(0.5, -0.8, 0.4)],
		[0.55, Vector3(0.14, 1.06, -0.46), Vector3(0.12, -0.04, -1.0), Vector3(0.3, -0.9, 0.3)],
		[0.66, Vector3(-0.22, 1.02, -0.36), Vector3(-0.95, -0.1, -0.3), Vector3(0.1, -0.9, 0.4)],
		[0.8, Vector3(-0.3, 0.98, -0.14), Vector3(-0.72, -0.22, 0.62), Vector3(0.2, -0.9, 0.4)],
		[1.0, Vector3(0.22, 0.98, -0.3), Vector3(0.12, 0.5, -1.0), Vector3(0.7, -0.6, 0.3)],
	],
	&"light_b": [
		[0.0, Vector3(-0.22, 0.98, -0.2), Vector3(-0.6, -0.2, -0.75), Vector3(0.3, -0.9, 0.4)],
		[0.24, Vector3(-0.2, 1.22, -0.06), Vector3(-0.7, 0.42, 0.56), Vector3(0.4, -0.8, 0.5)],
		[0.44, Vector3(-0.3, 1.1, -0.3), Vector3(-0.95, 0.06, -0.32), Vector3(0.3, -0.9, 0.4)],
		[0.55, Vector3(0.06, 1.04, -0.48), Vector3(0.04, -0.06, -1.0), Vector3(0.4, -0.9, 0.3)],
		[0.66, Vector3(0.42, 1.0, -0.34), Vector3(0.95, -0.12, -0.28), Vector3(0.7, -0.7, 0.3)],
		[0.8, Vector3(0.5, 0.96, -0.08), Vector3(0.68, -0.3, 0.62), Vector3(0.7, -0.6, 0.4)],
		[1.0, Vector3(0.22, 0.98, -0.3), Vector3(0.12, 0.5, -1.0), Vector3(0.7, -0.6, 0.3)],
	],
	&"heavy": [
		[0.0, Vector3(0.22, 0.98, -0.3), Vector3(0.12, 0.5, -1.0), Vector3(0.7, -0.6, 0.3)],
		[0.22, Vector3(0.2, 1.5, 0.08), Vector3(0.05, 0.55, 0.83), Vector3(1.0, 0.0, 0.2)],
		[0.44, Vector3(0.16, 1.62, -0.18), Vector3(0.0, 1.0, 0.12), Vector3(1.0, -0.1, 0.1)],
		[0.55, Vector3(0.1, 1.3, -0.48), Vector3(0.0, 0.2, -1.0), Vector3(0.8, -0.5, 0.2)],
		[0.66, Vector3(0.06, 0.86, -0.5), Vector3(0.0, -0.74, -0.67), Vector3(0.6, -0.7, 0.3)],
		[0.82, Vector3(0.08, 0.72, -0.42), Vector3(0.02, -0.9, -0.42), Vector3(0.6, -0.7, 0.3)],
		[1.0, Vector3(0.22, 0.98, -0.3), Vector3(0.12, 0.5, -1.0), Vector3(0.7, -0.6, 0.3)],
	],
	&"enemy_thrust": [
		[0.0, Vector3(0.22, 0.98, -0.3), Vector3(0.12, 0.5, -1.0), Vector3(0.7, -0.6, 0.3)],
		[0.3, Vector3(0.32, 1.1, 0.22), Vector3(0.04, 0.06, -1.0), Vector3(0.6, -0.8, 0.3)],
		[0.44, Vector3(0.34, 1.12, 0.26), Vector3(0.03, 0.05, -1.0), Vector3(0.6, -0.8, 0.3)],
		[0.56, Vector3(0.12, 1.14, -0.5), Vector3(0.0, 0.0, -1.0), Vector3(0.6, -0.8, 0.2)],
		[0.7, Vector3(0.1, 1.12, -0.52), Vector3(0.0, -0.02, -1.0), Vector3(0.6, -0.8, 0.2)],
		[1.0, Vector3(0.22, 0.98, -0.3), Vector3(0.12, 0.5, -1.0), Vector3(0.7, -0.6, 0.3)],
	],
}
## Two-handed guard: both fists stacked on the grip in front of the navel.
const TWO_HAND_STANCE := [Vector3(0.1, 0.96, -0.32), Vector3(0.05, 0.62, -0.78), Vector3(0.8, -0.6, 0.2)]

@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var player: AnimationPlayer = $AnimationPlayer

var gait_clock := 0.0
var breath_clock := 0.0
var stride := Vector2.ZERO
var blend_start: Array[Quaternion] = []
var blend_pelvis := Vector3.ZERO
var blend_remaining := 0.0
var blend_duration := 0.09
var last_clip: StringName = &""
var lean := Vector2.ZERO
var cloth: StandardMaterial3D
var trim: StandardMaterial3D
var iron: StandardMaterial3D
var leather: StandardMaterial3D
var linen: StandardMaterial3D
var blade: StandardMaterial3D
var bone: StandardMaterial3D
var void_black: StandardMaterial3D

var _weapon_root: Node3D
var _blade_base: Marker3D
var _blade_tip: Marker3D
var _trail: MeshInstance3D
var _jaw: Node3D
var _weapon_dropped := false
var _steps: AudioStreamPlayer3D
const STEP_TAKES := ["step_0", "step_1", "step_2", "step_3", "step_4"]

func _ready() -> void:
	cloth = _material("875339" if guard_variant else "276258")
	trim = _material("ce9c65" if guard_variant else "d0aa68", 0.32)
	iron = _material("94715e" if guard_variant else "71818a", 0.48)
	leather = _material("3d3132")
	linen = _material("a08a72" if guard_variant else "9ab3ab")
	blade = _material("d5ddd6", 0.45)
	bone = _material("d8cfb4")
	bone.roughness = 0.88
	void_black = _material("0b0a0d")
	if body_style == 1:
		cloth = _material("1f4a4c")
		iron = _material("767b82", 0.5)
		trim = _material("8a6a3c", 0.4)
		_dress_skeleton()
	else:
		_dress()
	_steps = AudioStreamPlayer3D.new()
	_steps.name = "Steps"
	var takes := AudioStreamRandomizer.new()
	for take: String in STEP_TAKES:
		takes.add_stream(-1, load("res://assets/audio/sfx/%s.wav" % take))
	takes.random_pitch = 1.08
	takes.random_volume_offset_db = 2.0
	_steps.stream = takes
	_steps.bus = &"SFX"
	_steps.volume_db = -9.0
	_steps.unit_size = 4.0
	_steps.max_distance = 22.0
	_steps.max_polyphony = 3
	add_child(_steps)
	_trail = WeaponTrail.new()
	_trail.name = "BladeTrail"
	add_child(_trail)
	set_weapon(weapon if weapon != null else DEFAULT_WEAPONS[equipment])
	player.add_animation_library(&"", POSES.create(skeleton))
	apply_motion(&"locomotion", 0.0, Vector2.ZERO, 0.0)

func _material(html: String, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(html)
	mat.metallic = metal
	mat.roughness = 0.76 - metal * 0.7
	return mat

func _part(joint: String, label: String, mesh: Mesh, mat: Material, offset: Vector3,
		angles := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = mat
	(parent if parent != null else skeleton.get_node(joint)).add_child(part)
	part.position = offset
	part.rotation_degrees = angles
	return part

## Faceted loft. Each cross section is (height, half width, half depth, depth offset).
func _loft(joint: String, label: String, mat: Material, sections: Array, sides := 8,
		offset := Vector3.ZERO, angles := Vector3.ZERO, parent: Node3D = null,
		capped := true) -> MeshInstance3D:
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
	if capped:
		for i in range(1, sides - 1):
			for p: Vector3 in [rings[0][0], rings[0][i], rings[0][i + 1],
					rings[-1][0], rings[-1][i + 1], rings[-1][i]]:
				builder.add_vertex(p)
	builder.generate_normals()
	return _part(joint, label, builder.commit(), mat, offset, angles, parent)

func _box(joint: String, label: String, size: Vector3, mat: Material, offset: Vector3,
		angles := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(joint, label, mesh, mat, offset, angles, parent)

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
	if equipment == 3:
		_loft("ElbowL","Shield",iron,[Vector4(-.45,.026,.034,0),Vector4(-.28,.185,.056,0),
				Vector4(.085,.221,.063,0),Vector4(.155,.171,.055,0)],6,Vector3(-.065,-.065,-.09))
		_box("ElbowL","ShieldSpine",Vector3(.035,.46,.025),trim,Vector3(-.065,-.17,-.15))

## Low-poly armoured skeleton: bare bone where the armour has rotted away.
## Bones run along -Y from each joint; the character faces -Z.
func _dress_skeleton() -> void:
	var rusted := _material("4a4440", 0.35)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.62, 0.98, 0.92)
	# Pelvis, lumbar spine and a hanging tasset skirt.
	_loft("Pelvis","HipBone",bone,[Vector4(-.07,.07,.06,0),Vector4(-.02,.15,.09,0),
			Vector4(.05,.17,.085,.01),Vector4(.08,.09,.06,0)],6)
	for i in 4:
		_box("Pelvis","Lumbar%d" % i,Vector3(.062,.034,.058),bone,Vector3(0,.10 + i * .045,.035))
	_loft("Pelvis","WarBelt",leather,[Vector4(.0,.185,.115,0),Vector4(.06,.18,.112,0)],8)
	_box("Pelvis","BeltBuckle",Vector3(.07,.06,.025),trim,Vector3(0,.03,-.118))
	for side in [-1.0, 1.0]:
		_box("Pelvis","Tasset",Vector3(.15,.2,.03),rusted,Vector3(side * .1,-.08,-.12),Vector3(-9,0,side * 7))
	_box("Pelvis","Loincloth",Vector3(.13,.32,.02),cloth,Vector3(0,-.13,-.125),Vector3(-4,0,0))
	# Ribcage below a half cuirass; sternum and thoracic spine.
	for i in 4:
		var h := -.06 + i * .055
		var w := .13 + i * .022
		var rib := _loft("Chest","Rib%d" % i,bone,[Vector4(h,w,w * .72,0),
				Vector4(h + .022,w - .004,w * .72 - .004,0)],10,Vector3.ZERO,Vector3.ZERO,null,false)
		rib.material_override = _double_sided(bone)
	_box("Chest","Sternum",Vector3(.04,.2,.03),bone,Vector3(0,.04,-.115))
	for i in 5:
		_box("Chest","Thoracic%d" % i,Vector3(.05,.04,.05),bone,Vector3(0,-.07 + i * .065,.1))
	_loft("Chest","HalfCuirass",iron,[Vector4(.11,.19,.14,-.01),Vector4(.19,.215,.15,-.012),
			Vector4(.26,.16,.12,0)],8)
	_loft("Chest","Gorget",rusted,[Vector4(.26,.15,.12,0),Vector4(.32,.11,.1,0)],8)
	_box("Chest","Strap",Vector3(.05,.4,.025),leather,Vector3(.02,.1,-.13),Vector3(0,0,-38))
	# Torn mantle in uneven strips.
	var lengths := [.62, .48, .7, .55, .44]
	for i in lengths.size():
		var x := -.2 + i * .1
		_box("Cape","MantleStrip%d" % i,Vector3(.11,lengths[i],.018),cloth,
				Vector3(x,-lengths[i] * .5 + .04,.16 + absf(x) * .1),Vector3(4,0,x * 12))
	_loft("Cape","MantleCollar",cloth,[Vector4(-.02,.2,.07,.07),Vector4(.04,.15,.06,.05)],8)
	for side in [-1, 1]:
		var s := "L" if side < 0 else "R"
		# Femur with hip ball and knee knob, kneecap, shin bones behind a front greave.
		_loft("Thigh"+s,"Femur",bone,[Vector4(-.37,.05,.048,0),Vector4(-.33,.03,.03,0),
				Vector4(-.06,.027,.027,0),Vector4(.0,.048,.048,0)],6)
		_box("Shin"+s,"Kneecap",Vector3(.06,.06,.035),bone,Vector3(0,-.005,-.045))
		_loft("Shin"+s,"Tibia",bone,[Vector4(-.33,.03,.03,0),Vector4(-.04,.026,.026,0),
				Vector4(.0,.042,.04,0)],6)
		_loft("Shin"+s,"FrontGreave",iron,[Vector4(-.31,.06,.035,-.03),
				Vector4(-.16,.075,.05,-.035),Vector4(-.05,.07,.045,-.03)],6)
		_loft("Foot"+s,"Sabaton",iron,[Vector4(-.076,.085,.16,-.046),
				Vector4(-.03,.083,.155,-.044),Vector4(.06,.06,.07,.01)],6)
		# Humerus, paired forearm bones, bony hand.
		_loft("Arm"+s,"Humerus",bone,[Vector4(-.25,.042,.04,0),Vector4(-.22,.024,.024,0),
				Vector4(-.04,.026,.026,0),Vector4(.03,.05,.05,0)],6)
		for k in [-1.0, 1.0]:
			_loft("Elbow"+s,"Forearm",bone,[Vector4(-.2,.017,.017,0),Vector4(-.02,.02,.02,0)],
					5,Vector3(k * .02,0,0))
		_box("Hand"+s,"Palm",Vector3(.07,.06,.035),bone,Vector3(0,-.04,0))
		for f in 3:
			_box("Hand"+s,"Finger%d" % f,Vector3(.017,.05,.017),bone,
					Vector3(-.022 + f * .022,-.085,-.012),Vector3(-35,0,0))
	# Asymmetric armour: heavy left pauldron, right vambrace on the sword arm.
	_loft("ArmL","Pauldron",iron,[Vector4(-.12,.15,.13,0),Vector4(-.04,.16,.15,0),
			Vector4(.06,.125,.12,0),Vector4(.11,.06,.06,0)],7)
	_loft("ArmL","PauldronLame",rusted,[Vector4(-.17,.13,.12,0),Vector4(-.11,.14,.135,0)],7)
	_loft("ArmR","ShoulderCap",rusted,[Vector4(-.06,.08,.075,0),Vector4(.06,.075,.07,0),
			Vector4(.09,.04,.04,0)],6)
	_loft("ElbowR","Vambrace",iron,[Vector4(-.19,.045,.045,0),Vector4(-.06,.058,.056,0),
			Vector4(-.01,.05,.05,0)],6)
	# Skull: cranium, cheekbones, sockets with pale embers, a loose jaw; open kettle helm.
	for i in 2:
		_box("Head","Neck%d" % i,Vector3(.045,.035,.045),bone,Vector3(0,-.07 + i * .045,.02))
	_loft("Head","Cranium",bone,[Vector4(.0,.085,.1,-.005),Vector4(.07,.118,.13,0),
			Vector4(.16,.115,.128,.008),Vector4(.235,.06,.075,.015)],8)
	_box("Head","Maxilla",Vector3(.13,.06,.08),bone,Vector3(0,.035,-.07))
	for side in [-1.0, 1.0]:
		_box("Head","Socket",Vector3(.05,.042,.03),void_black,Vector3(side * .045,.098,-.112))
		_box("Head","Ember",Vector3(.014,.014,.01),glow,Vector3(side * .045,.096,-.13))
		_box("Head","Cheekbone",Vector3(.035,.025,.05),bone,Vector3(side * .07,.06,-.08))
	_box("Head","NasalCavity",Vector3(.022,.03,.02),void_black,Vector3(0,.058,-.118))
	_jaw = Node3D.new()
	_jaw.name = "JawPivot"
	skeleton.get_node("Head").add_child(_jaw)
	_jaw.position = Vector3(0,.03,-.01)
	_box("Head","Jaw",Vector3(.11,.035,.1),bone,Vector3(0,-.03,-.065),Vector3.ZERO,_jaw)
	_box("Head","Teeth",Vector3(.09,.014,.012),bone,Vector3(0,-.01,-.11),Vector3.ZERO,_jaw)
	_loft("Head","KettleHelm",iron,[Vector4(.13,.128,.138,.005),Vector4(.2,.125,.135,.008),
			Vector4(.275,.07,.08,.012),Vector4(.3,.02,.02,.012)],8)
	_loft("Head","HelmBrim",rusted,[Vector4(.125,.2,.21,.01),Vector4(.145,.19,.2,.01)],8)

func _double_sided(source: StandardMaterial3D) -> StandardMaterial3D:
	var mat := source.duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

## Rebuilds the held weapon. Grip along hand local -Z; the right hand closes below the guard.
func set_weapon(next: SoulsWeapon) -> void:
	weapon = next
	if _weapon_root != null:
		_weapon_root.queue_free()
	_weapon_root = Node3D.new()
	_weapon_root.name = "Weapon"
	skeleton.get_node("HandR").add_child(_weapon_root)
	_weapon_root.position = Vector3(0, -.035, 0)
	var length := weapon.blade_length
	var guard := 0.0
	match weapon.form:
		SoulsWeapon.Form.SPEAR, SoulsWeapon.Form.JAVELIN:
			var shaft := length - .29
			_loft("","AshShaft",leather,[Vector4(-weapon.grip_length,.024,.024,0),
					Vector4(shaft,.022,.022,0)],8,Vector3.ZERO,Vector3(-90,0,0),_weapon_root)
			_loft("","Socket",trim,[Vector4(shaft-.12,.035,.035,0),
					Vector4(shaft+.02,.031,.031,0)],8,Vector3.ZERO,Vector3(-90,0,0),_weapon_root)
			_loft("","LeafPoint",blade,[Vector4(shaft,.032,.018,0),
					Vector4(shaft+.055,.07,.022,0), Vector4(length,.001,.001,0)],4,
					Vector3.ZERO,Vector3(-90,0,0),_weapon_root)
		_:
			var heavy := weapon.form == SoulsWeapon.Form.GREATSWORD
			var w := weapon.blade_half_width
			guard = .15 if heavy else .133
			var grip_center := -.11 + weapon.grip_length * .5
			_box("","Grip",Vector3(.036,.042,weapon.grip_length),leather,
					Vector3(0,0,grip_center),Vector3.ZERO,_weapon_root)
			_box("","Pommel",Vector3(.062,.064,.063) * (1.25 if heavy else 1.0),trim,
					Vector3(0,0,grip_center + weapon.grip_length * .5 + .02),Vector3(0,0,45),_weapon_root)
			_box("","Crossguard",Vector3(.42 if heavy else .267,.05 if heavy else .043,.051),trim,
					Vector3(0,0,-guard + .016),Vector3.ZERO,_weapon_root)
			var sections := [Vector4(0,w * 1.8,w * .62,0),Vector4(.1,w * 1.5,w * .47,0),
					Vector4(length * .83,w,w * .32,0),Vector4(length,.001,.001,0)]
			if heavy:
				# Ricasso, then a broad blade with a chipped shoulder near the point.
				sections = [Vector4(0,w * .8,w * .4,0),Vector4(.12,w * .8,w * .4,0),
						Vector4(.15,w * 1.1,w * .36,0),Vector4(length * .62,w,w * .3,0),
						Vector4(length * .7,w * .82,w * .28,0),Vector4(length * .86,w * .9,w * .26,0),
						Vector4(length,.001,.001,0)]
			_loft("","Blade",blade,sections,4,Vector3(0,0,-guard),Vector3(-90,0,0),_weapon_root)
	_blade_base = Marker3D.new()
	_blade_base.name = "BladeBase"
	_blade_tip = Marker3D.new()
	_blade_tip.name = "BladeTip"
	_weapon_root.add_child(_blade_base)
	_weapon_root.add_child(_blade_tip)
	_blade_base.position = Vector3(0, 0, -guard - length * weapon.dead_length)
	_blade_tip.position = Vector3(0, 0, -guard - length)
	_trail.color = weapon.trail_color
	_trail.clear()

## Sword arm follows the clip's blade path; a two-handed weapon also pulls the off hand onto
## the grip. Weight ramps at both ends of the clip so the IK pose blends with the authored body.
func _drive_arms(clip: StringName, phase: float) -> void:
	if weapon == null or weapon.form == SoulsWeapon.Form.JAVELIN:
		return
	var path: Array = SWINGS.get(&"light" if clip == &"enemy_slash" else clip, [])
	var key: Array = []
	var weight := 0.0
	if not path.is_empty():
		key = _sample_swing(path, phase)
		weight = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.9, 1.0, phase))
		if weapon.two_handed:
			weight = 1.0
	elif weapon.two_handed and clip in [&"locomotion", &"jump"]:
		key = TWO_HAND_STANCE
		weight = 1.0
	if key.is_empty():
		return
	if weapon.two_handed and not path.is_empty():
		# The stance is the start and end of each two-handed swing.
		var settle := 1.0 - smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.9, 1.0, phase))
		key = [key[0].lerp(TWO_HAND_STANCE[0], settle), key[1].slerp(TWO_HAND_STANCE[1].normalized(), settle), key[2]]
	var hand: Vector3 = key[0]
	var direction: Vector3 = (key[1] as Vector3).normalized()
	_solve_arm("R", hand, key[2], direction, weight)
	if weapon.two_handed:
		var hand_global := skeleton.get_bone_global_pose(skeleton.find_bone("HandR"))
		var grip_offset := Vector3(0, -.035, -.11 + weapon.grip_length * .78)
		var grip: Vector3 = hand_global * grip_offset
		_solve_arm("L", grip, Vector3(-0.8, -0.6, 0.2), direction, 1.0)

func _sample_swing(path: Array, phase: float) -> Array:
	var i := 0
	while i < path.size() - 2 and phase > path[i + 1][0]:
		i += 1
	var a: Array = path[i]
	var b: Array = path[i + 1]
	var t := smoothstep(0.0, 1.0, clampf(inverse_lerp(a[0], b[0], phase), 0.0, 1.0))
	var before: Vector3 = path[maxi(i - 1, 0)][1]
	var after: Vector3 = path[mini(i + 2, path.size() - 1)][1]
	var hand := (a[1] as Vector3).cubic_interpolate(b[1], before, after, t)
	var direction := (a[2] as Vector3).normalized().slerp((b[2] as Vector3).normalized(), t)
	return [hand, direction, (a[3] as Vector3).lerp(b[3], t)]

## Analytic two-bone IK in skeleton space. Limb bones point along local -Y; the weapon's blade
## lies along the hand's local -Z, so the hand basis is built from the wanted blade direction.
func _solve_arm(side: String, target: Vector3, pole: Vector3, blade_direction: Vector3, weight: float) -> void:
	if weight <= 0.0:
		return
	var upper := skeleton.find_bone("Arm" + side)
	var lower := skeleton.find_bone("Elbow" + side)
	var end := skeleton.find_bone("Hand" + side)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper))
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var a := skeleton.get_bone_rest(lower).origin.length()
	var b := skeleton.get_bone_rest(end).origin.length()
	var reach := target - shoulder
	var distance := clampf(reach.length(), absf(a - b) + 0.01, a + b - 0.002)
	var along := reach.normalized()
	var bend := (pole - along * pole.dot(along))
	if bend.length_squared() < 0.0001:
		bend = Vector3.DOWN - along * Vector3.DOWN.dot(along)
	bend = bend.normalized()
	var cos_shoulder := clampf((a * a + distance * distance - b * b) / (2.0 * a * distance), -1.0, 1.0)
	var elbow := shoulder + along * a * cos_shoulder + bend * a * sqrt(1.0 - cos_shoulder * cos_shoulder)
	var wrist := shoulder + along * distance
	var upper_basis := _bone_basis(elbow - shoulder, wrist - elbow)
	var lower_basis := _bone_basis(wrist - elbow, blade_direction)
	var upper_local := (parent.basis.inverse() * upper_basis).get_rotation_quaternion()
	var lower_local := (upper_basis.inverse() * lower_basis).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(upper, skeleton.get_bone_pose_rotation(upper).slerp(upper_local, weight))
	skeleton.set_bone_pose_rotation(lower, skeleton.get_bone_pose_rotation(lower).slerp(lower_local, weight))
	if side == "R":
		var z := -blade_direction
		var y := -(wrist - elbow).normalized()
		y = (y - z * y.dot(z))
		if y.length_squared() < 0.0001:
			y = Vector3.UP - z * z.y
		y = y.normalized()
		var hand_basis := Basis(y.cross(z), y, z)
		var hand_local := (lower_basis.inverse() * hand_basis).get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(end, skeleton.get_bone_pose_rotation(end).slerp(hand_local, weight))

## Basis whose -Y follows the bone and whose -Z faces where the next segment bends.
func _bone_basis(bone_vector: Vector3, toward: Vector3) -> Basis:
	var y := -bone_vector.normalized()
	var z := -(toward - y * toward.dot(y))
	if z.length_squared() < 0.0001:
		z = Vector3.BACK - y * y.z
	z = z.normalized()
	return Basis(y.cross(z), y, z).orthonormalized()

## The fallen let go: the weapon comes to rest flat on the ground beside the hand.
func _drop_weapon() -> void:
	_weapon_dropped = true
	var hand := _weapon_root.global_position
	var heading := -_weapon_root.global_basis.z
	heading.y = 0.0
	var yaw := atan2(-heading.x, -heading.z) if heading.length_squared() > 0.001 else 0.0
	_weapon_root.top_level = true
	_weapon_root.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(_weapon_root.global_basis.get_scale()),
			Vector3(hand.x, 0.06, hand.z))
	_trail.clear()

## World-space striking segment of the held weapon: [edge start, point].
func blade_segment() -> PackedVector3Array:
	if _blade_tip == null or not _blade_tip.is_inside_tree():
		return PackedVector3Array()
	return PackedVector3Array([_blade_base.global_position, _blade_tip.global_position])

## Leans the upper body into acceleration. x = sideways, y = forward (m/s², smoothed by caller).
func set_lean(value: Vector2) -> void:
	lean = value

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
	if clip == &"dead" and phase > 0.7 and not _weapon_dropped:
		_drop_weapon()
	elif clip != &"dead" and _weapon_dropped:
		_weapon_dropped = false
		set_weapon(weapon)
	if weapon != null and weapon.form == SoulsWeapon.Form.JAVELIN:
		_weapon_root.visible = clip != &"enemy_throw" or phase < 0.44 or phase > 0.94
	if blend_remaining > 0.0:
		blend_remaining = maxf(0.0, blend_remaining - delta)
		var weight := smoothstep(0,1,1.0 - blend_remaining / blend_duration)
		skeleton.set_bone_pose_position(0,blend_pelvis.lerp(skeleton.get_bone_pose_position(0),weight))
		for i in skeleton.get_bone_count():
			skeleton.set_bone_pose_rotation(i,blend_start[i].slerp(skeleton.get_bone_pose_rotation(i),weight))
	_drive_arms(clip, phase)
	if lean != Vector2.ZERO and clip != &"roll" and clip != &"dead":
		# Upper body tips into acceleration and away from hard stops; capped near 9 degrees.
		var chest := skeleton.find_bone("Chest")
		var tilt := Basis.from_euler(Vector3(-lean.y, 0.0, lean.x).limit_length(0.16))
		skeleton.set_bone_pose_rotation(chest, (tilt * Basis(skeleton.get_bone_pose_rotation(chest))).get_rotation_quaternion())
	if _jaw != null:
		var open := 0.08 + 0.05 * sin(breath_clock * TAU * 2.0)
		if clip in STRIKE_CLIPS and phase > 0.4 and phase < 0.75:
			open = 0.42
		elif clip == &"stagger" or clip == &"dead":
			open = 0.55
		_jaw.rotation.x = lerpf(_jaw.rotation.x, open, 1.0 - exp(-18.0 * delta))
	var segment := blade_segment()
	if segment.size() == 2:
		var cutting := clip in STRIKE_CLIPS and phase > 0.38 and phase < 0.76
		_trail.sample(segment[0], segment[1], cutting, delta)

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
	var previous_clock := gait_clock
	gait_clock = fposmod(gait_clock + backward * delta * (0.46 + speed * 1.48) * smoothstep(0,.12,speed),1.0)
	var walk := MOTION.get_animation(&"walk")
	var run := MOTION.get_animation(&"run")
	var idle := MOTION.get_animation(&"idle")
	var run_weight := smoothstep(.40,.91,speed)
	var moving := smoothstep(.01,.34,speed)
	if speed > 0.18 and _steps != null:
		# Heel strikes measured on the source clips: walk 0.20 / 0.60, run 0.03 / 0.55.
		for contact in [lerpf(.20, .025, run_weight), lerpf(.60, .55, run_weight)]:
			if _crossed(previous_clock, gait_clock, contact, backward < 0.0):
				_steps.volume_db = -11.0 + speed * 4.0
				_steps.play()
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

func _crossed(previous: float, current: float, mark: float, reverse: bool) -> bool:
	if reverse:
		var swap := previous
		previous = current
		current = swap
	if previous <= current:
		return previous < mark and mark <= current
	return mark > previous or mark <= current

func _set_cape(pitch: float, bank: float) -> void:
	skeleton.set_bone_pose_rotation(skeleton.find_bone("Cape"),
			Basis.from_euler(Vector3(pitch,0,bank) * (PI/180)).get_rotation_quaternion())
