extends SceneTree
## Foe tactics: attack tokens, spacing, perception, alarms, evasion, tracking, search.

const ARENA := "res://scenes/duel/courtyard_duel.tscn"

var _checks := 0
var _failures := 0
var _hero: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_tokens_and_spacing()
	await _test_perception()
	await _test_alarm()
	await _test_evasion_and_tracking()
	await _test_search()
	await _test_leash()
	await _test_starvation()
	print("AI: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_tokens_and_spacing() -> void:
	await _arena()
	var pack: Array[CharacterBody3D] = []
	for i in 5:
		var angle := TAU * i / 5.0
		pack.append(_spawn("husk", Vector3(sin(angle), 0, cos(angle)) * 3.2, true))
	var brute := _spawn("brute", Vector3(0, 0, -5.0), true)
	await _ticks(2)
	var worst_budget := 0
	var waiting_distances: Array[float] = []
	for t in 360:
		await physics_frame
		_hero.get_node("Combat").health = 100.0
		var budget := 0
		for foe in pack:
			if foe.get_node("Combat").attack != null:
				budget += 1
			elif t > 120:
				waiting_distances.append(foe.global_position.distance_to(_hero.global_position))
		if brute.get_node("Combat").attack != null:
			budget += 2
		worst_budget = maxi(worst_budget, budget)
	_check(worst_budget <= 4, "at most the token budget (+1 for an opening) attacks at once (peak %d)" % worst_budget)
	var mean := 0.0
	for d in waiting_distances:
		mean += d
	mean /= maxf(waiting_distances.size(), 1)
	_check(mean > 2.3, "foes without a token hold a spacing ring (mean %.1f m)" % mean)


func _test_perception() -> void:
	await _arena()
	var blind := _spawn("husk", Vector3(0, 0, -4.0), true, 0.0)
	await _ticks(60)
	_check(blind.mode == blind.Mode.IDLE, "a foe facing away does not see a quiet player 4 m behind it")
	_hero.sprinting = true
	Input.action_press(&"sprint")
	Input.action_press(&"move_left")
	await _ticks(20)
	Input.action_release(&"move_left")
	Input.action_release(&"sprint")
	_check(blind.mode == blind.Mode.HUNT, "it hears a sprinting player behind it")
	await _arena()
	var watcher := _spawn("husk", Vector3(0, 0, -4.0), true)
	await _ticks(20)
	_check(watcher.mode == watcher.Mode.HUNT, "a foe facing the player notices it")


func _test_alarm() -> void:
	await _arena()
	var lookout := _spawn("husk", Vector3(0, 0, -4.0), true)
	var sleeper := _spawn("husk", Vector3(5.5, 0, -6.5), true, PI * 0.5)
	await _ticks(30)
	_check(lookout.mode == lookout.Mode.HUNT and sleeper.mode != sleeper.Mode.IDLE,
		"a foe that spots the player rouses an ally out of sight")


func _test_evasion_and_tracking() -> void:
	await _arena()
	var spear := _spawn("spearman", Vector3(0, 0, -1.9), true)
	spear.evade_chance = 1.0
	await _ticks(25)
	spear._cooldown = 10.0
	for i in 120:
		if spear.get_node("Combat").action == &"":
			break
		await physics_frame
	spear._cooldown = 10.0
	spear._evade_cooldown = 0.0
	var rolled := false
	_hero.get_node("Heading").rotation.y = 0.0
	_hero.get_node("Combat").start_light()
	for i in 20:
		await physics_frame
		if spear.get_node("Combat").action == &"roll":
			rolled = true
	_check(rolled, "a nimble foe rolls away from a swing that would reach it")

	await _arena()
	var husk := _spawn("husk", Vector3(0, 0, -1.6), false)
	await _ticks(3)
	husk.player = _hero
	husk.ai_enabled = true
	var heading := husk.get_node("Heading") as Node3D
	husk.get_node("Combat").start_attack(husk.get_node("Combat").light_attack)
	var before := heading.rotation.y
	_hero.global_position += Vector3(1.6, 0, 0)
	await _ticks(20)
	_check(absf(angle_difference(before, heading.rotation.y)) > 0.25, "a windup tracks a player who sidesteps early")


func _test_search() -> void:
	await _arena()
	_hero.global_position = Vector3(-3.0, 0.02, 1.5)
	var husk := _spawn("husk", Vector3(-0.5, 0, -3.7), true)
	husk.pursuit_speed = 0.0
	await _ticks(30)
	_check(husk.mode == husk.Mode.HUNT, "the sentry-post husk sees the player")
	# Behind the west pier, out of its line of sight.
	_hero.global_position = Vector3(-8.1, 0.02, -2.2)
	await _ticks(200)
	_check(husk.mode == husk.Mode.SEARCH, "a foe that loses the player for 2.5 s searches its last position")
	await _ticks(340)
	_check(husk.mode in [husk.Mode.RETURN, husk.Mode.IDLE], "after five fruitless seconds it heads back to its post")


func _test_leash() -> void:
	await _arena()
	_hero.global_position = Vector3(0.0, 0.02, 4.0)
	var husk := _spawn("husk", Vector3(0, 0, -4.0), true)
	husk.leash = 5.0
	husk.notice_distance = 14.0
	await _ticks(1)
	# Its post lies beyond the player: walking home leads it straight at the player in view.
	husk._post = _hero.global_position + Vector3(0, 0, 6.0)
	var start := husk.global_position
	for i in 300:
		await physics_frame
	var moved := husk.global_position.distance_to(start)
	_check(moved > 1.5, "a foe beyond its leash walks home instead of freezing in place (moved %.1f m)" % moved)


func _test_starvation() -> void:
	await _arena()
	var brute := _spawn("brute", Vector3(0, 0, -2.6), true)
	for i in 6:
		var angle := TAU * i / 6.0 + 0.4
		var quick := _spawn("ghoul", Vector3(sin(angle), 0, cos(angle)) * 2.0, true)
		quick.retreat_after_attack = 0.0
		quick.attack_rest = 0.1
	# Longest stretch without an attack from the brute over half a minute of crowding.
	var since := 0
	var longest := 0
	for i in 1800:
		await physics_frame
		_hero.get_node("Combat").health = 100.0
		if brute.get_node("Combat").attack != null:
			since = 0
		else:
			since += 1
			longest = maxi(longest, since)
	_check(longest < 600, "a heavy that needs two tokens keeps getting turns among quick foes (longest wait %.1f s)" % (longest / 60.0))


func _arena() -> void:
	change_scene_to_file(ARENA)
	await scene_changed
	var watcher := current_scene.get_node("Guard") as CharacterBody3D
	watcher.ai_enabled = false
	watcher.global_position = Vector3(8.0, 0.02, 7.0)
	watcher.remove_from_group(&"foes")
	_hero = current_scene.get_node("Player")
	_hero.global_position = Vector3(0, 0.02, 1.0)
	root.get_node("Director").reset()
	await _ticks(2)


func _spawn(kind: String, offset: Vector3, ai: bool, yaw: float = PI) -> CharacterBody3D:
	var foe: CharacterBody3D = load("res://scenes/expedition/enemies/%s.tscn" % kind).instantiate()
	foe.player = _hero
	foe.ai_enabled = ai
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
