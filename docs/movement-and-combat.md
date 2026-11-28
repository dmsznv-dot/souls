# Movement and combat: decisions log

Souls 0.7 applies the movement-and-feel parts of the *Souls 0.6 movement and combat
specification* (reference commit `0630304`). Every number is a tuning target from that spec,
not a value taken from Elden Ring or Dark Souls. Physics runs at 60 Hz; "t" means ticks.

## Applied

| Area | Now | Was |
| --- | --- | --- |
| Speeds | walk 2.0 / run 4.5 / sprint 6.3 m/s; one radial deadzone 0.22, walk up to 0.55 of stick travel, then run | run 4.5, sprint 6.4, no walk band |
| Motor | driven velocity and external push kept apart; push added once per tick and trimmed against walls; one owner of horizontal motion per tick (reaction > action > skid > locomotion) | push folded into the velocity the next tick started from |
| Acceleration | 32 m/s² up, 38 braking, 44 against a reversal (old momentum is killed first); air control x0.35 | 38 / 24 |
| Skid | from the floor at >= 4.2 m/s with >= 0.55 stick and a >= 130 degree reversal; 38 m/s² along the old line, at most 8 t, ends early on a stop, an action or leaving the floor; no push-off kick | 3.4 m/s, 0.24 s, kick 1.6 m/s |
| Turning | 720 deg/s running, 480 sprinting, 600 locked on | 14 rad/s |
| Lock-on movement | sideways x0.85, backward x0.75; a target almost underfoot keeps the last valid basis | full speed every way |
| Landing | falling at >= 7 m/s costs 6 t of recovery | none |
| Floor | max angle 45 degrees, snap 0.18 m, safe margin 0.002 m, stop on slope, constant speed | engine defaults |
| Load classes | (armour + active weapon) / 50 kg: light < 0.30, medium < 0.70, heavy <= 1.00, overload. Speed x1.02 / 1.00 / 0.87 / 0.62, acceleration x1.10 / 1.00 / 0.82 / 0.70. The skeleton's kit is 20 kg, so every weapon is medium today; heavier armour presets will show the difference | weapon mass alone scaled walking speed |
| Roll | medium 39 t, i-frames [5, 21) t, 2.95 m, 22 stamina (light 34 t / [4, 21) / 3.25 m / 18; heavy 49 t / [7, 20) / 2.25 m / 29; none when overloaded). Distance follows a cumulative curve (0, 0) (0.15, 0.12) (0.42, 0.62) (0.75, 0.96) (1, 1); walls cut it without carrying the rest over; no input is a 70 % backstep; protection closes if the ground is lost | 0.62 s, i-frames 0.05-0.36 s, speed burst 8.6 m/s |
| Command buffer | absolute expiry in ticks: light/heavy 10, roll 11, parry/jump 6; a press is valid through capture + TTL - 1; expiry runs during hit-stop; same-tick presses resolve roll > parry > heavy > light > jump; cleared on death, respawn and weapon change | one 0.26 s slot that stopped ageing once a swing became active |
| Cancels | windup and active never cancel; in recovery the roll may cut in at its window, the next light only continues a multi-link chain; heavy, parry, jump and weapon change wait for idle. Every condition and cost is checked before the recovery is cut | the chain point applied to any command, and the recovery was cut before checking the next action could start |
| Attack steering | first half of the windup, at most 45 degrees from the starting yaw, at most 540 deg/s, toward the locked target when locked | first 60 % of the windup, no total limit |
| Weapon timings | the spec's windup / active / recovery, chain and roll windows, stamina, damage, posture and block costs for all 18 player attacks (section 8). Greatsword heavy: hyper armour from tick 28 of its windup | earlier hand-tuned values |
| Stamina | full cost up front (exactly 0 left is allowed); 24/s after a 0.65 s pause; a raised guard regenerates at 25 %; sprinting costs 13/s and stops regeneration, starts at >= 10, stops at 0 and needs the button released; running dry: 1.5 s without regeneration, then 16/s until 35 | half cost was enough; sprinting regenerated faster than it drained (24/s against 13/s), so it was free |
| Block | the guard is up after 4 t of holding; walking speed while guarding x0.55 | instant, x0.38 |
| Parry | [0, 4) startup, [4, 11) active, 28 t total; success recovers in 10 t, melee only | window 0.035-0.20 s of 0.42 s |
| Hit-stop | per outcome: light hit 2 t (impact < 0.30), medium 3 t, heavy 5 t; block 2 t; parry 4 t | 0.04-0.12 s scaled by impact |
| Poise | husk 12, hero and ordinary foes 28, brute 65, Gatekeeper 100. A break flinches for 12 t, or staggers for 22 t when impact >= 0.65. The hero now has poise too: a single light cut no longer flinches him | the hero flinched from every hit; flinch 0.30-0.42 s |
| Camera | follow 16 / 8 per second, stick 160 deg/s, sprint FOV +4 degrees, return 4 m/s | 14 / 7, 2.6 rad/s, +5 |
| Lock-on | acquire within 18 m and 55 degrees of the camera's centre; best score 0.70 x screen offset + 0.30 x distance; held to 21 m; switching needs a 3 % screen move and has a 15 t cooldown | 20 m, most centred target, no hold range |
| Foes | read only what is visible (a reeling hero, a swing in recovery), never the hero's stamina; decide to evade once per attack after a 12-17 t reaction delay (9-13 t for quick foes); windup tracking stops at mid windup and turns at most 35 degrees (50 for heavies and bosses); the 0.45 s gap between attack starts also holds for punishes | read hero stamina; evade checked every tick; tracking to 75 % of the windup with no limit |
| Stability | a foe told to stand (pursuit speed 0) no longer divides by zero and feeds NaN into the rig; `tools/run_tests.sh` fails a suite on any script error or non-finite value in its log | the search test logged NaN while passing |

## Deferred, with reasons

- **Tick-integer timeline and a shared contact pass after posing** (spec sections 3 and 10).
  Attack timings are still seconds (now exact multiples of a tick), and each fighter sweeps its
  own blade inside `advance()` before moving. Moving every fighter first and resolving all
  contacts in one ordered pass changes the core loop of every scene; it deserves its own step
  with the boundary tests H1-H5.
- **Attack instance and hit-group ids, parry tags (`parryable`, `unparryable`, `guardable`),
  weapon-guard absorption and guard-break 50 % pass-through.** Same reason: they belong to the
  contact pass.
- **Equipment preset resources and armour/shield masses.** The load classes are live, driven by
  `armor_mass` on the player; presets come with armour that changes the model.
- **Step-up sweep for 0.18 m steps, moving platforms.** No such geometry exists yet.
- **Camera shape-cast corner handling beyond the SpringArm3D sphere.** The arm already casts a
  sphere against the world; the spec's overlap search is for tight corners we do not have.
- **F2 event history with CSV/JSONL export, single-tick stepping arena, root-motion A/B for the
  tachi dash, landing-confirmed AoE for the leap slam, enemy W/A/R table.** Tooling and tuning
  passes after the contact rework.

## Checks

`tests/movement.gd` covers M1 (90 % of run speed in 8 t, stop in 7-8 t, 0.55 stick = 2.0 m/s),
M2 (skid only at a run, a roll takes over), D1 (i-frames exactly [5, 21), 2.94 m roll, 2.06 m
backstep, a wall cuts the roll), T2 (buffer expiry and priority) and C2 (acquire 18 m, hold
21 m). `tests/duel.gd` checks the longsword L1 windows on ticks 23/24 and 27/28 (T1), and
`tests/poise.gd` the stamina rules (D4). Run everything with `tools/run_tests.sh <godot>`.
