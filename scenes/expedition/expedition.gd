extends "res://scenes/duel/courtyard_duel.gd"
## The Ash Gate expedition as one continuous place. The Outer Ruins stream in on a background
## thread during the Gatekeeper fight; after his defeat the seal burns away and the player walks
## across a short bridge into the ruins. Nothing reloads: zone changes swap distant backdrops
## inside the gate's archway, crossfade the score and switch the HUD.

const RUINS_AREA := "res://scenes/expedition/outer_ruins_area.tscn"
const FOREST_AREA := "res://scenes/forest/forest_area.tscn"
const ForestArea = preload("res://scenes/forest/forest_area.gd")
const ShaderWarmup = preload("res://scenes/fx/shader_warmup.gd")
## The Thornwood lies far from the court; only the eclipse ring leads there.
const FOREST_OFFSET := Vector3(600.0, 0.0, 0.0)
const OuterRuins = preload("res://scenes/expedition/outer_ruins.gd")
## Places the ruins' entrance arch just behind the court's seal gate.
const RUINS_OFFSET := Vector3(0.0, 0.0, -25.2)
## Court/ruins border on the bridge, with hysteresis so standing on it never flickers.
const BORDER_Z := -14.6
const BORDER_MARGIN := 0.4

var zone: StringName = &"court"
var ruins: Node3D
var forest: ForestArea
var _forest_fallen: bool
var _transitioning: bool
var ruins_outcome: StringName
var _ruins_scene: PackedScene
var _ruins_announced: bool
## Stand-ins from the shader warm-up, kept so their shaders are not freed before use.
var _warm_keep: Array[Node3D] = []

@onready var _gate: Node3D = $AshGate
@onready var _court_hills: Node3D = $Environment/Court/AshHills
@onready var _guard_caption: Label = $Interface/GuardMeters/Caption
@onready var _hero_caption: Label = $Interface/HeroMeters/Caption


func _ready() -> void:
	super()
	ResourceLoader.load_threaded_request(RUINS_AREA, "PackedScene")
	_warm_ruins.call_deferred()


## Part of the level's load: the ruins are read now and their shaders compiled out of sight, so
## the gate opening onto them does not stall on a first run (a new machine, driver or build).
func _warm_ruins() -> void:
	if OS.get_cmdline_user_args().has("--no-warmup"):
		return
	if _ruins_scene == null:
		_ruins_scene = ResourceLoader.load_threaded_get(RUINS_AREA) as PackedScene
	if _ruins_scene == null:
		return
	var sample := _ruins_scene.instantiate()
	var items := ShaderWarmup.gather(sample)
	var foes := {}
	for foe in sample.get_node("Enemies").get_children():
		if not foe.scene_file_path.is_empty():
			foes[foe.scene_file_path] = true
	var stand_ins := []
	for path: String in foes:
		stand_ins.append(load(path))
	await ShaderWarmup.run(self, items, ShaderWarmup.spots(self, $Player.global_position), 3, stand_ins)
	sample.free()


func _exit_tree() -> void:
	for samples in _warm_keep:
		if is_instance_valid(samples):
			samples.free()
	_warm_keep.clear()


func _process(delta: float) -> void:
	super(delta)
	_track_zone()
	if zone == &"ruins" and ruins != null:
		_show_ruins_hud()
	elif zone == &"forest":
		_hero_caption.text = forest.zone_title() + ("   /   BONFIRE LIT" if forest.bonfire_lit else "")
		$Interface/GuardMeters.visible = false


func _update_music() -> void:
	if zone == &"forest":
		Music.set_intensity(2 if forest.engaged() and not _forest_fallen else 1)
	elif zone == &"ruins" and ruins != null:
		Music.set_intensity(2 if ruins_outcome == &"" and ruins.engaged() else (0 if ruins_outcome == &"defeat" else 1))
	else:
		super()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_duel") and _forest_fallen:
		_rise_in_forest()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") and outcome == &"victory" and _gate_prompt != null:
		if not _gate.is_open and _gate_prompt.global_position.distance_to(_hero.body.global_position + Vector3.UP * 1.45) < GATE_DISTANCE:
			open_gate()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"restart_duel") and ruins_outcome == &"defeat":
		respawn_in_ruins()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"restart_duel") and _gate.is_open:
		get_viewport().set_input_as_handled()
	else:
		super(event)


func open_gate() -> void:
	_gate_prompt.hide()
	# What the far side will need, read from disk on worker threads while the player fights on.
	Music.preload_area(&"forest")
	for path: String in ForestArea.foe_scenes():
		ResourceLoader.load_threaded_request(path)
	_spawn_ruins()
	# The forest starts streaming a frame later, after the gate's own frame.
	_start_forest.call_deferred()
	_gate.open()
	_audio.play_cue(&"gate_open", _gate_prompt.global_position)
	$Player/CameraRig.add_trauma(0.45)
	RetroFX.flash(0.18, Color(1.0, 0.5, 0.2))
	_show_notice("The seal burns away", 2.4)


func respawn_in_ruins() -> void:
	ruins_outcome = &""
	_result.hide()
	_spawn_ruins()
	var player := $Player as CharacterBody3D
	player.global_transform = ruins.entrance_transform()
	player.reset_physics_interpolation()
	player.get_node("CameraRig").snap()
	player.velocity = Vector3.ZERO
	player.get_node("Heading").rotation.y = 0.0
	player.get_node("CameraRig").lock_target = null
	_hero.revive()
	player.can_fight = true
	_show_notice("OUTER RUINS", 2.0)


func _finish(result: StringName) -> void:
	if result == &"defeat" and zone == &"forest":
		_forest_fall()
		return
	if result == &"defeat" and outcome == &"victory":
		# Falling past the gate: the Gatekeeper stays dead, the ruins reset at their entrance.
		_ruins_finish(&"defeat")
		return
	super(result)


## The ruins behind the gate. Their foes join one per frame and the rest of the setup is spread
## over frames too, so opening the gate or rising in the ruins does not stall a frame.
func _spawn_ruins() -> void:
	if ruins != null:
		ruins.queue_free()
		ruins.name = "FallenRuins"
	if _ruins_scene == null:
		_ruins_scene = ResourceLoader.load_threaded_get(RUINS_AREA) as PackedScene
	var area: Node3D = _ruins_scene.instantiate()
	ruins = area
	area.name = "OuterRuinsArea"
	var held: Array[Node] = []
	var roster := area.get_node("Enemies")
	for enemy in roster.get_children():
		enemy.owner = null
		roster.remove_child(enemy)
		held.append(enemy)
	add_child(area)
	area.position = RUINS_OFFSET
	area.reset_physics_interpolation()
	# One foe a frame: each one's rig takes a few milliseconds to set up.
	for i in held.size():
		await get_tree().process_frame
		if not is_instance_valid(area) or not area.is_inside_tree():
			for left in held:
				if is_instance_valid(left) and not left.is_inside_tree():
					left.free()
			return
		var enemy: Node = held[i]
		enemy.set(&"player", $Player)
		roster.add_child(enemy)
		enemy.owner = area
	area.setup($Player, true)
	area.portal.destination_ready = _forest_entry_ready
	area.set_backdrop_visible(zone == &"ruins")
	for enemy in area.enemies():
		enemy.get_node("Combat").feedback.connect(_on_feedback)
	area.cleared.connect(_ruins_finish.bind(&"victory"))
	area.portal_entered.connect(_enter_forest)
	area.enemy_defeated.connect(func(_enemy: Node) -> void: _show_notice("%d LEFT" % area.remaining, 1.2))
	Weather.bind_area(self)
	if not area.is_set_up:
		await area.set_up
	if is_instance_valid(area) and area.is_inside_tree():
		await Music.attach_torches(area, true)


func _track_zone() -> void:
	if not _gate.is_open or zone == &"forest":
		return
	var z: float = $Player.global_position.z
	var next := zone
	if zone == &"court" and z < BORDER_Z - BORDER_MARGIN:
		next = &"ruins"
	elif zone == &"ruins" and z > BORDER_Z + BORDER_MARGIN:
		next = &"court"
	if next == zone:
		return
	zone = next
	var in_ruins := zone == &"ruins"
	_court_hills.visible = not in_ruins
	if ruins != null:
		ruins.set_backdrop_visible(in_ruins)
	Music.play_area(&"ruins" if in_ruins else &"court", 3.0)
	Weather.set_preset(&"ruins" if in_ruins else &"court")
	$Interface/GuardMeters/Posture.visible = not in_ruins
	if in_ruins:
		if not _ruins_announced:
			_ruins_announced = true
			_show_notice("OUTER RUINS", 2.2)
	else:
		$Interface/GuardMeters.visible = true
		_guard_caption.text = "THE ASH GATEKEEPER"
		_hero_caption.text = "VITALITY  /  STAMINA"
		_guard_hp.max_value = _guard.max_health


func _show_ruins_hud() -> void:
	_hero_caption.text = "OUTER RUINS   /   %d LEFT" % ruins.remaining
	# Ruins foes carry thin bars over their heads; the top bar is the Gatekeeper's alone.
	$Interface/GuardMeters.visible = false


func _ruins_finish(result: StringName) -> void:
	if ruins_outcome != &"":
		return
	ruins_outcome = result
	if result == &"defeat":
		$Player.can_fight = false
		for enemy in ruins.enemies():
			enemy.ai_enabled = false
	_audio.play_cue(result, _hero.body.global_position)
	_result_title.text = "THE RUINS FALL SILENT" if result == &"victory" else "YOU FELL"
	$Interface/Result/Messages/Retry.text = "Exploring on" if result == &"victory" else "T / Menu   Rise at the ruins' entrance"
	get_tree().create_timer(0.55).timeout.connect(_result.show)
	if result == &"victory":
		get_tree().create_timer(3.5).timeout.connect(_result.hide)
		get_tree().create_timer(3.8).timeout.connect(_open_eclipse)



# ---------------------------------------------------------------- the Thornwood

## The forest is built a little each frame from the moment the seal burns, far from the court,
## so it is ready long before the eclipse ring opens.
func _start_forest() -> void:
	if forest != null:
		return
	forest = (load(FOREST_AREA) as PackedScene).instantiate()
	forest.name = "ThornwoodArea"
	forest.active = false
	add_child(forest)
	forest.position = FOREST_OFFSET
	forest.reset_physics_interpolation()
	forest.foe_spawned.connect(func(foe: CharacterBody3D) -> void: foe.get_node("Combat").feedback.connect(_on_feedback))
	forest.rested.connect(_on_forest_rested)
	forest.zone_changed.connect(func(_zone: StringName, title: String) -> void: _show_notice(title, 2.2))
	forest.ambushed.connect(func(at: Vector3) -> void: _audio.play_cue(&"ambush", at, 1.0))
	await forest.setup($Player, true)
	get_node(^"/root/Perf").mark(&"forest:torches")
	forest.set_active(zone == &"forest")
	await Music.attach_torches(forest, true)


func _open_eclipse() -> void:
	if ruins == null or ruins_outcome != &"victory":
		return
	ruins.open_portal()
	_audio.play_cue(&"portal_open", ruins.portal.to_global(ruins.portal.CENTER))
	_show_notice("The eclipse ring stirs", 2.6)


## Ready to receive the player: ground, collision and the spawn exist (navigation may still be
## baking; the forest keeps its ambushes asleep until it is).
func _forest_entry_ready() -> bool:
	return forest != null and forest.entry_ready()


func _enter_forest() -> void:
	if _transitioning or not _forest_entry_ready():
		ruins.portal.unlock()
		return
	_transitioning = true
	_audio.play_cue(&"portal_enter", $Player.global_position)
	$Player.can_fight = false
	RetroFX.pass_through(Color(0.08, 0.05, 0.16), _arrive_in_forest)


func _arrive_in_forest() -> void:
	_transitioning = false
	if _hero.health <= 0.0 or not _forest_entry_ready():
		# The crossing could not finish: stay, hand control back, let the portal take a press.
		ruins.portal.unlock()
		$Player.can_fight = _hero.health > 0.0
		return
	zone = &"forest"
	get_node(^"/root/Perf").mark(&"portal:arrive")
	forest.set_active(true)
	_place_player(forest.entrance_transform())
	$Player.can_fight = true
	# The veil is opaque for a moment: the rest of the hand-over is spread over its frames.
	await get_tree().process_frame
	get_node(^"/root/Perf").mark(&"portal:environment")
	for holder in find_children("*", "WorldEnvironment", true, false):
		if not forest.is_ancestor_of(holder):
			(holder as WorldEnvironment).environment = ForestArea.environment()
	for light in find_children("*", "DirectionalLight3D", true, false):
		ForestArea.tune_moon(light)
	if ruins != null:
		ruins.set_backdrop_visible(false)
	_court_hills.visible = false
	await get_tree().process_frame
	get_node(^"/root/Perf").mark(&"portal:music")
	Music.play_area(&"forest", 2.5)
	await get_tree().process_frame
	get_node(^"/root/Perf").mark(&"portal:weather")
	Weather.set_preset(&"forest")
	Weather.bind_area(forest)
	# The way back is closed: the ruins and their foes are freed while the veil still covers it.
	if ruins != null:
		ruins.queue_free()
		ruins = null
	# Still under the veil: compile the forest's and the zones' shaders now rather than as each
	# thing first comes into view.
	await get_tree().process_frame
	if not OS.get_cmdline_user_args().has("--no-warmup"):
		get_node(^"/root/Perf").mark(&"portal:warmup")
		var items := ShaderWarmup.gather(forest)
		# The zones are built later, on approach: warm their kinds of material now too, and keep
		# the stand-ins so those shaders stay compiled until the zones use them.
		_warm_keep.clear()
		for area: Node3D in [forest.crossing, forest.belfry]:
			var samples: Node3D = area.warmup_samples()
			_warm_keep.append(samples)
			items.append_array(ShaderWarmup.gather(samples))
		var stand_ins := []
		for path: String in ForestArea.foe_scenes():
			stand_ins.append(load(path))
		await ShaderWarmup.run(forest, items, ShaderWarmup.spots(forest, forest.entrance_transform().origin), 3, stand_ins)
	# The portal's hum fades out by the standing stones.
	_audio.play_cue(&"portal_open", forest.entrance_transform().origin + Vector3(0, 1.5, 2.0), 0.3)
	_show_notice("THE THORNWOOD", 2.6)


func _place_player(at: Transform3D) -> void:
	var player := $Player as CharacterBody3D
	player.global_transform = at
	player.velocity = Vector3.ZERO
	player.drive = Vector3.ZERO
	player.commands.clear()
	player.reset_physics_interpolation()
	player.get_node("Heading").rotation.y = 0.0
	var camera := player.get_node("CameraRig")
	camera.lock_target = null
	camera.rotation.y = 0.0
	camera.snap()


func _forest_fall() -> void:
	if _forest_fallen:
		return
	_forest_fallen = true
	$Player.can_fight = false
	_audio.play_cue(&"defeat", _hero.body.global_position)
	_result_title.text = "YOU FELL"
	$Interface/Result/Messages/Retry.text = "T / Menu   Rise at the bonfire" if forest.bonfire_lit else "T / Menu   Rise at the forest's edge"
	get_tree().create_timer(0.55).timeout.connect(_result.show)


func _rise_in_forest() -> void:
	_forest_fallen = false
	_result.hide()
	forest.reset_foes()
	_place_player(forest.respawn_transform())
	_hero.revive()
	$Player.can_fight = true


func _on_forest_rested() -> void:
	_hero.revive()
	_audio.play_cue(&"bonfire", forest.bonfire_transform().origin, 1.0)
	_show_notice("BONFIRE LIT" if not has_meta(&"rested_once") else "Rested  ·  The forest stirs again", 2.6)
	set_meta(&"rested_once", true)
