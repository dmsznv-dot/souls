extends Node3D

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const CAPTIONS := {
	&"spearman": "PALE SPEARMAN",
	&"shield": "ASH SHIELDBEARER",
	&"thrower": "CINDER THROWER",
}

var remaining_enemies: int
var outcome: StringName
var _notice_time: float
var _retry_pending: bool

@onready var _hero: Combatant = $Player/Combat
@onready var _audio: Node3D = $Audio
@onready var _enemies := $Enemies.get_children()
@onready var _vitality: ProgressBar = %Vitality
@onready var _stamina: ProgressBar = %Stamina
@onready var _group_status: Label = %GroupStatus
@onready var _opponent_name: Label = %OpponentName
@onready var _opponent_health: ProgressBar = %OpponentHealth
@onready var _notice: Label = %Notice
@onready var _result: PanelContainer = %Result
@onready var _result_title: Label = %ResultTitle


func _ready() -> void:
	remaining_enemies = _enemies.size()
	_hero.defeated.connect(_finish.bind(&"defeat"))
	_hero.feedback.connect(_play_feedback)
	for enemy in _enemies:
		var combat: Combatant = enemy.get_node("Combat")
		combat.defeated.connect(_enemy_defeated.bind(enemy))
		combat.feedback.connect(_play_feedback)
	_update_status()


func _process(delta: float) -> void:
	_vitality.value = _hero.health
	_stamina.value = _hero.stamina
	_notice_time = maxf(0.0, _notice_time - delta)
	_notice.visible = _notice_time > 0.0
	var enemy := _visible_opponent()
	_opponent_name.visible = enemy != null
	_opponent_health.visible = enemy != null
	if enemy != null:
		var combat: Combatant = enemy.get_node("Combat")
		_opponent_name.text = CAPTIONS[enemy.role]
		_opponent_health.max_value = combat.max_health
		_opponent_health.value = combat.health


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart_duel") and not _retry_pending:
		_retry_pending = true
		get_tree().reload_current_scene.call_deferred()


func _visible_opponent() -> Node3D:
	var marker: Marker3D = $Player/CameraRig.lock_target
	if is_instance_valid(marker) and marker.is_visible_in_tree():
		return marker.get_parent() as Node3D
	var nearest: Node3D
	var range_squared := 42.25
	for enemy in _enemies:
		var distance: float = enemy.global_position.distance_squared_to(_hero.body.global_position)
		if enemy.get_node("Combat").health > 0.0 and distance < range_squared:
			range_squared = distance
			nearest = enemy
	return nearest


func _enemy_defeated(enemy: CharacterBody3D) -> void:
	enemy.ai_enabled = false
	enemy.get_node("LockPoint").hide()
	enemy.set_deferred("collision_layer", 0)
	enemy.set_deferred("collision_mask", 1)
	remaining_enemies -= 1
	_update_status()
	if remaining_enemies == 0:
		_finish(&"victory")


func _update_status() -> void:
	_group_status.text = "OUTER RUINS   /   %d LEFT" % remaining_enemies


func _finish(result: StringName) -> void:
	if outcome != &"":
		return
	outcome = result
	$Player.can_fight = false
	for enemy in _enemies:
		enemy.ai_enabled = false
	_audio.play_cue(result, _hero.body.global_position)
	_result_title.text = "THE RUINS FALL SILENT" if result == &"victory" else "YOU FELL"
	get_tree().create_timer(0.55).timeout.connect(_result.show)


func _play_feedback(cue: StringName, at: Vector3) -> void:
	_audio.play_cue(cue, at)
	match cue:
		&"parry": _set_notice("Parried  ·  Counter now")
		&"guard_break": _set_notice("Guard broken")
		&"tired": _set_notice("Out of stamina")


func _set_notice(message: String) -> void:
	_notice.text = message
	_notice_time = 0.9
