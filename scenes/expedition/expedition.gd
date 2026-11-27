extends "res://scenes/duel/courtyard_duel.gd"
## The Ash Gate expedition as one continuous place. The Outer Ruins stream in on a background
## thread during the Gatekeeper fight; after his defeat the seal burns away and the player walks
## across a short bridge into the ruins. Nothing reloads: zone changes swap distant backdrops
## inside the gate's archway, crossfade the score and switch the HUD.

const RUINS_AREA := "res://scenes/expedition/outer_ruins_area.tscn"
const OuterRuins = preload("res://scenes/expedition/outer_ruins.gd")
## Places the ruins' entrance arch just behind the court's seal gate.
const RUINS_OFFSET := Vector3(0.0, 0.0, -25.2)
## Court/ruins border on the bridge, with hysteresis so standing on it never flickers.
const BORDER_Z := -14.6
const BORDER_MARGIN := 0.4

var zone: StringName = &"court"
var ruins: Node3D
var ruins_outcome: StringName
var _ruins_scene: PackedScene
var _ruins_announced: bool

@onready var _gate: Node3D = $AshGate
@onready var _court_hills: Node3D = $Environment/Court/AshHills
@onready var _guard_caption: Label = $Interface/GuardMeters/Caption
@onready var _hero_caption: Label = $Interface/HeroMeters/Caption


func _ready() -> void:
	super()
	ResourceLoader.load_threaded_request(RUINS_AREA, "PackedScene")


func _process(delta: float) -> void:
	super(delta)
	_track_zone()
	if zone == &"ruins" and ruins != null:
		_show_ruins_hud()


func _update_music() -> void:
	if zone == &"ruins" and ruins != null:
		Music.set_intensity(2 if ruins_outcome == &"" and ruins.engaged() else (0 if ruins_outcome == &"defeat" else 1))
	else:
		super()


func _unhandled_input(event: InputEvent) -> void:
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
	_spawn_ruins()
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
	if result == &"defeat" and outcome == &"victory":
		# Falling past the gate: the Gatekeeper stays dead, the ruins reset at their entrance.
		_ruins_finish(&"defeat")
		return
	super(result)


func _spawn_ruins() -> void:
	if ruins != null:
		ruins.queue_free()
		ruins.name = "FallenRuins"
	if _ruins_scene == null:
		_ruins_scene = ResourceLoader.load_threaded_get(RUINS_AREA) as PackedScene
	ruins = _ruins_scene.instantiate()
	ruins.name = "OuterRuinsArea"
	add_child(ruins)
	ruins.position = RUINS_OFFSET
	ruins.reset_physics_interpolation()
	ruins.setup($Player, true)
	ruins.set_backdrop_visible(zone == &"ruins")
	for enemy in ruins.enemies():
		enemy.get_node("Combat").feedback.connect(_on_feedback)
	ruins.cleared.connect(_ruins_finish.bind(&"victory"))
	ruins.enemy_defeated.connect(func(_enemy: Node) -> void: _show_notice("%d LEFT" % ruins.remaining, 1.2))
	Music.attach_torches(ruins)


func _track_zone() -> void:
	if not _gate.is_open:
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
	var enemy := OuterRuins.nearest_opponent($Player, ruins)
	$Interface/GuardMeters.visible = enemy != null
	if enemy != null:
		var combat: Node = enemy.get_node("Combat")
		_guard_caption.text = ruins.caption(enemy)
		_guard_hp.max_value = combat.max_health
		_guard_hp.value = combat.health


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
