extends Node
## Autoload "Music". Every area has an exploration score and a separate combat theme, each a
## set of sample-aligned stems in one AudioStreamSynchronized. When a foe notices the player a
## stinger hits, the exploration score drops away and the combat theme starts from its top;
## when the fight ends the score returns. Areas crossfade, so walking across the bridge
## never cuts the music.
##
## Intensity: 0 = exploration base only (aftermath), 1 = exploration with melody, 2 = combat.
## Combat phase 2 adds the theme's third stem (choir and bells for the Gatekeeper).

const AREAS := {
	&"court": {
		"explore": ["res://assets/audio/music/court_pad.ogg", "res://assets/audio/music/court_melody.ogg"],
		"combat": ["res://assets/audio/music/court_combat_rhythm.ogg", "res://assets/audio/music/court_combat_lead.ogg",
			"res://assets/audio/music/court_combat_phase.ogg"],
	},
	&"ruins": {
		"explore": ["res://assets/audio/music/ruins_base.ogg", "res://assets/audio/music/ruins_melody.ogg"],
		"combat": ["res://assets/audio/music/ruins_combat_rhythm.ogg", "res://assets/audio/music/ruins_combat_lead.ogg",
			"res://assets/audio/music/ruins_combat_phase.ogg"],
	},
	# The Thornwood explores to its own night score and fights to the ruins' combat theme.
	&"forest": {
		"explore": ["res://assets/audio/music/forest_base.ogg", "res://assets/audio/music/forest_melody.ogg"],
		"combat": ["res://assets/audio/music/ruins_combat_rhythm.ogg", "res://assets/audio/music/ruins_combat_lead.ogg",
			"res://assets/audio/music/ruins_combat_phase.ogg"],
	},
}
const STINGERS := {
	&"victory": "res://assets/audio/music/victory.ogg",
	&"defeat": "res://assets/audio/music/defeat.ogg",
	&"notice": "res://assets/audio/music/notice.ogg",
}
const WIND := "res://assets/audio/ambience/wind.ogg"
const TORCH := "res://assets/audio/ambience/torch.ogg"
const SILENT_DB := -60.0
## Seconds before another notice stinger may play.
const NOTICE_REST := 10.0

var area: StringName
var intensity: int = 1
var combat_phase: int = 1
var _players: Dictionary = {}
var _gain: Dictionary = {}
var _layer_db: Dictionary = {}
var _wind: AudioStreamPlayer
var _stinger: AudioStreamPlayer
var _duck: float
var _notice_rest: float


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


## Starts reading an area's score from disk on worker threads, so play_area finds it loaded.
func preload_area(next: StringName) -> void:
	if not AREAS.has(next):
		return
	for kind in ["explore", "combat"]:
		for path: String in AREAS[next][kind]:
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(path)


func play_area(next: StringName, crossfade: float = 3.0) -> void:
	if not AREAS.has(next):
		return
	for kind in ["explore", "combat"]:
		var key := _key(next, kind)
		if _players.has(key):
			continue
		var paths: Array = AREAS[next][kind]
		var synced := AudioStreamSynchronized.new()
		synced.stream_count = paths.size()
		for i in paths.size():
			synced.set_sync_stream(i, _looping(paths[i]))
			synced.set_sync_stream_volume(i, SILENT_DB)
		var player := AudioStreamPlayer.new()
		player.name = "Score_%s" % String(key).replace(":", "_")
		player.stream = synced
		player.bus = &"Music"
		player.volume_db = SILENT_DB
		add_child(player)
		_players[key] = player
		_gain[key] = 0.0
		var layers := PackedFloat32Array()
		layers.resize(paths.size())
		layers.fill(SILENT_DB)
		_layer_db[key] = layers
	area = next
	if not _wind.playing:
		_wind.play()
	set_meta(&"crossfade", maxf(crossfade, 0.05))


## 0..2. Entering combat plays the notice stinger and restarts the combat theme.
func set_intensity(level: int) -> void:
	level = clampi(level, 0, 2)
	if level == 2 and intensity < 2 and not area.is_empty():
		var combat: AudioStreamPlayer = _players[_key(area, "combat")]
		if _gain[_key(area, "combat")] < 0.05:
			combat.play()
		if _notice_rest <= 0.0:
			stinger(&"notice")
			_notice_rest = NOTICE_REST
	if level < 2:
		combat_phase = 1
	intensity = level


func set_combat_phase(phase: int) -> void:
	combat_phase = clampi(phase, 1, 2)


func stinger(name: StringName) -> void:
	if not STINGERS.has(name):
		return
	_stinger.stream = load(STINGERS[name])
	_stinger.play()
	_duck = 0.8 if name == &"notice" else 3.5


func stop_all() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()
	_wind.stop()
	area = &""


## Positional crackle on every lantern light under root (names starting with "Lamp").
## Paced: a few voices per frame, so a big streamed area does not start forty players at once.
func attach_torches(root: Node, paced: bool = false) -> void:
	var started := 0
	for light in root.find_children("*", "OmniLight3D", true, false):
		if not is_instance_valid(light) or light.has_node("Crackle") or not (light.name.begins_with("Lamp") or light.name.begins_with("WatchFire")):
			continue
		started += 1
		if paced and started % 4 == 0:
			await get_tree().process_frame
			if not is_instance_valid(light):
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
	_notice_rest = maxf(0.0, _notice_rest - real_delta)
	var fade_time: float = get_meta(&"crossfade", 3.0)
	for key: StringName in _players:
		var player: AudioStreamPlayer = _players[key]
		var parts := String(key).split(":")
		var in_area := StringName(parts[0]) == area
		var combat := parts[1] == "combat"
		var wanted := in_area and (combat == (intensity == 2))
		# Into a fight quickly, out of it slowly; area changes use the crossfade time.
		var rate := (1.0 / 0.6 if combat else 1.0 / 1.6) if in_area else 1.0 / fade_time
		_gain[key] = move_toward(_gain[key], 1.0 if wanted else 0.0, real_delta * rate)
		if wanted and not player.playing:
			player.play()
		var ducked := 0.45 if _duck > 0.0 else 1.0
		player.volume_db = linear_to_db(maxf(_gain[key] * ducked, 0.001))
		if _gain[key] <= 0.0 and player.playing:
			player.stop()
		var synced := player.stream as AudioStreamSynchronized
		var layers: PackedFloat32Array = _layer_db[key]
		for i in layers.size():
			var target := _layer_target(combat, i)
			var current := db_to_linear(layers[i])
			var next := move_toward(current, db_to_linear(target), real_delta / 1.2)
			layers[i] = linear_to_db(maxf(next, 0.001))
			synced.set_sync_stream_volume(i, layers[i])
		_layer_db[key] = layers


func _layer_target(combat: bool, layer: int) -> float:
	if combat:
		return 0.0 if layer < 2 or combat_phase == 2 else SILENT_DB
	if layer == 0:
		return 0.0
	return -1.5 if intensity >= 1 else SILENT_DB


func _key(area_name: StringName, kind: String) -> StringName:
	return StringName("%s:%s" % [area_name, kind])


func _looping(path: String) -> AudioStream:
	var stream := load(path)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	return stream
