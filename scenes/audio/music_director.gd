extends Node
## Autoload "Music". Each area plays three sample-aligned stems in one AudioStreamSynchronized:
## base, melody and battle. Intensity fades stems in and out without losing sync; changing area
## crossfades two such players, so walking from one area into the next never cuts the score.
##
## Intensity: 0 = base only (aftermath, menus), 1 = exploring (base + melody), 2 = combat (all).

const AREAS := {
	&"court": ["res://assets/audio/music/court_pad.ogg", "res://assets/audio/music/court_melody.ogg",
		"res://assets/audio/music/court_battle.ogg"],
	&"ruins": ["res://assets/audio/music/ruins_base.ogg", "res://assets/audio/music/ruins_melody.ogg",
		"res://assets/audio/music/ruins_battle.ogg"],
}
const STINGERS := {
	&"victory": "res://assets/audio/music/victory.ogg",
	&"defeat": "res://assets/audio/music/defeat.ogg",
}
const WIND := "res://assets/audio/ambience/wind.ogg"
const TORCH := "res://assets/audio/ambience/torch.ogg"
const SILENT_DB := -60.0
## Layer gains per intensity, in dB: [base, melody, battle].
const MIX := [[0.0, SILENT_DB, SILENT_DB], [0.0, -1.5, SILENT_DB], [-2.0, -5.0, 0.0]]

var area: StringName
var intensity: int = 1
var _players: Dictionary = {}
var _area_gain: Dictionary = {}
var _layer_db: Dictionary = {}
var _wind: AudioStreamPlayer
var _stinger: AudioStreamPlayer
var _duck: float


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wind = AudioStreamPlayer.new()
	_wind.stream = _looping(WIND)
	_wind.bus = &"Ambience"
	_wind.volume_db = -4.0
	add_child(_wind)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = &"Music"
	add_child(_stinger)


func _exit_tree() -> void:
	stop_all()
	_stinger.stop()
	for player: AudioStreamPlayer in _players.values():
		player.stream = null
	_players.clear()


func play_area(next: StringName, crossfade: float = 3.0) -> void:
	if not AREAS.has(next):
		return
	if not _players.has(next):
		var synced := AudioStreamSynchronized.new()
		synced.stream_count = 3
		for i in 3:
			synced.set_sync_stream(i, _looping(AREAS[next][i]))
			synced.set_sync_stream_volume(i, SILENT_DB)
		var player := AudioStreamPlayer.new()
		player.name = "Score_%s" % next
		player.stream = synced
		player.bus = &"Music"
		player.volume_db = SILENT_DB
		add_child(player)
		_players[next] = player
		_area_gain[next] = 0.0
		_layer_db[next] = PackedFloat32Array([SILENT_DB, SILENT_DB, SILENT_DB])
	area = next
	var player: AudioStreamPlayer = _players[next]
	if not player.playing:
		player.play()
	if not _wind.playing:
		_wind.play()
	set_meta(&"crossfade", maxf(crossfade, 0.05))


func set_intensity(level: int) -> void:
	intensity = clampi(level, 0, 2)


func stinger(name: StringName) -> void:
	if not STINGERS.has(name):
		return
	_stinger.stream = load(STINGERS[name])
	_stinger.play()
	_duck = 3.5


func stop_all() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()
	_wind.stop()
	area = &""


## Positional crackle on every lantern light under root (names starting with "Lamp").
func attach_torches(root: Node) -> void:
	for light in root.find_children("Lamp*", "OmniLight3D", true, false):
		if light.has_node("Crackle"):
			continue
		var crackle := AudioStreamPlayer3D.new()
		crackle.name = "Crackle"
		crackle.stream = _looping(TORCH)
		crackle.bus = &"Ambience"
		crackle.unit_size = 2.5
		crackle.max_distance = 14.0
		crackle.volume_db = -6.0
		light.add_child(crackle)
		crackle.play(randf() * 7.0)


func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.0001)
	_duck = maxf(0.0, _duck - real_delta)
	var fade_time: float = get_meta(&"crossfade", 3.0)
	for key: StringName in _players:
		var player: AudioStreamPlayer = _players[key]
		var goal := 1.0 if key == area else 0.0
		_area_gain[key] = move_toward(_area_gain[key], goal, real_delta / fade_time)
		var ducked := 0.45 if _duck > 0.0 else 1.0
		player.volume_db = linear_to_db(maxf(_area_gain[key] * ducked, 0.001))
		if _area_gain[key] <= 0.0 and key != area and player.playing:
			player.stop()
		var synced := player.stream as AudioStreamSynchronized
		var layers: PackedFloat32Array = _layer_db[key]
		for i in 3:
			var target: float = MIX[intensity][i]
			# Layers move in amplitude, about 1.2 s for a full fade, so entries swell rather than cut.
			var current := db_to_linear(layers[i])
			var next := move_toward(current, db_to_linear(target), real_delta / 1.2)
			layers[i] = linear_to_db(maxf(next, 0.001))
			synced.set_sync_stream_volume(i, layers[i])
		_layer_db[key] = layers


func _looping(path: String) -> AudioStream:
	var stream := load(path)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	return stream
