extends Node3D
## Standalone Thornwood: the forest with its own player and HUD. The expedition reaches the
## same area through the eclipse ring; this scene keeps it playable and testable alone.

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const FoeBars = preload("res://scenes/ui/foe_bars.gd")
const HudUtil = preload("res://scenes/ui/hud_util.gd")
const ForestArea = preload("res://scenes/forest/forest_area.gd")

var fallen := false
var _notice_time: float
var _focus: ProgressBar

@onready var _area: ForestArea = $Area
@onready var _hero: Combatant = $Player/Combat
@onready var _audio: Node3D = $Audio
@onready var _vitality: ProgressBar = %Vitality
@onready var _stamina: ProgressBar = %Stamina
@onready var _group_status: Label = %GroupStatus
@onready var _notice: Label = %Notice
@onready var _result: PanelContainer = %Result
@onready var _result_title: Label = %ResultTitle


func _ready() -> void:
	_area.foe_spawned.connect(_on_foe_spawned)
	_area.setup($Player, false)
	_place_player(_area.entrance_transform())
	Music.play_area(&"forest", 2.0)
	Weather.set_preset(&"forest")
	Weather.bind_area(self)
	RetroFX.prewarm.call_deferred(get_viewport().get_camera_3d())
	Music.attach_torches(_area)
	_hero.defeated.connect(_on_defeated)
	_hero.feedback.connect(_play_feedback)
	_focus = HudUtil.add_focus_bar(_stamina)
	FoeBars.install($Interface)
	_hero.weapon_changed.connect(func(weapon: SoulsWeapon) -> void: _set_notice(HudUtil.weapon_notice(weapon), 2.0))
	_area.rested.connect(_on_rested)
	_area.ambushed.connect(func(at: Vector3) -> void: _audio.play_cue(&"ambush", at, 1.0))
	_set_notice("THE THORNWOOD", 2.4)


func _on_foe_spawned(foe: CharacterBody3D) -> void:
	foe.get_node("Combat").feedback.connect(_play_feedback)


func _place_player(at: Transform3D) -> void:
	var player := $Player as CharacterBody3D
	player.global_transform = at
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.get_node("Heading").rotation.y = 0.0
	var camera := player.get_node("CameraRig")
	camera.lock_target = null
	camera.rotation.y = 0.0
	camera.snap()


func _process(delta: float) -> void:
	Music.set_intensity(2 if _area.engaged() and not fallen else 1)
	_vitality.value = _hero.health
	_stamina.value = _hero.stamina
	_focus.value = _hero.focus
	_group_status.text = "THE THORNWOOD" + ("   /   BONFIRE LIT" if _area.bonfire_lit else "")
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


## Rises at the bonfire once it is lit, else at the forest's edge; the forest's foes return.
func rise() -> void:
	fallen = false
	_result.hide()
	_area.reset_foes()
	_place_player(_area.respawn_transform())
	_hero.revive()
	$Player.can_fight = true


func _on_rested() -> void:
	_hero.revive()
	_audio.play_cue(&"bonfire", _area.bonfire_transform().origin, 1.0)
	_set_notice("BONFIRE LIT" if not has_meta(&"rested_once") else "Rested  ·  The forest stirs again", 2.6)
	set_meta(&"rested_once", true)


func _play_feedback(cue: StringName, at: Vector3, strength: float = 0.5) -> void:
	_audio.play_cue(cue, at, strength)
	$Player.on_world_impact(cue, at, strength)
	match cue:
		&"parry": _set_notice("Parried  ·  Counter now")
		&"guard_break": _set_notice("Guard broken")
		&"tired": _set_notice("Out of stamina")
		&"exhausted": _set_notice("Exhausted")
		&"posture_break": _set_notice("Posture broken  ·  Strike now")
		&"shockwave": RetroFX.shockwave(at, 3.0)
		&"nova": RetroFX.shockwave(at, 2.8, Color(0.66, 0.58, 1.0))
		&"critical": _set_notice("Critical")
		&"no_focus": _set_notice("Not enough focus")


func _set_notice(message: String, duration: float = 0.9) -> void:
	_notice.text = message
	_notice_time = duration
