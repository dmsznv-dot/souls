extends Node3D

const Combatant = preload("res://scenes/duel/combat/combatant.gd")
const HudUtil = preload("res://scenes/ui/hud_util.gd")
const NoirLighting = preload("res://scenes/fx/noir_lighting.gd")
## Magenta neon fills: the gate's flanking arches and a rim from behind the player's start.
const ACCENTS := [Vector3(-4.4, 2.4, -10.6), Vector3(4.4, 2.4, -10.6), Vector3(0.0, 4.6, 7.8)]
const GATE_DISTANCE := 2.45

@export_file("*.tscn") var post_victory_path: String

var outcome: StringName
var _debug_enabled: bool
var _notice_time: float
var _reset_requested: bool
var _focus: ProgressBar

@onready var _hero: Combatant = $Player/Combat
@onready var _guard: Combatant = $Guard/Combat
@onready var _audio: Node3D = $Audio
@onready var _player_hp: ProgressBar = %PlayerHP
@onready var _stamina: ProgressBar = %Stamina
@onready var _guard_hp: ProgressBar = %GuardHP
@onready var _posture: ProgressBar = %Posture
@onready var _notice: Label = %Notice
@onready var _debug: Label = %Debug
@onready var _result: PanelContainer = %Result
@onready var _result_title: Label = %ResultTitle
@onready var _hero_arc: MeshInstance3D = $HeroArc
@onready var _guard_arc: MeshInstance3D = $GuardArc
@onready var _gate_prompt := get_node_or_null("GatePrompt") as Label3D


func _ready() -> void:
	_hero.feedback.connect(_on_feedback)
	_guard.feedback.connect(_on_feedback)
	_hero.defeated.connect(_finish.bind(&"defeat"))
	_guard.defeated.connect(_finish.bind(&"victory"))
	_guard_hp.max_value = _guard.max_health
	NoirLighting.apply($Environment, ACCENTS)
	NoirLighting.toon(self)
	Music.play_area(&"court", 1.5)
	Weather.set_preset(&"court")
	Weather.bind_area(self)
	RetroFX.prewarm.call_deferred(get_viewport().get_camera_3d())
	Music.attach_torches(self)
	_focus = HudUtil.add_focus_bar(_stamina)
	_hero.weapon_changed.connect(func(weapon: SoulsWeapon) -> void: _show_notice(HudUtil.weapon_notice(weapon), 2.2))
	if not post_victory_path.is_empty():
		$Guard.phase_changed.connect(_on_boss_phase)
		$Interface/GuardMeters/Caption.text = "THE ASH GATEKEEPER"
		$Interface/Bindings/Keys/Other.text = "Shift / L3  Sprint   ·   Tab / D-pad  Weapon   ·   F / X  Jump   ·   E / A  Gate   ·   T  Retry   ·   F2  Debug"


func _process(delta: float) -> void:
	_update_music()
	_player_hp.value = _hero.health
	_stamina.value = _hero.stamina
	_focus.value = _hero.focus
	_guard_hp.value = _guard.health
	_posture.value = _guard.posture
	_notice_time = maxf(0.0, _notice_time - delta)
	_notice.visible = _notice_time > 0.0
	_stamina.self_modulate = Color(1.0, 0.64, 0.54) if _notice.visible and _notice.text == "Out of stamina" else Color.WHITE
	if _debug_enabled:
		_debug.text = "Hero  %s   |   Watcher  %s   |   Buffer  %s" % [
			_hero.phase_name(), _guard.phase_name(), $Player.buffer_status()]
		_draw_attack(_hero, _hero_arc)
		_draw_attack(_guard, _guard_arc)


func _update_music() -> void:
	if outcome == &"":
		Music.set_intensity(2 if $Guard.is_engaged() else 1)
	else:
		Music.set_intensity(1 if outcome == &"victory" else 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and outcome == &"victory" and _gate_prompt != null:
		if not _reset_requested and _gate_prompt.global_position.distance_to(_hero.body.global_position + Vector3.UP * 1.45) < GATE_DISTANCE:
			_reset_requested = true
			get_tree().change_scene_to_file.bind(post_victory_path).call_deferred()
	elif event.is_action_pressed(&"restart_duel") and not _reset_requested:
		_reset_requested = true
		get_tree().reload_current_scene.call_deferred()
	elif event.is_action_pressed(&"combat_debug"):
		_debug_enabled = not _debug_enabled
		_debug.visible = _debug_enabled
		_hero_arc.visible = _debug_enabled
		_guard_arc.visible = _debug_enabled


func _finish(result: StringName) -> void:
	if outcome != &"":
		return
	outcome = result
	$Player.can_fight = result == &"victory" and _gate_prompt != null
	$Guard.ai_enabled = false
	if result == &"victory":
		$Guard/LockPoint.hide()
		$Guard.set_deferred("collision_layer", 0)
		$Guard.set_deferred("collision_mask", 1)
	var fallen := _guard if result == &"victory" else _hero
	_audio.play_cue(result, fallen.body.global_position)
	if result == &"victory" and _gate_prompt != null:
		_gate_prompt.show()
		_show_notice("Gate unsealed · Approach the gate and press E / A", 4.0)
		return
	_result_title.text = "WATCHER DEFEATED" if result == &"victory" else "YOU FELL"
	get_tree().create_timer(0.52).timeout.connect(_result.show)


func _on_boss_phase(phase: int) -> void:
	Music.set_combat_phase(phase)
	$Interface/GuardMeters/Caption.text = "THE ASH GATEKEEPER  ·  %s" % ("II" if phase == 2 else "I")
	_show_notice("The Gatekeeper readies his blade", 1.8)


func _on_feedback(cue: StringName, location: Vector3, strength: float = 0.5) -> void:
	_audio.play_cue(cue, location, strength)
	$Player.on_world_impact(cue, location, strength)
	match cue:
		&"tired":
			_show_notice("Out of stamina")
		&"parry":
			_show_notice("Parried  ·  Counter now")
			_sparks(location, Color(0.56, 0.95, 0.98), 18)
		&"guard_break":
			_show_notice("Guard broken")
			_sparks(location, Color(1.0, 0.50, 0.26), 14)
		&"block":
			_sparks(location, Color(1.0, 0.80, 0.41), 9)
		&"hit":
			_sparks(location, Color(1.0, 0.64, 0.42), 7)
		&"shockwave":
			RetroFX.shockwave(location, 3.0)
		&"nova":
			RetroFX.shockwave(location, 2.8, Color(0.66, 0.58, 1.0))
		&"critical":
			_show_notice("Critical", 0.8)
		&"no_focus":
			_show_notice("Not enough focus")


func _show_notice(message: String, duration: float = 0.85) -> void:
	_notice.text = message
	_notice_time = duration


func _sparks(location: Vector3, color: Color, count: int) -> void:
	RetroFX.sparks(location, color, count)


func _draw_attack(actor: Combatant, instance: MeshInstance3D) -> void:
	var mesh := instance.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var attack := actor.attack
	if attack == null:
		return
	var start := actor.body.global_position + Vector3.UP * 0.08
	var forward := -actor.heading.global_basis.z
	var half_arc := deg_to_rad(attack.arc / 2.0)
	var tint := Color(0.46, 0.92, 0.69) if actor.lunge_speed() > 0.0 else Color(0.96, 0.69, 0.32)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, instance.material_override)
	mesh.surface_set_color(tint)
	mesh.surface_add_vertex(to_local(start))
	for step in range(25):
		var angle := lerpf(-half_arc, half_arc, float(step) / 24.0)
		mesh.surface_add_vertex(to_local(start + forward.rotated(Vector3.UP, angle) * attack.reach))
	mesh.surface_add_vertex(to_local(start))
	mesh.surface_end()
