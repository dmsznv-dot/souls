# Third-party asset credits

## Animation

Six clips from Quaternius Universal Animation Library Standard are retargeted in `assets/animations/quaternius_humanoid.res` under CC0 1.0 Universal. [Motion sources](docs/motion-sources.md) lists the clips, the original and mirrored sources, and the license.

## Environment

Kenney created the models below and released all three packs under Creative Commons CC0 1.0 Universal. The project redistributes the listed GLB files under that dedication. A local copy of its legal text is in [assets/environment/CC0-1.0.txt](assets/environment/CC0-1.0.txt).

| Pack | Files under `assets/environment/` | Use in the game |
| --- | --- | --- |
| [Modular Dungeon Kit](https://kenney.nl/assets/modular-dungeon-kit) | `modular-dungeon-kit/gate.glb`, `modular-dungeon-kit/template-floor.glb`, `modular-dungeon-kit/template-wall-half.glb` | Return gate, memorial terraces and burial walls |
| [Graveyard Kit](https://kenney.nl/assets/graveyard-kit) | `graveyard-kit/iron-fence.glb`, `graveyard-kit/gravestone-decorative.glb`, `graveyard-kit/urn-round.glb` | Cloister railings, weathered memorials and urns |
| [Prototype Kit](https://kenney.nl/assets/prototype-kit) | `prototype-kit/column-rounded-low.glb` | Scale reference retained as a pair of urn supports |

The Modular Dungeon GLBs came from the [aya-assets snapshot](https://github.com/alexan11111/aya-assets/tree/20cbf1b40c4d55f31039cd9c546ebbb4ad99e3d1/kenney/modular-dungeon-kit). Their source filenames have the prefix `modular-dungeon-kit--`. The Graveyard and Prototype files came from the [tge-assets snapshot](https://github.com/Hidencod/tge-assets/tree/e5bd31ec8b339b25d66dd5816a21dd517bd1ae87/packs). The GLBs retain their original embedded colormaps. Godot uses project-authored limestone, aged iron and old bronze materials to match the surrounding ruin.

The ash paving, ruined aqueducts, eclipse shrine, garden walls, horizon and lanterns in `outer_ruins.glb` are original geometry created for this project.

## Audio

All sound effects, ambience and music in `assets/audio/` are original and synthesized from code by `tools/audio/generate_audio.py`. No recorded samples or third-party audio are used.
