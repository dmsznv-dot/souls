extends Node3D
## Plays combat one-shots at the world position of the event.

const CUES: Dictionary[StringName, AudioStream] = {
	&"windup": preload("res://scenes/duel/audio/windup.wav"),
	&"swing": preload("res://scenes/duel/audio/swing.wav"),
	&"heavy": preload("res://scenes/duel/audio/heavy.wav"),
	&"hit": preload("res://scenes/duel/audio/hit.wav"),
	&"block": preload("res://scenes/duel/audio/block.wav"),
	&"guard_break": preload("res://scenes/duel/audio/guard_break.wav"),
	&"parry": preload("res://scenes/duel/audio/parry.wav"),
	&"roll": preload("res://scenes/duel/audio/roll.wav"),
	&"victory": preload("res://scenes/duel/audio/victory.wav"),
	&"defeat": preload("res://scenes/duel/audio/defeat.wav"),
}
const VOLUME_DB := -7.0


func play_cue(cue: StringName, at: Vector3) -> void:
	var stream: AudioStream = CUES.get(cue)
	if stream == null:
		return

	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.bus = &"Master"
	voice.volume_db = VOLUME_DB
	voice.max_db = VOLUME_DB
	voice.unit_size = 10.0
	voice.max_distance = 36.0
	voice.panning_strength = 0.7
	voice.top_level = true
	add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free, CONNECT_ONE_SHOT)
	voice.play()
