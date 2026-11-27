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
