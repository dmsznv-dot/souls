extends RefCounted
## Authored angular poses, in degrees, baked into native skeletal animation tracks.
## Every pose inherits the low guard stance. The gameplay controller supplies phase.

const STANCE := {
	"Chest": Vector3(-5,-9,0), "Head": Vector3(5,6,0), "Cape": Vector3(-7,0,0),
	"ArmR": Vector3(8,0,11), "ArmL": Vector3(8,0,-11),
	"ElbowR": Vector3(28,0,0), "ElbowL": Vector3(19,0,0),
	"ThighR": Vector3(7,0,4), "ThighL": Vector3(7,0,-4),
	"ShinR": Vector3(-12,0,0), "ShinL": Vector3(-12,0,0),
	"FootR": Vector3(5,0,0), "FootL": Vector3(5,0,0)
}
const WIND_SLASH := {
	"Chest": Vector3(-5,-40,-8), "ArmR": Vector3(54,-68,58), "ElbowR": Vector3(42,-15,0),
	"ArmL": Vector3(17,22,-26), "ThighL": Vector3(20,0,-7), "ShinL": Vector3(-29,0,0)
}
const CUT_ACROSS := {
	"Chest": Vector3(-15,39,12), "ArmR": Vector3(75,38,-29), "ElbowR": Vector3(8,0,0),
	"ArmL": Vector3(-18,-28,-22), "Cape": Vector3(-25,-8,-18)
}
const WIND_HIGH := {
	"Chest": Vector3(8,-21,-7), "ArmR": Vector3(142,-24,32), "ElbowR": Vector3(50,0,-8),
	"ArmL": Vector3(111,-14,-2), "ElbowL": Vector3(56,0,13), "Head": Vector3(-9,9,0),
	"ThighR": Vector3(30,0,8), "ShinR": Vector3(-41,0,0)
}
const CUT_DOWN := {
	"Chest": Vector3(-29,17,6), "ArmR": Vector3(56,9,-8), "ElbowR": Vector3(7,0,0),
	"HandR": Vector3(-51,0,0), "ArmL": Vector3(47,-10,3), "ElbowL": Vector3(16,0,0),
	"ThighL": Vector3(32,0,-4), "ShinL": Vector3(-42,0,0), "Cape": Vector3(-36,0,0)
}
## Backhand return cut: the blade crosses from the left shoulder out past the right hip.
const BACKHAND_OUT := {
	"Chest": Vector3(-14,-42,-9), "ArmR": Vector3(68,-74,46), "ElbowR": Vector3(9,-10,0),
	"HandR": Vector3(-24,-26,0), "ArmL": Vector3(22,18,-28), "ElbowL": Vector3(30,0,0),
	"ThighR": Vector3(24,0,6), "ShinR": Vector3(-34,0,0), "Cape": Vector3(-24,8,16)
}
## Hard reversal at a run: lead heel planted ahead, rear knee folded, chest thrown back.
const SKID := {
	"Pelvis": Vector3(6,0,0), "Chest": Vector3(16,0,0), "Head": Vector3(-10,0,0),
	"ThighL": Vector3(40,0,-8), "ShinL": Vector3(-10,0,0), "FootL": Vector3(-18,0,0),
	"ThighR": Vector3(-6,0,8), "ShinR": Vector3(-62,0,0), "FootR": Vector3(24,0,0),
	"ArmL": Vector3(35,0,-42), "ElbowL": Vector3(32,0,0), "ArmR": Vector3(20,0,30)
}
const DRAW_BACK := {
	"Chest": Vector3(1,-44,-6), "ArmR": Vector3(-32,-14,23), "ElbowR": Vector3(73,0,0),
	"HandR": Vector3(-39,41,0), "ArmL": Vector3(48,10,-16), "ElbowL": Vector3(22,0,0)
}
const LUNGE := {
	"Chest": Vector3(-21,27,5), "ArmR": Vector3(102,-29,9), "ElbowR": Vector3(5,0,0),
	"HandR": Vector3(-83,0,0), "ArmL": Vector3(-32,20,-30),
	"ThighL": Vector3(37,0,-5), "ShinL": Vector3(-47,0,0), "ThighR": Vector3(-13,0,6),
	"Cape": Vector3(-30,0,0)
}
const DEFEND := {
	"Chest": Vector3(-9,-20,-3), "ArmR": Vector3(45,14,7), "ElbowR": Vector3(53,-14,-32),
	"HandR": Vector3(-47,27,-21), "ArmL": Vector3(36,-7,-16), "ElbowL": Vector3(83,0,17),
	"Head": Vector3(3,17,0), "ThighL": Vector3(24,0,-5), "ShinL": Vector3(-30,0,0)
}
const PARRY_OUT := {
	"Chest": Vector3(1,28,7), "ArmR": Vector3(70,-59,37), "ElbowR": Vector3(13,-26,7),
	"HandR": Vector3(-16,0,0), "ArmL": Vector3(-7,5,-38), "Cape": Vector3(-12,-10,-9)
}
const TUCK := {
	"Chest": Vector3(-38,6,0), "Head": Vector3(-35,0,0),
	"ThighR": Vector3(95,0,11), "ThighL": Vector3(105,0,-12),
	"ShinL": Vector3(-126,0,0), "ShinR": Vector3(-112,0,0),
	"ArmR": Vector3(69,0,18), "ElbowR": Vector3(98,0,-15), "HandR": Vector3(-76,-65,0),
	"ArmL": Vector3(76,0,-12), "ElbowL": Vector3(109,0,5), "Cape": Vector3(-10,0,0)
}
const RECOIL := {
	"Chest": Vector3(25,-16,-10), "Head": Vector3(23,-3,4),
	"ArmR": Vector3(-12,-14,39), "ArmL": Vector3(-19,11,-35),
	"ThighR": Vector3(22,0,7), "ShinR": Vector3(-33,0,0)
}
const FALLEN := {
	"Pelvis": Vector3(83,0,-9), "Chest": Vector3(-4,9,0), "Head": Vector3(-9,-24,0),
	"ArmR": Vector3(10,9,62), "ArmL": Vector3(-2,0,-40), "ElbowR": Vector3(10,0,0),
	"ThighR": Vector3(12,0,8), "ThighL": Vector3(-5,0,-11), "ShinL": Vector3(-8,0,0)
}

const THROW_AIM := {
	"Pelvis":Vector3(0,-17,0), "Chest":Vector3(3,-28,-12), "Head":Vector3(-2,37,4),
	"ArmR":Vector3(110,-59,68), "ElbowR":Vector3(96,-7,-12), "HandR":Vector3(-118,45,5),
	"ArmL":Vector3(72,-9,-12),"ElbowL":Vector3(9,0,0), "ThighR":Vector3(23,0,8),
	"ShinR":Vector3(-45,0,0), "FootR":Vector3(22,0,0)
}
const THROW_RELEASE := {
	"Pelvis":Vector3(-4,16,3), "Chest":Vector3(-21,27,5), "ArmR":Vector3(115,-9,-15),
	"ElbowR":Vector3(3,0,0), "HandR":Vector3(-91,-12,0), "ArmL":Vector3(-28,28,-35),
	"ThighL":Vector3(32,0,-6), "ShinL":Vector3(-48,0,0),"Cape":Vector3(-35,0,-12)
}
const OATH := {
	"Pelvis":Vector3(0,-12,0), "Chest":Vector3(-8,-15,4), "Head":Vector3(-26,8,0),
	"ArmR":Vector3(36,4,1), "ElbowR":Vector3(83,3,-28), "HandR":Vector3(-29,-12,0),
	"ArmL":Vector3(22,4,-16), "ElbowL":Vector3(57,0,21),
	"ThighL":Vector3(29,0,-6), "ShinL":Vector3(-46,0,0)
}
const CHALLENGE := {
	"Chest":Vector3(9,13,-4), "Head":Vector3(8,-9,0),
	"ArmR":Vector3(139,-17,47), "ElbowR":Vector3(20,0,-16),"HandR":Vector3(-63,7,0),
	"ArmL":Vector3(-6,-4,-42), "ElbowL":Vector3(19,0,0), "Cape":Vector3(-17,0,8)
}

static func create(skeleton: Skeleton3D) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	# The weight settles onto the back leg before each active interval, then passes
	# to the lead foot while the weapon follows through.
	var load_slash := WIND_SLASH.merged({"Pelvis":Vector3(0,-19,-3),"Head":Vector3(2,28,2)},true)
	var follow_slash := CUT_ACROSS.merged({"Pelvis":Vector3(-5,20,5),
			"Chest":Vector3(-17,51,10),"HandR":Vector3(-14,12,6)},true)
	var load_high := WIND_HIGH.merged({"Pelvis":Vector3(4,-7,-5),"Cape":Vector3(-10,0,8)},true)
	var follow_down := CUT_DOWN.merged({"Pelvis":Vector3(-9,8,3),"HandR":Vector3(-71,8,0)},true)
	_add(lib,skeleton,&"light",[[0,{}],[.26,WIND_SLASH,Vector3(.038,-.035,.024)],
			[.44,load_slash,Vector3(.052,-.056,.028)],[.60,CUT_ACROSS,Vector3(-.023,-.033,-.066)],
			[.72,follow_slash,Vector3(-.040,-.064,-.080)],[.88,CUT_ACROSS,-.024],[1,{}]])
	var load_back := CUT_ACROSS.merged({"Pelvis":Vector3(-4,24,4),"Chest":Vector3(-13,50,9),
			"HandR":Vector3(-10,22,4),"Head":Vector3(3,-20,0)},true)
	var follow_back := BACKHAND_OUT.merged({"Pelvis":Vector3(-6,-20,-4),"Chest":Vector3(-16,-52,-10),
			"HandR":Vector3(-30,-34,0)},true)
	_add(lib,skeleton,&"light_b",[[0,CUT_ACROSS,-.024],[.26,load_back,Vector3(.03,-.04,.02)],
			[.44,load_back,Vector3(.045,-.055,.028)],[.60,BACKHAND_OUT,Vector3(-.02,-.04,-.06)],
			[.72,follow_back,Vector3(-.035,-.06,-.075)],[.88,BACKHAND_OUT,-.024],[1,{}]])
	_add(lib,skeleton,&"enemy_slash",[[0,{}],[.29,WIND_SLASH,-.04],[.44,load_slash,Vector3(.048,-.07,.035)],
			[.59,CUT_ACROSS,Vector3(-.022,-.048,-.067)],[.74,follow_slash,Vector3(-.055,-.082,-.073)],[1,{}]])
	_add(lib,skeleton,&"heavy",[[0,{}],[.22,WIND_HIGH,Vector3(.03,-.046,.015)],
			[.44,load_high,Vector3(.055,-.015,.042)],[.61,CUT_DOWN,Vector3(-.04,-.105,-.08)],
			[.73,follow_down,Vector3(-.049,-.133,-.084)],[.86,CUT_DOWN,-.075],[1,{}]])
	_add(lib,skeleton,&"enemy_thrust",[[0,{}],[.30,DRAW_BACK,-.037],[.44,DRAW_BACK,Vector3(.043,-.075,.07)],
			[.56,LUNGE,Vector3(-.028,-.11,-.12)],[.66,LUNGE,Vector3(-.045,-.126,-.14)],
			[.78,LUNGE,-.072],[1,{}]])
	_add(lib,skeleton,&"enemy_throw",[[0,{}],[.29,THROW_AIM,-.03],
			[.44,THROW_AIM,Vector3(.046,-.052,.059)],[.53,THROW_RELEASE,Vector3(-.028,-.035,-.079)],
			[.68,follow_slash,Vector3(-.045,-.092,-.081)],[1,{}]])
	_add(lib,skeleton,&"boss_phase",[[0,{}],[.22,OATH,-.102],[.41,OATH,-.125],
			[.65,CHALLENGE,.025],[.79,CHALLENGE,.012],[.93,DEFEND,-.055],[1,{}]])
	# Body timelines shared by attacks whose blade paths are aliased in the rig.
	for alias: Array in [[&"stab", &"enemy_thrust"], [&"light_c", &"enemy_thrust"], [&"cast", &"enemy_thrust"],
			[&"dash_slash", &"light"], [&"slam", &"heavy"], [&"nova", &"heavy"], [&"spin_slash", &"light"],
			[&"leap_slam", &"heavy"]]:
		lib.add_animation(alias[0], lib.get_animation(alias[1]))
	_add(lib,skeleton,&"block",[[0,{}],[.4,DEFEND,-.035],[1,DEFEND,-.035]])
	_add(lib,skeleton,&"parry",[[0,{}],[.22,DEFEND],[.51,PARRY_OUT],[.66,PARRY_OUT],[1,{}]])
	_add(lib,skeleton,&"stagger",[[0,{}],[.20,RECOIL,-.065],[.48,RECOIL,-.065],[1,{}]])
	_add(lib,skeleton,&"dead",[[0,{}],[.24,RECOIL,-.12],[.76,FALLEN,-.635],[1,FALLEN,-.64]])
	var rolling: Array = [[0,{}]]
	for point: Vector3 in [Vector3(.16,-36,-.25),Vector3(.37,-115,-.32),
			Vector3(.59,-214,-.32),Vector3(.80,-306,-.27)]:
		var pose := TUCK.duplicate()
		pose["Pelvis"] = Vector3(point.y,0,0)
		rolling.append([point.x,pose,point.z])
	rolling.append([1,{}])
	_add(lib,skeleton,&"roll",rolling)
	return lib

static func _add(lib: AnimationLibrary, skeleton: Skeleton3D, clip: StringName, keys: Array) -> void:
	var anim := Animation.new()
	anim.resource_name = clip
	anim.length = 1.0
	var height := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(height,^"Skeleton3D:Pelvis")
	var base := skeleton.get_bone_rest(skeleton.find_bone("Pelvis")).origin
	for key: Array in keys:
		var offset := Vector3.ZERO
		if key.size() > 2:
			offset = key[2] if key[2] is Vector3 else Vector3.UP * key[2]
		anim.position_track_insert_key(height,key[0],base + offset)
	for idx in skeleton.get_bone_count():
		var joint := skeleton.get_bone_name(idx)
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track,NodePath("Skeleton3D:"+joint))
		for key: Array in keys:
			var angles: Vector3 = key[1].get(String(joint),STANCE.get(String(joint),Vector3.ZERO))
			anim.rotation_track_insert_key(track,key[0],Basis.from_euler(angles * (PI/180)).get_rotation_quaternion())
	lib.add_animation(clip,anim)
