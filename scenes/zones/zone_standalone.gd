extends Node3D
## A zone played on its own (crossing.tscn, belfry.tscn): the area, a player, the HUD, the
## Thornwood's night sky. Falling rises the hero at the zone's respawn point with foes back.

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const FoeBars = preload("res://scenes/ui/foe_bars.gd")
const HudUtil = preload("res://scenes/ui/hud_util.gd")
const ForestArea = preload("res://scenes/forest/forest_area.gd")
const NoirLighting = preload("res://scenes/fx/noir_lighting.gd")

var fallen := false
var _notice_time: float
var _focus: ProgressBar

@onready var _area: Node3D = $Area
@onready var _hero: Combatant = $Player/Combat
@onready var _audio: Node3D = $Audio
@onready var _vitality: ProgressBar = %Vitality
@onready var _stamina: ProgressBar = %Stamina
@onready var _group_status: Label = %GroupStatus
@onready var _notice: Label = %Notice
@onready var _result: PanelContainer = %Result
@onready var _result_title: Label = %ResultTitle


func _ready() -> void:
	var sky := WorldEnvironment.new()
	sky.environment = ForestArea.environment()
	add_child(sky)
	var moon := DirectionalLight3D.new()
	add_child(moon)
	_area.foe_spawned.connect(func(foe: CharacterBody3D) -> void: foe.get_node("Combat").feedback.connect(_play_feedback))
	await _area.prepare($Player, false)
	NoirLighting.apply(self)
	ForestArea.tune_moon(moon)
	for flicker in find_children("Flicker", "Node", true, false):
		flicker.set_base_energy((flicker.get_parent() as Light3D).light_energy)
	_area.activate()
	_place_player(_area.entrance_transform())
	Music.play_area(&"forest", 2.0)
	Weather.set_preset(_area.weather_preset)
	Weather.bind_area(self)
	RetroFX.prewarm.call_deferred(get_viewport().get_camera_3d())
	Music.attach_torches(_area)
	_hero.defeated.connect(_on_defeated)
	_hero.feedback.connect(_play_feedback)
	_focus = HudUtil.add_focus_bar(_stamina)
	FoeBars.install($Interface)
	_set_notice(_area.title, 2.4)


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


func _process(delta: float) -> void:
	if not _area.prepared:
		return
	Music.set_intensity(2 if _area.engaged() and not fallen else 1)
	_vitality.value = _hero.health
	_stamina.value = _hero.stamina
	_focus.value = _hero.focus
	_group_status.text = _area.title
	_notice_time = maxf(0.0, _notice_time - delta)
	_notice.visible = _notice_time > 0.0
	%OpponentName.visible = false
	%OpponentHealth.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_duel") and fallen:
		rise()
		get_viewport().set_input_as_handled()


func _on_defeated() -> void:
	fallen = true
	$Player.can_fight = false
	_audio.play_cue(&"defeat", _hero.body.global_position)
	_result_title.text = "YOU FELL"
	get_tree().create_timer(0.55).timeout.connect(_result.show)


func rise() -> void:
	fallen = false
	_result.hide()
	_area.reset_foes()
	_place_player(_area.respawn_transform())
	_hero.revive()
	$Player.can_fight = true


func _play_feedback(cue: StringName, at: Vector3, strength: float = 0.5) -> void:
	_audio.play_cue(cue, at, strength)
	$Player.on_world_impact(cue, at, strength)
	match cue:
		&"parry": _set_notice("Parried  ·  Counter now")
		&"guard_break": _set_notice("Guard broken")
		&"tired": _set_notice("Out of stamina")
		&"exhausted": _set_notice("Exhausted")
		&"posture_break": _set_notice("Posture broken  ·  Strike now")
		&"critical": _set_notice("Critical")


func _set_notice(message: String, duration: float = 0.9) -> void:
	_notice.text = message
	_notice_time = duration
