# Souls

Souls is an early-stage 3D soulslike prototype built in Godot 4.7.2 with GDScript. The visual direction draws on low-poly PS1 and Nintendo 64 games. The combat design focuses on responsive movement, readable enemy attacks, and boss fights that reward learning their patterns.

## First playable milestone

One test arena, one weapon, and one boss. The prototype will test lock-on camera behavior, dodge input buffering, stamina, and attack timing. The first boss will use distinct windups and punish windows so players can learn when to dodge, reposition, or counterattack.

The current prototype opens the Ash Court for a duel against the Gate Watcher. Close the distance, read his sweep or thrust, and counter after a dodge or parry. The shorter controller test arena is still available in the editor at `scenes/arena/controller_arena.tscn`.

## Run locally

1. Install the standard Godot 4.7.2 editor.
2. Keep the complete project in one folder. If you downloaded the ZIP, extract it and use the `Souls` folder inside it.
3. In the Godot Project Manager, choose **Import** and select `project.godot` inside that folder, next to `scenes/`. Godot treats the folder containing `project.godot` as the project root and scans it for assets.
4. Press **F5** to open the duel. Its scene is `scenes/duel/courtyard_duel.tscn`.

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
| Retry duel | T | Menu |

Press **Esc** to release the mouse cursor. Left-click the game window to capture it again.

Heavy attacks deal more posture damage. A frontal parry interrupts the Watcher's attack and makes the first follow-up strike hit harder. Press **F2** to inspect attack arcs, phases, and queued input. The four attack resources in `scenes/duel/combat/` expose timing, damage, reach, and stamina cost in the Inspector.

After importing the project, run both checks from the project folder.

```sh
godot --headless --path . --script res://tests/stage_one.gd
godot --headless --path . --script res://tests/duel.gd
```

The courtyard GLB, duelist rigs, and combat sound effects were created for this project. Development skills and their license are in `.agents/skills/`.

The project uses the Compatibility renderer to support early browser testing for a possible itch.io release.
