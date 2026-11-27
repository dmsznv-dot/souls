extends SceneTree
## Poise, daze, knockdown, flank bonus, exhaustion, response windows, armour material, lock switch.

const ARENA := "res://scenes/duel/courtyard_duel.tscn"
const LIGHT := preload("res://scenes/duel/combat/light.tres")
const HEAVY := preload("res://scenes/duel/combat/heavy.tres")

var _checks := 0
var _failures := 0
var _hero: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_poise()
	await _test_knockdown()
	await _test_daze()
	await _test_flank()
	await _test_exhaustion()
	await _test_response_window()
	await _test_material()
	await _test_lock_switch()
	await _test_bars()
	print("Poise: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_poise() -> void:
	await _arena()
	var husk := _spawn("husk", Vector3(0, 0, -2.0))
	var brute := _spawn("brute", Vector3(3.0, 0, -2.0))
	await _ticks(3)
	var hero_combat := _hero.get_node("Combat")
	husk.get_node("Combat").receive_attack(hero_combat, LIGHT)
	_check(husk.get_node("Combat").action == &"flinch", "a light blow staggers a weak husk")
	brute.get_node("Combat").receive_attack(hero_combat, LIGHT)
	_check(brute.get_node("Combat").action == &"", "a brute shrugs off a single light blow")
	for i in 4:
		await _ticks(4)
		brute.get_node("Combat").receive_attack(hero_combat, LIGHT)
	_check(brute.get_node("Combat").action == &"flinch", "light blows in quick succession break a brute's poise")


func _test_knockdown() -> void:
	await _arena()
	var brute := _spawn("brute", Vector3(0, 0, -2.0))
	await _ticks(3)
	var combat := brute.get_node("Combat")
	var crush: Resource = load("res://scenes/combat/weapons/attacks/greatsword_heavy.tres")
	combat.receive_attack(_hero.get_node("Combat"), crush)
	_check(combat.action == &"", "a brute stands one greatsword blow")
	await _ticks(4)
	combat.receive_attack(_hero.get_node("Combat"), crush)
	_check(combat.action == &"knockdown", "a second heavy greatsword blow knocks the brute off its feet")
	var health: float = combat.health
	await _ticks(50)
	_check(_lowest(brute) > -0.05 and _lowest(brute) < 0.12, "the fallen brute lies on the floor (lowest %.2f m)" % _lowest(brute))
	combat.receive_attack(_hero.get_node("Combat"), LIGHT)
	_check(combat.action == &"knockdown" and combat.health < health, "a blow on a fallen foe lands but does not lift it")
	await _ticks(100)
	_check(combat.action != &"knockdown", "it gets back up")

	await _arena()
	var boss := _spawn("husk", Vector3(0, 0, -2.0))
	boss.get_node("Combat").steady = true
	await _ticks(3)
	for i in 3:
		boss.get_node("Combat").receive_attack(_hero.get_node("Combat"), HEAVY)
		await _ticks(3)
	_check(boss.get_node("Combat").action != &"knockdown", "a steady body (a boss) is never knocked down")

	var slam := HEAVY.duplicate()
	slam.impact = 1.0
	var player := _hero.get_node("Combat")
	player.receive_attack(boss.get_node("Combat"), slam)
	_check(player.action == &"knockdown", "a slam of full weight knocks the player down")
	await _ticks(roundi(player.KNOCKDOWN_DURATION * 0.45 * 60.0))
	_check(player.is_invulnerable(), "a downed player cannot be hit again while lying")


func _test_daze() -> void:
	await _arena()
	var spear := _spawn("spearman", Vector3(0, 0, -2.0))
	await _ticks(3)
	var combat := spear.get_node("Combat")
	combat.posture = 10.0
	var cues: Array[StringName] = []
	combat.feedback.connect(func(cue: StringName, _at: Vector3, _s: float) -> void: cues.append(cue))
	combat.receive_attack(_hero.get_node("Combat"), LIGHT)
	_check(combat.action == &"dazed" and &"posture_break" in cues, "a broken posture leaves the foe dazed")
	await _ticks(30)
	_check(combat.action == &"dazed", "the daze lasts long enough to close in")
	var before: float = combat.health
	combat.receive_attack(_hero.get_node("Combat"), LIGHT)
	var plain: float = LIGHT.damage * combat.RESISTANCE[&"plate"][LIGHT.damage_type]
	_check(&"critical" in cues and before - combat.health > plain * 1.5, "the next blow on a dazed foe is a critical (%.1f vs %.1f)" % [before - combat.health, plain])


func _test_flank() -> void:
	await _arena()
	var front := _spawn("husk", Vector3(-1.0, 0, -1.4), PI)
	var back := _spawn("husk", Vector3(1.0, 0, -1.4), 0.0)
	await _ticks(3)
	var hero_combat := _hero.get_node("Combat")
	_check(hero_combat._position_bonus(front) == Vector2.ONE, "a blow from the front lands at plain weight")
	var rear: Vector2 = hero_combat._position_bonus(back)
	_check(rear.x > 1.1 and rear.y > 1.3, "a blow from behind hits harder and breaks poise faster (%.2f, %.2f)" % [rear.x, rear.y])


func _test_exhaustion() -> void:
	await _arena()
	await _ticks(20)
	var combat := _hero.get_node("Combat")
	combat.stamina = 14.0
	combat.start_roll(Vector3.FORWARD)
	_check(combat.exhausted, "running stamina dry leaves the hero exhausted")
	await _ticks(60)
	var after_second: float = combat.stamina
	_check(after_second < 2.0, "an exhausted hero regains nothing for over a second (%.1f)" % after_second)
	await _ticks(150)
	_check(combat.stamina > 15.0, "then stamina returns")


func _test_response_window() -> void:
	await _arena()
	var brute := _spawn("brute", Vector3(0, 0, -2.0))
	brute.ai_enabled = true
	var winded := false
	for i in 600:
		await physics_frame
		_hero.get_node("Combat").health = 100.0
		if brute.get_node("Combat").action == &"winded":
			winded = true
			break
	_check(winded, "a brute stands winded after its blow, the player's opening")


func _test_material() -> void:
	await _arena()
	var spear := _spawn("spearman", Vector3(0, 0, -2.0))
	var husk := _spawn("husk", Vector3(2.0, 0, -2.0))
	await _ticks(3)
	var cues: Array[StringName] = []
	var collect := func(cue: StringName, _at: Vector3, _s: float) -> void: cues.append(cue)
	spear.get_node("Combat").feedback.connect(collect)
	husk.get_node("Combat").feedback.connect(collect)
	spear.get_node("Combat").receive_attack(_hero.get_node("Combat"), LIGHT)
	husk.get_node("Combat").receive_attack(_hero.get_node("Combat"), LIGHT)
	_check(&"impact_plate" in cues and &"impact_flesh" in cues, "blows ring on plate and thud on flesh (%s)" % [cues])


func _test_lock_switch() -> void:
	await _arena()
	_hero.global_position = Vector3(0, 0.02, 3.0)
	var left := _spawn("husk", Vector3(-1.6, 0, -4.0))
	var right := _spawn("husk", Vector3(1.6, 0, -4.0))
	left.ai_enabled = false
	right.ai_enabled = false
	await _ticks(5)
	var camera := _hero.get_node("CameraRig")
	camera.rotation.y = 0.0
	camera.lock_target = left.get_node("LockPoint")
	await _ticks(2)
	_check(camera.switch_target(1.0) and camera.lock_target == right.get_node("LockPoint"), "a flick to the right moves the lock to the foe on the right")
	camera._switch_cooldown = 0.0
	left.get_node("LockPoint").hide()
	camera.lock_target = left.get_node("LockPoint")
	await _ticks(2)
	_check(camera.lock_target == right.get_node("LockPoint"), "when the locked foe falls the lock moves to the next one")


func _test_bars() -> void:
	await _arena()
	var guard := current_scene.get_node("Guard")
	guard.global_position = Vector3(2.0, 0.02, -3.0)
	guard.get_node("Combat").receive_attack(_hero.get_node("Combat"), LIGHT)
	var husk := _spawn("husk", Vector3(-1.0, 0, -4.0))
	await _ticks(3)
	husk.get_node("Combat").receive_attack(_hero.get_node("Combat"), LIGHT)
	await process_frame
	await process_frame
	var bars: Array = current_scene.get_node("Interface/FoeBars")._bars
	_check(bars.size() == 1, "a hurt foe shows a thin bar overhead; the duel opponent keeps the top bar (%d bars)" % bars.size())
	_check(bars.size() == 1 and bars[0][3] > bars[0][2], "the bar trails a chip of the damage just taken")


func _lowest(foe: Node3D) -> float:
	var low := INF
	for part in foe.get_node("Heading/Rig").find_children("*", "MeshInstance3D", true, false):
		if part.name == &"BladeTrail" or not part.is_visible_in_tree() or part.mesh == null:
			continue
		for v in part.mesh.get_faces():
			low = minf(low, (part.global_transform * v).y)
	return low


func _arena() -> void:
	change_scene_to_file(ARENA)
	await scene_changed
	var watcher := current_scene.get_node("Guard") as CharacterBody3D
	watcher.ai_enabled = false
	watcher.global_position = Vector3(8.0, 0.02, 7.0)
	watcher.remove_from_group(&"foes")
	watcher.get_node("LockPoint").hide()
	_hero = current_scene.get_node("Player")
	_hero.global_position = Vector3(0, 0.02, 1.0)
	root.get_node("Director").reset()
	await _ticks(2)


func _spawn(kind: String, offset: Vector3, yaw: float = PI) -> CharacterBody3D:
	var foe: CharacterBody3D = load("res://scenes/expedition/enemies/%s.tscn" % kind).instantiate()
	foe.player = _hero
	foe.ai_enabled = false
	current_scene.add_child(foe)
	foe.global_position = _hero.global_position + offset
	foe.get_node("Heading").rotation.y = yaw
	return foe


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _check(passed: bool, description: String) -> bool:
	_checks += 1
	if passed:
		print("PASS: ", description)
	else:
		_failures += 1
		printerr("FAIL: ", description)
	return passed
