# Performance

Target: 60 fps on a base M1 and on a GTX 1080 Ti, with quality settings allowed to give way.
The project renders with the Compatibility renderer (OpenGL).

## Measuring

`tools/bench/bench.tscn` plays the expedition without input: the court is won, the forest
streams in behind the gate, the hero walks through the eclipse, along the forest road, over the
crossing and through the belfry. Vsync is off, so the numbers show how long a frame really
takes. The hero cannot die; foes fight as usual.

- Editor: open `tools/bench/bench.tscn`, Run Current Scene.
- Command line: `<godot> --path <project> res://tools/bench/bench.tscn`
  (add `-- --no-warmup` to compare without the shader warm-up).

The report (console and `user://bench.txt`) gives per stretch: frames, average, p50/p95/p99,
max, frames over 20 and 33 ms, the renderer's CPU and GPU time, draw calls and shader programs
compiled during the stretch, then the slowest frames with what was marked in them
(`Perf.mark`, see `scenes/debug/perf_marks.gd`). Hitches in normal play still go to
`user://hitches.log` (F4 shows the overlay).

First-run shader compilation only shows with empty caches: delete `user://shader_cache`
(macOS: `~/Library/Application Support/Godot/app_userdata/souls/shader_cache`) and, if possible,
the driver's own shader cache.

## What keeps frames even

| Area | What happens |
| --- | --- |
| Gate opening | The ruins join one foe per frame; dressing, navigation (on a worker thread) and lighting follow over the next frames; crackle on the torches is added a few voices per frame. The forest starts streaming a frame later. |
| Forest streaming | Already sliced at about 3 ms a frame; the zones' foes are no longer spawned twice at the end; the forest's foe scenes and its score are read from disk on worker threads when the gate opens. |
| Portal | Under the opaque veil the hand-over is spread over frames: environment and moon, music, weather, then the shader warm-up; the ruins are freed (the way back is closed). |
| Zones | Built on approach (crossing within 100 m, belfry within 110 m) and freed when far behind (150 / 160 m), never while the player is inside or while the belfry is the place to rise. Building is paced: the layout hands back the frame after about 2.5 ms, detail geometry is built on a worker thread and attached one region per frame, navigation bakes on a worker thread and is settled onto the floor a slice at a time, foes spawn one per frame. |

## Shader warm-up

OpenGL compiles a shader the first time something drawn with it reaches the screen; Godot keeps
compiled programs in `user://shader_cache`, and drivers keep their own caches, so this bites on a
first run (new machine, new driver, new build). `scenes/fx/shader_warmup.gd` gathers one of
everything that can need its own shader (material and vertex layout, multimesh layouts,
particles) plus one stand-in of each foe, and draws them for three frames in a 64 x 64
SubViewport that shares the world, on a render layer the player's camera does not see: by a
fire and in the dark, since lights change the shader variant. It runs under the portal's veil
for the forest and both zones (zones contribute small samples, kept alive so their shaders are
not freed before the zones are built), and at the level's start for the ruins.

## Measured (this container, 4 vCPU, software OpenGL; relative numbers only)

CPU only (headless), before -> after, worst frame per stretch:

| Stretch | Before | After |
| --- | --- | --- |
| Gate opening and streaming | 63 ms (ruins 54 ms in one frame) and 53 ms (end of the forest's build) | about 20 ms |
| Portal | 40 ms | 36-55 ms, all under the opaque veil |
| Forest / crossing / belfry | 22-29 ms | 18-20 ms, an occasional 22-40 ms frame on entering the crossing (not traced yet) |

With rendering and both caches empty (a first run), the forest stretch's p99 went from 487 ms to
337 ms with the warm-up (software rendering: about 300 ms a frame, so only the spikes above that
matter). The gate opening still stalls on a first run (several seconds in software rendering)
as the ruins' foes first appear; the warm-up at the start has not removed it yet.

## Not done

- Baking procedural content into files. Streaming the forest takes about 255 frames (4 s) while
  the player fights through the ruins and no longer causes hitches, so baking would mainly make
  it faster, which nobody sees yet. It becomes worth it with bigger areas or loading screens to
  shorten; until then it would add the risk of baked files falling out of step with the
  generators.
- Quality presets (render scale, shadows, particle density, draw distance).
- Lower update rates for far foes (AI, animation).
