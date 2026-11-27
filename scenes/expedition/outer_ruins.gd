extends Node3D
## Standalone Outer Ruins: the area with its own player and HUD. The expedition reaches the
## same area seamlessly from the Ash Court; this scene keeps it playable and testable alone.

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const HudUtil = preload("res://scenes/ui/hud_util.gd")

var remaining_enemies: int
var outcome: StringName
var _notice_time: float
var _retry_pending: bool
var _focus: ProgressBar

@onready var _area: Node3D = $Area
@onready var _hero: Combatant = $Player/Combat
@onready var _audio: Node3D = $Audio
@onready var _vitality: ProgressBar = %Vitality
@onready var _stamina: ProgressBar = %Stamina
@onready var _group_status: Label = %GroupStatus
@onready var _opponent_name: Label = %OpponentName
@onready var _opponent_health: ProgressBar = %OpponentHealth
@onready var _notice: Label = %Notice
@onready var _result: PanelContainer = %Result
@onready var _result_title: Label = %ResultTitle


func _ready() -> void:
	_area.setup($Player, false)
	remaining_enemies = _area.remaining
	Music.play_area(&"ruins", 2.0)
	Weather.set_preset(&"ruins")
	Weather.bind_area(self)
	RetroFX.prewarm.call_deferred(get_viewport().get_camera_3d())
	Music.attach_torches(self)
	_hero.defeated.connect(_finish.bind(&"defeat"))
	_hero.feedback.connect(_play_feedback)
	_focus = HudUtil.add_focus_bar(_stamina)
	_hero.weapon_changed.connect(func(weapon: SoulsWeapon) -> void: _set_notice(HudUtil.weapon_notice(weapon)))
	for enemy in _area.enemies():
		enemy.get_node("Combat").feedback.connect(_play_feedback)
	_area.enemy_defeated.connect(func(_enemy: Node) -> void:
		remaining_enemies = _area.remaining
		_update_status())
	_area.cleared.connect(_finish.bind(&"victory"))
	_update_status()


func _process(delta: float) -> void:
	var engaged: bool = outcome == &"" and _area.engaged()
	Music.set_intensity(2 if engaged else (0 if outcome == &"defeat" else 1))
	_vitality.value = _hero.health
	_stamina.value = _hero.stamina
	_focus.value = _hero.focus
	_notice_time = maxf(0.0, _notice_time - delta)
	_notice.visible = _notice_time > 0.0
	var enemy := _visible_opponent()
	_opponent_name.visible = enemy != null
	_opponent_health.visible = enemy != null
	if enemy != null:
		var combat: Combatant = enemy.get_node("Combat")
		_opponent_name.text = _area.caption(enemy)
		_opponent_health.max_value = combat.max_health
		_opponent_health.value = combat.health


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_duel") and not _retry_pending:
		_retry_pending = true
		get_tree().reload_current_scene.call_deferred()


func _visible_opponent() -> Node3D:
	return nearest_opponent($Player, _area)


## Locked target if any, else the closest living enemy within 6.5 m.
static func nearest_opponent(player: Node3D, area: Node3D) -> Node3D:
	var marker: Marker3D = player.get_node("CameraRig").lock_target
	if is_instance_valid(marker) and marker.is_visible_in_tree() and marker.get_parent().get_parent() == area.get_node("Enemies"):
		return marker.get_parent() as Node3D
	var nearest: Node3D
	var range_squared := 42.25
	for enemy in area.enemies():
		var distance: float = enemy.global_position.distance_squared_to(player.global_position)
		if enemy.get_node("Combat").health > 0.0 and distance < range_squared:
			range_squared = distance
			nearest = enemy
	return nearest


func _update_status() -> void:
	_group_status.text = "OUTER RUINS   /   %d LEFT" % remaining_enemies


func _finish(result: StringName) -> void:
	if outcome != &"":
		return
	outcome = result
	$Player.can_fight = false
	for enemy in _area.enemies():
		enemy.ai_enabled = false
	_audio.play_cue(result, _hero.body.global_position)
	_result_title.text = "THE RUINS FALL SILENT" if result == &"victory" else "YOU FELL"
	get_tree().create_timer(0.55).timeout.connect(_result.show)


func _play_feedback(cue: StringName, at: Vector3, strength: float = 0.5) -> void:
	_audio.play_cue(cue, at, strength)
	$Player.on_world_impact(cue, at, strength)
	match cue:
		&"parry": _set_notice("Parried  ·  Counter now")
		&"guard_break": _set_notice("Guard broken")
		&"tired": _set_notice("Out of stamina")
		&"shockwave": RetroFX.shockwave(at, 3.0)
		&"nova": RetroFX.shockwave(at, 2.8, Color(0.66, 0.58, 1.0))
		&"critical": _set_notice("Critical")
		&"no_focus": _set_notice("Not enough focus")


func _set_notice(message: String) -> void:
	_notice.text = message
	_notice_time = 0.9
