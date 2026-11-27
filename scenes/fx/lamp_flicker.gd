extends Node
## Flame flicker for the parent light: two slow wobbles and an occasional gutter.

var _base: float
var _clock: float
var _gutter: float


func _ready() -> void:
	_base = (get_parent() as Light3D).light_energy
	_clock = randf() * 100.0


func _process(delta: float) -> void:
	_clock += delta
	if _gutter <= 0.0 and randf() < delta * 0.25:
		_gutter = 0.18
	_gutter = maxf(0.0, _gutter - delta)
	var wobble := 0.08 * sin(_clock * 7.3) + 0.05 * sin(_clock * 13.1 + 1.7) + 0.04 * sin(_clock * 2.1)
	(get_parent() as Light3D).light_energy = _base * (1.0 + wobble - (0.35 if _gutter > 0.0 else 0.0))
