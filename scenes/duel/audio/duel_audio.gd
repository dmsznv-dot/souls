extends Node3D
## Plays combat one-shots at the world position of the event. Every cue draws from a pool of
## takes with pitch and volume variation, so repeated swings and steps never machine-gun.
## The blow's strength picks the swing weight class and lowers pitch for heavy weapons.

const SFX := "res://assets/audio/sfx/"
const POOLS := {
	&"swing_light": ["swing_light_0", "swing_light_1", "swing_light_2"],
	&"swing_medium": ["swing_medium_0", "swing_medium_1", "swing_medium_2"],
	&"swing_heavy": ["swing_heavy_0", "swing_heavy_1", "swing_heavy_2"],
	&"hit": ["hit_0", "hit_1", "hit_2"],
	&"block": ["block_0", "block_1", "block_2"],
	&"guard_break": ["guard_break"],
	&"parry": ["parry"],
	&"roll": ["roll_0", "roll_1"],
	&"windup": ["windup"],
	&"land": ["land"],
	&"death": ["death"],
	&"tired": ["tired"],
	&"gate_open": ["gate_open"],
}
const STINGER_CUES: Array[StringName] = [&"victory", &"defeat"]
const VOLUME_DB := -4.0

var _streams: Dictionary = {}


func _ready() -> void:
	for cue: StringName in POOLS:
		var pool := AudioStreamRandomizer.new()
		for take: String in POOLS[cue]:
			pool.add_stream(-1, load(SFX + take + ".wav"))
		pool.random_pitch = 1.06
		pool.random_volume_offset_db = 1.5
		_streams[cue] = pool


func play_cue(cue: StringName, at: Vector3, strength: float = 0.5) -> void:
	if cue in STINGER_CUES:
		var music := get_node_or_null(^"/root/Music")
		if music != null:
			music.stinger(cue)
		return
	var pitch := 1.0
	var gain := 0.0
	match cue:
		&"swing", &"heavy":
			cue = &"swing_light" if strength < 0.3 else (&"swing_medium" if strength < 0.65 else &"swing_heavy")
			pitch = lerpf(1.12, 0.86, strength)
		&"hit", &"block":
			pitch = lerpf(1.1, 0.84, strength)
			gain = lerpf(-2.0, 1.5, strength)
	var stream: AudioStream = _streams.get(cue)
	if stream == null:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.bus = &"SFX"
	voice.volume_db = VOLUME_DB + gain
	voice.max_db = 3.0
	voice.pitch_scale = pitch
	voice.unit_size = 10.0
	voice.max_distance = 40.0
	voice.panning_strength = 0.7
	voice.top_level = true
	add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free, CONNECT_ONE_SHOT)
	voice.play()
