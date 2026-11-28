extends RefCounted
## One-slot command buffer with absolute expiry in physics ticks. A press is captured on the
## nearest physics tick and stays valid while tick < capture + TTL: light/heavy 10 ticks, roll
## 11, parry and jump 6. Expiry runs on regardless of hit-stop. A newer press replaces the
## slot; presses captured on the same tick resolve Roll > Parry > Heavy > Light > Jump.

const TTL := {&"roll": 11, &"parry": 6, &"heavy_attack": 10, &"light_attack": 10, &"jump": 6}
const PRIORITY := {&"roll": 5, &"parry": 4, &"heavy_attack": 3, &"light_attack": 2, &"jump": 1}

var action: StringName = &""
var capture_tick: int = -1
var expires_at: int = -1


func offer(next: StringName, tick: int) -> void:
	if not TTL.has(next) or tick < capture_tick:
		return
	if tick == capture_tick and action != &"" and int(PRIORITY[next]) <= int(PRIORITY[action]):
		return
	action = next
	capture_tick = tick
	expires_at = tick + int(TTL[next])


func peek(tick: int) -> StringName:
	if action != &"" and tick >= expires_at:
		clear()
	return action if tick >= capture_tick else &""


func clear() -> void:
	action = &""
	capture_tick = -1
	expires_at = -1


func describe(tick: int) -> String:
	if action == &"" or tick >= expires_at:
		return "—"
	return "%s %d t" % [action, expires_at - tick]
