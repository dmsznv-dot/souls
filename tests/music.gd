extends SceneTree
## Adaptive score: notice stinger and combat theme on engagement, phase layer, return after.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var music := root.get_node("Music")
	change_scene_to_file("res://scenes/expedition/boss_court.tscn")
	await scene_changed
	await _ticks(10)
	_check(music.area == &"court" and music.intensity == 1, "the court opens on its exploration score")
	var boss := current_scene.get_node("Guard")
	var hero := current_scene.get_node("Player") as CharacterBody3D
	hero.global_position = Vector3(0, 0.02, -1.0)
	await _ticks(30)
	_check(music.intensity == 2 and music._players[&"court:combat"].playing,
		"the Gatekeeper noticing the player starts the combat theme")
	_check(music._stinger.playing and String(music._stinger.stream.resource_path).ends_with("notice.ogg"),
		"a notice stinger marks the start of the fight")
	await _ticks(90)
	_check(music._players[&"court:combat"].volume_db > -6.0 and music._players[&"court:explore"].volume_db < -30.0,
		"the combat theme replaces the exploration score")
	hero.global_position = Vector3(0, 0.02, 7.5)
	boss.get_node("Combat").health = 60.0
	await _ticks(120)
	_check(music.combat_phase == 2, "the Gatekeeper's second phase adds the choir layer")
	boss.get_node("Combat").health = 1.0
	boss.get_node("Combat").receive_attack(hero.get_node("Combat"), load("res://scenes/duel/combat/light.tres"))
	await _ticks(150)
	_check(music.intensity == 1 and music._gain[&"court:explore"] > 0.9 and music._gain[&"court:combat"] < 0.1,
		"after the fight the exploration score returns")
	print("Music: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


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
