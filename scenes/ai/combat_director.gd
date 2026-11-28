extends Node
## Autoload "Director". Shares the fight between foes the way modern action games do: only a
## few may attack at once (attack tokens), their attacks are spaced so they arrive one after
## another rather than together, and a foe that spots the player calls nearby allies.

## Total token weight in play at once. Ordinary foes cost 1, heavies 2.
const BUDGET := 3
## Minimum gap between two different foes starting attacks.
const STAGGER := 0.45
const TOKEN_TIMEOUT := 3.0
## A foe waiting longer than this goes first; others are held back until it gets its turn.
const PRIORITY_WAIT := 3.0
## A foe waiting longer than this may attack even over budget: nobody idles forever.
const STARVED_WAIT := 6.0

var _holders: Dictionary = {}
var _since_attack: float = 10.0
## id -> [seconds waiting, seconds since its last request]
var _waiting: Dictionary = {}


func _physics_process(delta: float) -> void:
	_since_attack += delta
	for id in _waiting.keys():
		var waiter: Array = _waiting[id]
		waiter[0] += delta
		waiter[1] += delta
		if waiter[1] > 0.5 or not is_instance_valid(instance_from_id(id)):
			_waiting.erase(id)
	for id in _holders.keys():
		var entry: Array = _holders[id]
		entry[1] -= delta
		if entry[1] <= 0.0 or not is_instance_valid(instance_from_id(id)):
			_holders.erase(id)


## Asks to attack now. Urgent requests (punishing an opening) may exceed the budget by one.
func request(foe: Node, cost: int = 1, urgent: bool = false) -> bool:
	var id := foe.get_instance_id()
	if _holders.has(id):
		return true
	if not _waiting.has(id):
		_waiting[id] = [0.0, 0.0]
	_waiting[id][1] = 0.0
	var waited: float = _waiting[id][0]
	# Longest waiter first, so heavies that need two slots are not starved by quick foes.
	var oldest := id
	for other in _waiting:
		if _waiting[other][0] > _waiting[oldest][0]:
			oldest = other
	if oldest != id and _waiting[oldest][0] > PRIORITY_WAIT and not urgent:
		return false
	var used := 0
	for entry: Array in _holders.values():
		used += entry[0]
	var limit := BUDGET + (1 if urgent or waited > STARVED_WAIT else 0)
	if waited > STARVED_WAIT:
		cost = mini(cost, 1)
	# The 0.45 s gap between different foes' starts holds even for a punish.
	if used + cost > limit or (_since_attack < STAGGER and waited < STARVED_WAIT):
		return false
	_holders[id] = [cost, TOKEN_TIMEOUT]
	_waiting.erase(id)
	_since_attack = 0.0
	return true


func release(foe: Node) -> void:
	_holders.erase(foe.get_instance_id())


func holds(foe: Node) -> bool:
	return _holders.has(foe.get_instance_id())


## A foe that has spotted the player rouses every other foe within the radius.
func alert(from: Node3D, radius: float) -> void:
	for foe in from.get_tree().get_nodes_in_group(&"foes"):
		if foe != from and foe.global_position.distance_to(from.global_position) <= radius:
			foe.call_deferred(&"hear_alarm", from.global_position)


func reset() -> void:
	_holders.clear()
	_waiting.clear()
	_since_attack = 10.0
