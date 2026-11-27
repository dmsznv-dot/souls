# Duelist motion sources

Souls 0.3 uses six animations from **Quaternius Universal Animation Library, Standard**, on its original duelist skeleton. The publisher releases the pack under CC0 1.0 Universal. The downloaded in-place GLB contained 43 named animations. The bundled Godot resource contains rotations and centered pelvis offsets for the six selected clips. [Publisher](https://quaternius.com/packs/universalanimationlibrary.html) · [Publisher’s download page](https://quaternius.itch.io/universal-animation-library) · [License](https://creativecommons.org/publicdomain/zero/1.0/)

| Source clip | Game use |
| --- | --- |
| Idle_Loop | Breathing, head position and standing weight shifts |
| Walk_Loop | Low-speed steps, backsteps and the base for lateral footwork |
| Jog_Fwd_Loop | Full-speed stride blended by actual movement velocity |
| Jump_Start, Jump_Loop, Jump_Land | Crouch and extension, airborne silhouette, and landing compression |

The publisher pages identified the pack and license. The raw GLB was accessible through the Blood League Kickoff public repository. Its asset-specific license file credits Quaternius and reproduces the CC0 dedication. The downloaded GLB had SHA-256 `4c748767741a3e495d89667b9a218b690ba9810b9517a12e960780e3ca72c4e9`. [GLB mirror](https://raw.githubusercontent.com/Seyamalam/blood-league-kickoff/main/public/assets/vendor/quaternius/universal-animation-library.glb) · [Asset license](https://raw.githubusercontent.com/Seyamalam/blood-league-kickoff/main/public/assets/vendor/quaternius/LICENSE-ANIMATIONS.txt)

Godot 4.7.2 sampled the source poses at 24 Hz. The duelist faces −Z. Retargeting turned the source 180 degrees around Y, used shoulder-to-elbow, elbow-to-hand, thigh-to-knee and knee-to-ankle directions, and transferred torso, head and ankle rotations relative to the bind pose. The resulting local joint rotations and limited hip offsets live in `assets/animations/quaternius_humanoid.res`. The game adjusts support-foot height for its shorter legs, blends the right arm toward its weapon stance, and adds lateral steps and cape movement. Physics controls the character root throughout.

The Standard library also includes `Roll`, `Sword_Attack` and `Sword_Idle`. Souls uses its own tuck, guard, parry, sword and spear attacks, overhand throw, stagger, collapse and boss challenge. These clips use the campaign’s anticipation, contact and recovery timing. All armor, weapons, shields and character meshes are original project geometry.

Two other sources informed selection. Quaternius’s CC0 **RobotExpressive** GLB was downloaded and inspected, and contains idle, walking, running, jumping, punching and death. GDQuest’s **Mannequiny** publishes its humanoid rig and walk-to-run blending under CC BY 4.0 for the art. Neither contributes data to the shipped resource. [RobotExpressive and asset license](https://github.com/mrdoob/three.js/tree/r181/examples/models/gltf/RobotExpressive) · [Mannequiny releases](https://github.com/gdquest-demos/godot-3d-mannequin/releases)

## Additional clips (Souls 0.5)

`assets/animations/quaternius_extra.res` holds 22 more clips retargeted by `tools/animation/retarget_quaternius.gd` from two Quaternius packs, both CC0 1.0 Universal:

- **Universal Animation Library, Standard** (the GLB above): Roll, Sprint_Loop, Crouch_Fwd_Loop, Crouch_Idle_Loop, Hit_Chest, Hit_Head, Death01, Spell_Simple_Shoot, Punch_Cross, Punch_Jab.
- **Universal Animation Library 2, Standard**: Zombie_Idle_Loop, Zombie_Walk_Fwd_Loop, Zombie_Scratch, Hit_Knockback, Melee_Hook, Slide_Start, Slide_Loop, Slide_Exit, Sword_Dash_RM, Shield_Dash_RM, OverhandThrow, NinjaJump_Land. Downloaded from [OpenGameArt](https://opengameart.org/content/universal-animation-library-2) (`universal_animation_library_2standard.zip`, SHA-256 `ec0e40d6d78fe9aaad59e322f40865a8675c22f0745e291622e54520391a9217`); the archive's License.txt states CC0 1.0. [Publisher](https://quaternius.com/packs/universalanimationlibrary2.html)

The tool turns the source 180 degrees around Y. Each limb keeps its source rotation measured from a reference that points the rig bone along the source bind direction, so swing and twist transfer while bone lengths differ; pelvis, chest, head and feet transfer rotation relative to the T-pose bind. Horizontal pelvis travel is removed because physics moves the body, and height changes are scaled by the leg-length ratio. Clips keep the normalized one-second layout and store their source length as metadata.

To rebuild, pass both GLBs after `--`:

```sh
godot --headless --path . --script res://tools/animation/retarget_quaternius.gd -- UAL1.glb UAL2_Standard.glb
```

The hero rolls with the mocap roll, sprints with the sprint loop, flinches with the hit reactions and dies with Death01. Husks walk and claw with the zombie clips, the cinder crawler moves with the crouch and sprint loops, and the brute punches with Melee_Hook and Punch_Cross. Sword arms still follow the project's own blade paths through IK.
