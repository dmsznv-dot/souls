extends SceneTree
## Enemy kinds and the Gatekeeper's move set.

const BOSS_SCENE := "res://scenes/expedition/boss_court.tscn"
const ARENA := "res://scenes/duel/courtyard_duel.tscn"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_kinds()
	await _test_boss()
	print("Foes: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_kinds() -> void:
	var husk := await _spawn("husk", 6.0)
	var husk_start := husk.global_position
	await _ticks(60)
	var husk_travel := husk.global_position.distance_to(husk_start)
	var ghoul := await _spawn("ghoul", 6.0)
	var ghoul_start := ghoul.global_position
	await _ticks(60)
	var ghoul_travel := ghoul.global_position.distance_to(ghoul_start)
	_check(ghoul_travel > husk_travel * 2.5, "a crawler closes ground far faster than a husk (%.1f vs %.1f m)" % [ghoul_travel, husk_travel])

	ghoul = await _spawn("ghoul", 1.4)
	var hero := current_scene.get_node("Player") as CharacterBody3D
	var before := ghoul.global_position.distance_to(hero.global_position)
	for i in 160:
		await physics_frame
		if ghoul.get_node("Combat").action != &"":
			continue
		if ghoul.global_position.distance_to(hero.global_position) > before + 0.4:
			break
	_check(ghoul.global_position.distance_to(hero.global_position) > before + 0.4,
		"a crawler backs off after it strikes")

	var brute := await _spawn("brute", 3.0, false)
	var brute_combat := brute.get_node("Combat")
	brute_combat.receive_attack(brute_combat, load("res://scenes/duel/combat/light.tres"))
	await _ticks(2)
	_check(brute_combat.action == &"", "a brute shrugs off a light blow")
	husk = await _spawn("husk", 3.0, false)
	var husk_combat := husk.get_node("Combat")
	husk_combat.receive_attack(husk_combat, load("res://scenes/duel/combat/light.tres"))
	await _ticks(2)
	_check(husk_combat.action == &"flinch", "a husk flinches from a light blow")
	_check(husk_combat.health < 100.0 - 18.0 or husk_combat.max_health == 55.0, "husk health matches its kind")

	brute = await _spawn("brute", 2.6, false)
	brute_combat = brute.get_node("Combat")
	brute_combat.start_attack(brute_combat.heavy_attack)
	await _ticks(150)
	_check(current_scene.get_node("Player/Combat").health < 100.0, "the brute's slam shockwave reaches the player")


func _test_boss() -> void:
	change_scene_to_file(BOSS_SCENE)
	await scene_changed
	await _ticks(4)
	var boss := current_scene.get_node("Guard")
	var hero := current_scene.get_node("Player") as CharacterBody3D
	boss.ai_enabled = false
	var moves: Array[StringName] = []
	for i in 40:
		boss._plan.clear()
		boss._boss_plan([1.5, 4.0, 8.0][i % 3])
		moves.append(boss.boss_move)
	var repeats := 0
	for i in range(1, moves.size()):
		if moves[i] == moves[i - 1]:
			repeats += 1
	_check(repeats == 0, "the Gatekeeper never repeats a move back to back")
	var kinds := {}
	for move in moves:
		kinds[move] = true
	_check(kinds.size() >= 6, "phase one draws on at least six moves (%d)" % kinds.size())

	boss.global_position = Vector3(0, 0.02, -6.0)
	hero.global_position = Vector3(0, 0.02, 2.0)
	boss.get_node("Heading").rotation.y = PI
	await _ticks(3)
	boss._leap_target = hero.global_position
	boss.get_node("Combat").start_attack(boss._boss_moves[&"leap"])
	await _ticks(100)
	_check(boss.global_position.distance_to(hero.global_position) < 3.0, "the leaping slam closes an 8 m gap")
	_check(hero.get_node("Combat").health < 100.0, "the landing shockwave strikes the player")

	hero.get_node("Combat").revive()
	boss.global_position = Vector3(0, 0.02, -4.0)
	await _ticks(60)
	var heading := boss.get_node("Heading") as Node3D
	var turned := 0.0
	var last := heading.rotation.y
	boss.get_node("Combat").start_attack(boss._boss_moves[&"spin"])
	for i in 80:
		await physics_frame
		turned += absf(angle_difference(last, heading.rotation.y))
		last = heading.rotation.y
	_check(turned > deg_to_rad(300.0), "the spin sweeps a full circle (%.0f°)" % rad_to_deg(turned))

	await _ticks(40)
	var bolts_before := current_scene.get_children().size()
	boss.get_node("Combat").start_attack(boss._boss_moves[&"ash_wave"])
	await _ticks(50)
	var spawned := current_scene.get_children().size() - bolts_before
	_check(spawned >= 3, "the ash wave throws a fan of three bolts")

	var delayed: DuelAttack = boss._boss_moves[&"delayed"]
	var plain: DuelAttack = boss._boss_moves[&"cleave"]
	var combat := boss.get_node("Combat")
	await _ticks(60)
	combat.start_attack(delayed)
	var ticks := 0
	while combat.action_age < delayed.windup and ticks < 200:
		await physics_frame
		ticks += 1
	_check(ticks > roundi((plain.windup + 0.45) * 60.0), "the delayed overhead hangs before it falls (%d ticks)" % ticks)


func _spawn(kind: String, distance: float, ai: bool = true) -> CharacterBody3D:
	change_scene_to_file(ARENA)
	await scene_changed
	var watcher := current_scene.get_node("Guard") as CharacterBody3D
	watcher.ai_enabled = false
	watcher.global_position = Vector3(7.5, 0.02, 6.5)
	var hero := current_scene.get_node("Player") as CharacterBody3D
	hero.global_position = Vector3(0, 0.02, 2.0)
	var foe: CharacterBody3D = load("res://scenes/expedition/enemies/%s.tscn" % kind).instantiate()
	foe.player = hero
	foe.ai_enabled = ai
	current_scene.add_child(foe)
	foe.global_position = Vector3(0, 0.02, 2.0 - distance)
	foe.get_node("Heading").rotation.y = PI
	await _ticks(3)
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
