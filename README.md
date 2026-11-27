# Souls

Souls is an early-stage 3D soulslike prototype built in Godot 4.7.2 with GDScript. The visual direction draws on low-poly PS1 and Nintendo 64 games. The combat design focuses on responsive movement, readable enemy attacks, and boss fights that reward learning their patterns.

## First playable milestone

One test arena, one weapon, and one boss. The prototype will test lock-on camera behavior, dodge input buffering, stamina, and attack timing. The first boss will use distinct windups and punish windows so players can learn when to dodge, reposition, or counterattack.

Souls 0.3 opens in the Ash Court against the Ash Gatekeeper. Read his sweep and thrust in the first phase. Below half health he finishes his current move and adds a follow-up overhead strike. Defeat him, then approach the gate and press **E** or **A**. The Outer Ruins start with restored health and stamina. The spearman, shieldbearer and cinder thrower guard the road to the shrine.

Use **T** or **Menu** to retry the current area. The controller test arena and the shorter 0.2 training duel are available in `scenes/arena/` and `scenes/duel/`.

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
| Jump | F | X |
| Interact with the gate | E | A |
| Retry current area | T | Menu |

Press **Esc** to release the mouse cursor. Left-click the game window to capture it again.

Heavy attacks deal more posture damage. A frontal parry interrupts a melee attack and makes the first follow-up strike hit harder. The shieldbearer opens up during an attack. Cover can intercept the thrower's visible bolts. Press **F2** in the Ash Court to inspect attack arcs, phases, and queued input. Attack resources in `scenes/duel/combat/` and `scenes/expedition/enemies/` expose timing, damage, reach, and stamina cost in the Inspector.

After importing the project, run the checks from the project folder.

```sh
godot --headless --path . --script res://tests/stage_one.gd
godot --headless --path . --script res://tests/duel.gd
godot --headless --path . --script res://tests/expedition.gd
```

The courtyard, duelist meshes, and combat sounds were created for this project. [Motion sources](docs/motion-sources.md) describes the retargeted Quaternius clips. [Third-party assets](THIRD_PARTY.md) lists the Kenney models and their license. Development skills and their license are in `.agents/skills/`.

The project uses the Compatibility renderer to support early browser testing for a possible itch.io release.
