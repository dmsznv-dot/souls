# Souls

Souls is an early-stage 3D soulslike prototype built in Godot 4.7.2 with GDScript. The visual direction draws on low-poly PS1 and Nintendo 64 games. The combat design focuses on responsive movement, readable enemy attacks, and boss fights that reward learning their patterns.

## First playable milestone

One test arena, one weapon, and one boss. The prototype will test lock-on camera behavior, dodge input buffering, stamina, and attack timing. The first boss will use distinct windups and punish windows so players can learn when to dodge, reposition, or counterattack.

Souls 0.4 opens in the Ash Court against the Ash Gatekeeper, who now swings a greatsword. Read his sweep and thrust in the first phase. Below half health he finishes his current move and adds a follow-up overhead strike. Defeat him, approach the gate and press **E** or **A**: the seal burns away and a short bridge leads straight into the Outer Ruins. Nothing loads; the ruins stream in during the boss fight. The spearman, shieldbearer and cinder thrower guard the road to the shrine. If you fall in the ruins, **T** or **Menu** raises you at their entrance with the guards restored, and the Gatekeeper stays defeated.

The hero is an armoured skeleton carrying three weapons. Each weapon has its own mass, reach and swing timing. Hits come from the blade itself: the striking edge is swept between physics steps and tested against each body, so a short blade misses where a greatsword connects. Light attacks chain into a return cut, a buffered dodge cancels late recovery, and full-weight blows shove and flinch.

The controller test arena and the shorter training duel are available in `scenes/arena/` and `scenes/duel/`. The ruins can also be played alone from `scenes/expedition/outer_ruins.tscn`.

## Run locally

1. Install the standard Godot 4.7.2 editor.
2. Keep the complete project in one folder. If you downloaded the ZIP, extract it and use the `Souls` folder inside it.
3. In the Godot Project Manager, choose **Import** and select `project.godot` inside that folder, next to `scenes/`. Godot treats the folder containing `project.godot` as the project root and scans it for assets.
4. Press **F5** to start the expedition. Its entry scene is `scenes/expedition/boss_court.tscn`.

| Action | Keyboard and mouse | Xbox controller |
| --- | --- | --- |
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Lock or release target | Middle mouse button | R3 |
| Light attack | Left mouse button | RB |
| Heavy attack | R | RT |
| Block | Hold right mouse button | Hold LB |
| Parry | Q | LT |
| Dodge | Space | B |
| Sprint | Hold Shift | Hold L3 |
| Switch weapon | Tab | D-pad right |
| Jump | F | X |
| Open the seal gate | E | A |
| Retry current area | T | Menu |

Press **Esc** to release the mouse cursor. Left-click the game window to capture it again. **F3** toggles the retro presentation.

Heavy attacks deal more posture damage. A frontal parry interrupts a melee attack and makes the first follow-up strike hit harder. The shieldbearer opens up during an attack. Cover can intercept the thrower's visible bolts. Press **F2** in the Ash Court to inspect attack arcs, phases, and queued input.

| Weapon | Mass | Character |
| --- | --- | --- |
| Ashen Longsword | 3 kg | Balanced default. Reaches about 2.0 m centre to centre. |
| Pilgrim Shortsword | 1.6 kg | Fastest recovery, earliest cancels, about 1.8 m reach. |
| Gatebreaker Greatsword | 9 kg | Two-handed, slow and committed, about 2.8 m reach, long hit-stop, staggers on heavy blows. |

Weapons live in `scenes/combat/weapons/` as `SoulsWeapon` resources: blade length, grip, mass and the light chain and heavy attack. Attack resources expose timing, damage, posture, AI engagement distance, impact weight and the chain and roll-cancel points in the Inspector. Sword arms follow authored blade paths (`SWINGS` in `scenes/characters/duelist_rig.gd`) through two-bone IK, so the edge crosses the space in front of the body while hits can land.

### Look and sound

`scenes/fx/` holds the presentation: a post-process that resamples the frame on a coarse pixel grid, posterizes it through a 4x4 Bayer dither and adds animated grain, and a shared dense dusk fog for both areas. Gradients in the fog and sky break into dithered bands.

Every sound and music stem is synthesized by `tools/audio/generate_audio.py`. The Ash Court plays a D minor dungeon synth score and the Outer Ruins a D Dorian medieval tune on drone, lute and recorder. Each area has three sample-aligned stems that fade with combat intensity and crossfade when you cross the bridge. To regenerate the audio:

```sh
pip install numpy scipy soundfile
python3 tools/audio/generate_audio.py
```

After importing the project, run the checks from the project folder.

```sh
godot --headless --path . --script res://tests/stage_one.gd
godot --headless --path . --script res://tests/duel.gd
godot --headless --path . --script res://tests/expedition.gd
godot --headless --path . --script res://tests/weapons.gd
```

The courtyard, duelist and skeleton meshes, weapons, sounds and music were created for this project. [Motion sources](docs/motion-sources.md) describes the retargeted Quaternius clips. [Third-party assets](THIRD_PARTY.md) lists the Kenney models and their license. Development skills and their license are in `.agents/skills/`.

The project uses the Compatibility renderer to support early browser testing for a possible itch.io release.
