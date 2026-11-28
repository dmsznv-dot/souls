# Thornwood and the zones beyond

Souls 0.8 follows the Thornwood and new-locations specification (reference commit `260da31`).
Distances along the forest road are metres from the arrival stones.

## Route

```text
Outer Ruins -> Eclipse -> arrival stones -> patrol trail -> dead oak -> lowland
  -> abandoned convoy -> bonfire clearing -> (on foot, no transition) Flooded Crossing
  -> Belfry under the Roots
```

| Stretch | Groups | Interactions |
| --- | --- | --- |
| 0-18 m, arrival | wet stones underfoot, drops from the crowns, violet glow between the stelae; the first lantern 10 m ahead | no fight, no breakables; drizzle 0.16 |
| 18-55 m, patrol trail | a post with a rag in the wind, a lean-to with two crates | first ambush unchanged; crates break |
| 55-95 m, dead oak | a pocket 14 m off the road (clear of trees), a great snag, a stump with faintly breathing caps (no light), a niche of stone under the roots behind a rotten grate | grate opens the niche (1 heavy or 3 light blows) and stays open |
| 95-140 m, lowland | puddles that catch firelight, stones at the water's edge, dripping crowns | brute ambush with a fighting pocket; drizzle 0.16 |
| 140-195 m, convoy | a cart run nose-down into the ditch beside a fallen trunk, a wet tarp, two crates and a barrel spilled toward the road | breakables; the road stays 3.4 m clear |
| clearing | ring of wet stones, a stranger's cold camp, one violet echo stela at the edge | bonfire unchanged; 3.5 m around it clear |

Every ambush landing has a 3 m radius free of props and a pocket of about 6 m kept clear of
trees. Authored spots clear generated growth after its random draws, so every other tree and
plant keeps its place (checked against the old layout: identical trunk list).

## Light, wind and weather

- `scenes/fx/fire_light.gd` replaces the old flicker. One component owns a light's energy:
  `base_energy x ignition x envelope`. The envelope is a slow swell (0.4-0.9 Hz) plus a small
  unevenness (1.2-2.2 Hz) with a phase per source, a quick dip on each gust that eases back,
  and the odd gutter for lanterns. The hot point drifts a few centimetres downwind of where the
  light stands, flames lean with the wind (torches up to 22 degrees), and lantern glass and
  bonfire embers glow with a smaller swing from their own material copy. Profiles: lantern
  (sheltered), torch, bonfire. The bonfire's kindling tweens `ignition` from 0.13 to 1.
- `scenes/forest/foliage_wind.gdshader` sways firs, oaks and ferns from two global shader
  parameters (`forest_wind_xz`, `forest_gust`) that `Weather` sets from the shared wind. The
  bottom fifth of a tree barely moves; each instance has its own phase in `INSTANCE_CUSTOM`.
  Snags, rocks and logs stay still. **F7** cycles the wind: as authored, still, held gust.
- `Weather`: the forest eases out of the ruins' storm in a few seconds; drizzle comes back in
  the open stretches (`local_rain`); splashes sit on the ground sampled ten times a second;
  wet stone and mud dry over about ten seconds and gloss less than the ruins; materials set on
  instances (the generated ground) now get wet too.

## Breakable props

`scenes/environment/breakable_prop.gd`: crate (one blow), barrel (one heavy or two light),
rotten grate (one heavy or three light). The hero's blade sweep tests the Breakable physics
layer (4) with the same sub-steps as against foes; one count per swing, nothing through a
wall. Breaking hides the prop, drops its collision after the physics step and throws light
fragments that touch only the world and vanish after about two seconds (at most 24 at once).
Crates and barrels come back on a rest or a rise, once nobody stands in their place; an
opened grate stays open. Props carry ids `area/anchor/prop`.

## Portal contract

The eclipse portal takes the press only when the far side is ready (`entry_ready`: ground,
collision and spawn) and the hero is alive; the prompt uses the same check. A press locks it;
if the crossing cannot finish (death during the fade, the far side gone) it unlocks and the
player keeps control. Arrival clears speed, queued commands and the lock. Ambushes wait for
`combat_ready` (navigation baked).

## Zones

Both are built by `scenes/zones/zone_area.gd` subclasses with `prepare -> activate ->
deactivate`: geometry in the project's materials, lights, foes, breakables, navigation baked
on a thread when streamed and settled onto the floor. The forest builds both and tracks which
one the player is in (weather, sound loops, foes). Each also runs alone:
`scenes/zones/crossing.tscn`, `scenes/zones/belfry.tscn`.

### Flooded Crossing (about 95 m)

| Part | Detail |
| --- | --- |
| Entry | the clearing's south edge opens (no trees, level ground, a gap in the boundary); a wet slope between trunks runs 3 m down to a mud bank |
| Main way | plank walk on piles (18 m), islet with the warden's hut and a lantern swinging with the wind, second walk (16 m), far bank, 14 stone steps up |
| Side loop | a shallow ford west of the islet, about 22 m, back to the far bank; splashes underfoot |
| Fight | the islet's open front, 6 x 8 m, wider than the walk: a spearman at the hut, a thorn crawler on the islet |
| Water | deep water drowns: the hero rises at the last fire (forest bonfire, or the zone's start when played alone) |
| Props | two crates by the hut, a broken old walk beside the new one |
| Weather and sound | preset `crossing`: steady drizzle, glossier surfaces; water lapping under the walks |

### Belfry under the Roots (about 60 m)

| Part | Detail |
| --- | --- |
| Entry | a gorge with roots overhead narrows into a crypt arch; a tilted tunnel runs 4 m down |
| Lower chamber | 17 x 15 m, one campfire, cold glints at the roots; the fight is on the floor (a shieldbearer) |
| Niche | a rotten grate in the west wall; the passage behind it loops back into the chamber; bones and caps inside |
| Gallery | a ramp up the east wall to the bell hall, a husk on it |
| Arch | a ritual arch with a dormant violet glow at the foot of the stairs |
| Bell hall | the bell hangs from the roots in a shaft open to the sky with a cold wash of light; a gust rings it (at most every 9 s) and the chamber answers with a fading hum |
| Exit | stairs to a landing under the sky with a lantern at the door, visible from the hall; the content ends here |
| Respawn | reaching the gorge mouth makes it the place to rise (until the next rest at the bonfire) |
| Weather and sound | preset `belfry`: rain only at the mouth, dripping inside |

## Checks

`tests/zones.gd` (41 checks): fire liveliness, phase and drift; wind reaching and leaving the
crowns; breakables (one count per swing, two light swings for a barrel, fragments limited and
gone, reset, a wall blocks the blow, the grate stays open); composition groups, unique ids,
nothing near landings or the bonfire; both zones walkable on their navigation from entry to
exit (the crossing also through the ford, the belfry also by the gallery); drowning and rising;
the bell; walking on from the clearing into both zones and the belfry checkpoint; the portal's
readiness, lock and unlock. Streaming the forest with both zones keeps frames at or under about
17 ms apart from the first load of a foe scene (already loaded in the expedition by the ruins).

Not done yet: F4 build/emitter counters, a debug view of anchors and no-prop zones, the new
arch's effect (it stays a landmark until it has a destination), a dedicated music cue per zone
(both use the forest score), moving water normals beyond the shader's noise.
