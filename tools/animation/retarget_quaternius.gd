extends SceneTree
## Retargets Quaternius Universal Animation Library clips (CC0) onto the duelist rig.
##
##   godot --headless --path . --script res://tools/animation/retarget_quaternius.gd \
##       -- <UAL1 glb> <UAL2 glb>
##
## Writes assets/animations/quaternius_extra.res. The source faces +Z in a T-pose; it is turned
## 180 degrees around Y. Limbs keep their source rotation measured from a reference that points
## each rig bone along the source bind direction, so swing and twist both transfer while bone
## lengths may differ. Pelvis, chest, head and feet transfer their rotation relative to the bind
## pose. Horizontal pelvis travel is removed (physics moves the body); height changes are scaled
## by the leg-length ratio. Clips are sampled at 24 Hz onto a normalized one-second timeline,
## the same layout as quaternius_humanoid.res, and keep their source length as metadata.

const OUT := "res://assets/animations/quaternius_extra.res"
const RIG := "res://scenes/characters/duelist_rig.tscn"
const FPS := 24.0
## [target bone, source bone, child used for the bind direction or "" for bind-relative]
const MAP := [
	["Pelvis", "pelvis", ""], ["Chest", "spine_03", ""], ["Head", "Head", ""],
	["ThighL", "thigh_l", "calf_l"], ["ShinL", "calf_l", "foot_l"], ["FootL", "foot_l", ""],
	["ArmL", "upperarm_l", "lowerarm_l"], ["ElbowL", "lowerarm_l", "hand_l"], ["HandL", "hand_l", "@lowerarm_l"],
	["ThighR", "thigh_r", "calf_r"], ["ShinR", "calf_r", "foot_r"], ["FootR", "foot_r", ""],
	["ArmR", "upperarm_r", "lowerarm_r"], ["ElbowR", "lowerarm_r", "hand_r"], ["HandR", "hand_r", "@lowerarm_r"],
]
## [source file index, source clip, output name, loop]
const CLIPS := [
	[0, "Roll", "mocap_roll", false], [0, "Sprint_Loop", "sprint", true],
	[0, "Crouch_Fwd_Loop", "crouch_walk", true], [0, "Crouch_Idle_Loop", "crouch_idle", true],
	[0, "Hit_Chest", "hit_chest", false], [0, "Hit_Head", "hit_head", false],
	[0, "Death01", "death", false], [0, "Spell_Simple_Shoot", "spell_shoot", false],
	[0, "Punch_Cross", "punch_cross", false], [0, "Punch_Jab", "punch_jab", false],
	[1, "Zombie_Idle_Loop", "zombie_idle", true], [1, "Zombie_Walk_Fwd_Loop", "zombie_walk", true],
	[1, "Zombie_Scratch", "zombie_scratch", false], [1, "Hit_Knockback", "hit_knockback", false],
	[1, "Melee_Hook", "melee_hook", false], [1, "Slide_Start", "slide_start", false],
	[1, "Slide_Loop", "slide_loop", true], [1, "Slide_Exit", "slide_exit", false],
	[1, "Sword_Dash_RM", "sword_dash", false], [1, "Shield_Dash_RM", "shield_dash", false],
	[1, "OverhandThrow", "overhand_throw", false], [1, "NinjaJump_Land", "hard_land", false],
]
const TURN := Basis(Vector3.UP, PI)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <UAL1.glb> <UAL2.glb>")
		quit(1)
		return
	var rig: Node3D = load(RIG).instantiate()
	root.add_child(rig)
	var target: Skeleton3D = rig.get_node("Skeleton3D")
	var sources := []
	for path in args:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			printerr("cannot read ", path)
			quit(1)
			return
		var scene: Node = doc.generate_scene(state)
		root.add_child(scene)
		sources.append(scene)
	await process_frame
	var library := AnimationLibrary.new()
	for clip: Array in CLIPS:
		var scene: Node = sources[clip[0]]
		var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		if not player.has_animation(clip[1]):
			printerr("missing clip ", clip[1])
			continue
		library.add_animation(clip[2], _bake(skeleton, player, clip[1], target, clip[3]))
		print("baked ", clip[2], " from ", clip[1])
	ResourceSaver.save(library, OUT)
	print("saved ", OUT)
	quit()


func _bake(source: Skeleton3D, player: AnimationPlayer, clip: String, target: Skeleton3D, looping: bool) -> Animation:
	var source_anim := player.get_animation(clip)
	var length := source_anim.length
	var frames := maxi(2, int(round(length * FPS)) + 1)
	var leg_ratio := target.get_bone_rest(0).origin.y / _rest(source, "pelvis").origin.y
	var bind_pelvis := _rest(source, "pelvis").origin - _rest(source, "root").origin
	var reference := {}
	for entry: Array in MAP:
		reference[entry[0]] = _reference(source, entry)
	var anim := Animation.new()
	anim.length = 1.0
	anim.set_meta(&"source_length", length)
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var height := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(height, ^"Skeleton3D:Pelvis")
	var tracks := {}
	for i in target.get_bone_count():
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("Skeleton3D:" + target.get_bone_name(i)))
		tracks[target.get_bone_name(i)] = track
	var offsets: Array[Vector3] = []
	player.play(clip)
	for k in frames:
		var time := minf(k / FPS, length)
		player.seek(time, true)
		var key_time := float(k) / (frames - 1)
		var globals := {}
		for entry: Array in MAP:
			var current := _pose(source, entry[1]).basis.orthonormalized()
			var bind := _rest(source, entry[1]).basis.orthonormalized()
			globals[entry[0]] = current * bind.inverse() * reference[entry[0]]
		for entry: Array in MAP:
			var bone := target.find_bone(entry[0])
			var parent := target.get_bone_parent(bone)
			var parent_basis: Basis = globals.get(target.get_bone_name(parent), Basis.IDENTITY) if parent >= 0 else Basis.IDENTITY
			var local: Basis = parent_basis.inverse() * globals[entry[0]]
			anim.rotation_track_insert_key(tracks[entry[0]], key_time, local.get_rotation_quaternion())
		anim.rotation_track_insert_key(tracks["Cape"], key_time,
				Basis.from_euler(Vector3(deg_to_rad(-7.0), 0, 0)).get_rotation_quaternion())
		var pelvis := _pose(source, "pelvis").origin - _pose(source, "root").origin
		offsets.append((pelvis - bind_pelvis) * leg_ratio)
	# Remove horizontal travel: physics owns the body's position.
	var drift := offsets[-1] - offsets[0]
	for k in frames:
		var offset := offsets[k] - drift * (float(k) / (frames - 1))
		var mean := Vector3.ZERO
		offset.x *= 0.25
		offset.z *= 0.25
		anim.position_track_insert_key(height, float(k) / (frames - 1),
				target.get_bone_rest(0).origin + Vector3(offset.x, offset.y, offset.z) + mean)
	return anim


## Rig bone pointing along the source bind direction (limbs) or the rig rest (torso, feet).
func _reference(source: Skeleton3D, entry: Array) -> Basis:
	var child: String = entry[2]
	if child.is_empty():
		return Basis.IDENTITY
	var from := _rest(source, entry[1]).origin
	var to := _rest(source, child.trim_prefix("@")).origin
	var direction := (to - from).normalized()
	if child.begins_with("@"):
		direction = -direction
	return _arc(Vector3.DOWN, direction)


func _arc(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	if axis.length_squared() < 1e-8:
		return Basis.IDENTITY if from.dot(to) > 0.0 else Basis(Vector3.BACK, PI)
	return Basis(axis.normalized(), from.angle_to(to))


func _pose(skeleton: Skeleton3D, bone: String) -> Transform3D:
	return Transform3D(TURN) * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))


func _rest(skeleton: Skeleton3D, bone: String) -> Transform3D:
	return Transform3D(TURN) * skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(bone))
