# Souls

Souls is an early-stage 3D soulslike prototype built in Godot 4.7.2 with GDScript. The visual direction draws on low-poly PS1 and Nintendo 64 games. The combat design focuses on responsive movement, readable enemy attacks, and boss fights that reward learning their patterns.

## First playable milestone

One test arena, one weapon, and one boss. The prototype will test lock-on camera behavior, dodge input buffering, stamina, and attack timing. The first boss will use distinct windups and punish windows so players can learn when to dodge, reposition, or counterattack.

Souls 0.5 opens in the Ash Court against the Ash Gatekeeper. He reads your distance and his phase, never repeats a move back to back and mixes cuts, a three-blow string, a delayed overhead that punishes early rolls, a charging thrust after a backstep and a leaping slam with a landing shockwave; below half health he adds a full spin and a fan of ash bolts. Defeat him, approach the gate and press **E** or **A**: the seal burns away and a short bridge leads straight into the Outer Ruins. Nothing loads; the ruins stream in during the boss fight. Eight foes of six kinds hold the road to the shrine: the spearman, shieldbearer and cinder thrower, slow ash husks, a fast cinder crawler that pounces and backs off, a bone sentry, and the ashbound brute, whose slam shakes the ground. If you fall in the ruins, **T** or **Menu** raises you at their entrance with the foes restored, and the Gatekeeper stays defeated.

The hero is an armoured skeleton carrying six very different weapons. Hits come from the weapon itself: the striking edge is swept between physics steps and tested against each body, so a short blade misses where a greatsword connects. Movement has weight: rolls burst, carry and land in a crouch, a reversal at a run skids before pushing off, falls land hard, and foes accelerate, brake and turn at their own rates.

Foes fight as a group: only a few attack at once while the rest circle at a distance, strafing and keeping clear of each other. They see in a cone (a quiet approach from behind goes unnoticed), hear a sprint, call nearby allies, track you through the early part of a windup, roll away from swings, punish openings, back off after taking hits and search where they last saw you before returning to their posts.

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

Press **Esc** to release the mouse cursor. Left-click the game window to capture it again. **F3** toggles the retro presentation. **F4** shows frame timing; any hitch is also written with the gameplay events of that frame to `user://hitches.log` (on macOS: `~/Library/Application Support/Godot/app_userdata/souls/hitches.log`). Physics interpolation is on, so movement stays smooth on 120 Hz displays.

Heavy attacks deal more posture damage. A frontal parry interrupts a melee attack and makes the first follow-up strike hit harder. The shieldbearer opens up during an attack. Cover can intercept the thrower's visible bolts. Press **F2** in the Ash Court to inspect attack arcs, phases, and queued input.

| Weapon | Mass | Speed and damage | Twist |
| --- | --- | --- | --- |
| Ashen Longsword | 3 kg | Balanced, slash | Heavy breaks posture |
| Ashen Tachi | 1.9 kg | Fast and long, slash | Heavy is a dashing draw cut |
| Gatebreaker Greatsword | 9 kg | Slow, huge, slash | Hyper armour; hold heavy to charge up to +60 % |
| Bone Shiv | 0.8 kg | Fastest, short, pierce | Three-cut flurry, lunging pounce, x2.5 to the back |
| Bellbreaker | 11 kg | Slowest, impact | Crushes guards; heavy slams a shockwave |
| Ember Staff | 2 kg | Magic | Spends focus on homing ember bolts and an ash nova; bonks without focus |

Foes take more or less damage from slash, pierce, impact and magic depending on their armour. Hold the heavy button to charge weapons that allow it; the blue bar is focus and refills slowly.

Weapons live in `scenes/combat/weapons/` as `SoulsWeapon` resources: blade length, grip, mass and the light chain and heavy attack. Attack resources expose timing, damage, posture, AI engagement distance, impact weight and the chain and roll-cancel points in the Inspector. Sword arms follow authored blade paths (`SWINGS` in `scenes/characters/duelist_rig.gd`) through two-bone IK, so the edge crosses the space in front of the body while hits can land.

### Look and sound

`scenes/fx/` holds the presentation: a post-process that resamples the frame on a coarse pixel grid, posterizes it through a 4x4 Bayer dither and adds animated grain, then grades it as comic neon noir after The Wolf Among Us, with ink lines on sharp edges, darks crushed toward blue-black and warmed highlights. A cold blue moon throws hard shadows, lanterns make flickering warm pools, magenta neon rims silhouettes against a magenta horizon, and lit materials use toon shading. Gradients in the fog and sky break into dithered bands.

Weather is one shared model: gusting wind drives leaves, ash, the hero's cape and the occasional tumbling branch; rain falls slanted by the wind, wets the stone until lanterns glint off it, and storms bring lightning and thunder. The court is windy with passing drizzle, the ruins are stormy.

Every sound and music stem is synthesized by `tools/audio/generate_audio.py`. The Ash Court explores to a D minor dungeon synth score and the Outer Ruins to a D Dorian medieval tune on drone, lute and recorder. When a foe notices you a stinger hits and the area's own combat theme starts: the Gatekeeper's D minor theme gains a choir in his second phase, and the ruins fight is a driving dungeon synth arrangement. Scores crossfade when you cross the bridge. To regenerate the audio:

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
godot --headless --path . --script res://tests/foes.gd
godot --headless --path . --script res://tests/music.gd
godot --headless --path . --script res://tests/ai.gd
godot --headless --path . --script res://tests/weather.gd
```

The courtyard, duelist and skeleton meshes, weapons, sounds and music were created for this project. [Motion sources](docs/motion-sources.md) describes the retargeted Quaternius clips. [Third-party assets](THIRD_PARTY.md) lists the Kenney models and their license. Development skills and their license are in `.agents/skills/`.

The project uses the Compatibility renderer to support early browser testing for a possible itch.io release.
