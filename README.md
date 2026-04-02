# Forge Engine

A Vulkan-powered 3D game engine built with [SageLang](../sagelang). Features a project launcher with game templates, a visual editor with floating windows, TrueType font rendering, PBR lighting, quaternion math, a centralized UI theme system, and 90+ engine modules spanning rendering, physics, animation, AI, networking, and content pipelines.

For the complete engine guide, see **[GUIDE.md](GUIDE.md)**. For release numbering rules, see **[VERSIONING.md](VERSIONING.md)**.

## Quick Start

```bash
# Build SageLang (if not already built)
cd ../sagelang && ./build.sh --skip-tests && cd ../3DEngine

# Launch the editor (opens project browser first)
./run.sh editor.sage

# Run a game demo
./run.sh examples/demo_world.sage

# Run tests (50 suites, 1,499 checks)
./tests/run_all.sh

# Build distributable package
./build_dist.sh
```

The engine release version is sourced from the repo-root `VERSION` file and exposed in runtime UI/build paths through `lib/forge_version.sage`.
Forge stays on `0.y.z` while we are still building toward a fully functional Unreal-style engine release; `1.0.0` is intentionally reserved for when the core workflows are truly there.

## Project Browser

When you launch the editor, a **Project Browser** appears first:

- **Left panel** — 7 game templates: FPS, RPG, Top-Down, Voxel, Racing, Survival, Sandbox
- **Right panel** — Create New Project, Open Existing Project, Exit
- **Preview area** — Shows selected template details and included features
- **Keyboard** — Arrow keys to navigate, Enter to create, ESC to exit

## Editor

The Forge Editor is a UE5-inspired visual scene editor for building 3D games. Place objects, transform them, apply materials, configure physics, then generate a complete SageLang game script.

### Features

- **Project launcher** — Template-based project creation with 7 game type presets
- **Floating windows** — Draggable, resizable Outliner, Details, and Content Browser panels with snap-to-edge docking
- **Responsive layout** — Panels reposition automatically when the window is resized
- **Menu system** — File, Edit, Window, Tools, Help dropdown menus + right-click context menu
- **Themed UI** — Centralized dark theme with accent colors, hover/active/disabled button states, borders, shadows, and focus rings
- **Editable properties** — Click transform values in Details panel to type new numbers (with blinking cursor, undo support)
- **Scrollable panels** — Mouse wheel scrolls all floating window content with visible scrollbars
- **Material presets** — Apply Metal, Wood, Glass, Gold materials from Tools menu
- **Imported animation controls** — Preview imported glTF clips in the editor, switch clips, scrub time, toggle looping, tune playback speed on the selected entity, and inspect imported skin/joint counts
- **Prefab system** — Save entities as reusable .prefab.json templates
- **Undo/Redo** — CTRL+Z / CTRL+Y with full command history (100 levels)
- **Modal dialogs** — Quit confirmation, About dialog
- **Play-in-Editor** — Press ENTER to generate and run your game
- **Save Screenshot** — Capture viewport to PNG from File menu
- **Compile Native** — Generate LLVM-compiled standalone executables
- **Keyboard shortcuts** — Press F1 to see all shortcuts

### Controls

| Input | Action |
|-------|--------|
| RMB + Drag | Orbit camera |
| MMB + Drag | Pan camera |
| Scroll Wheel | Zoom / scroll panels |
| Left Click | Select entity (viewport raycast or outliner) |
| Right Click (viewport) | Context menu (Add Cube/Sphere/Light, Delete) |
| 1 / 2 / 3 | Translate / Rotate / Scale gizmo |
| R / F / E | Place Cube / Sphere / Model |
| D / Q | Delete / Duplicate selected |
| TAB | Toggle physics on selected |
| SPACE / SHIFT+SPACE | Play-pause / toggle looping on selected imported animation |
| CTRL+LEFT / CTRL+RIGHT | Previous / next clip on selected imported animation |
| CTRL+UP / CTRL+DOWN | Scrub selected imported animation |
| `-` / `=` | Decrease / increase selected imported animation speed |
| ENTER | Play-in-Editor |
| Arrow Keys | Nudge selected entity |
| CTRL+S / CTRL+N / CTRL+O | Save / New / Open scene |
| CTRL+Z / CTRL+Y | Undo / Redo |
| CTRL+Q | Quit (with confirmation dialog) |
| F1 | Toggle keyboard shortcuts overlay |

### Menu Bar

| Menu | Actions |
|------|---------|
| **File** | New Scene, Open Scene, Save Scene, Save Screenshot, Export Game, Compile Native, Quit |
| **Edit** | Undo, Redo, Delete, Duplicate, Select All |
| **Window** | Show/hide Outliner, Details, Content Browser, Reset Layout |
| **Tools** | Add Cube/Sphere/Physics/Light, Apply Materials (Metal/Wood/Glass/Gold), Save as Prefab, Toggle Physics, Generate Code |
| **Help** | Controls (F1), About |

### Code Generation

Press **ENTER** or use File > Export Game to generate `assets/generated_game.sage` — a complete, runnable game with renderer, physics, HUD, FPS controls, and game loop. Export now preserves authored scene lights, uses the primary scene camera to seed the generated runtime player transform, yaw/pitch, and FOV, and re-imports authored glTF assets at runtime with node hierarchy transforms, transform-animation clip playback, and imported skin/joint palette generation, including clip selection, current time, speed, and looping state. GPU skinned mesh deformation is still the next step on top of that groundwork.

```bash
./run.sh assets/generated_game.sage
```

## Requirements

- [SageLang](../sagelang) with Vulkan GPU module (built with `./build.sh`)
- Vulkan-capable GPU and drivers
- Linux (tested on Ubuntu/Arch with NVIDIA and AMD)

## Architecture

```
forge-engine/
├── editor.sage              # Visual editor (~1,700 lines)
├── run.sh                   # Script runner
├── build_dist.sh            # Distribution builder
├── VERSION                  # Single source of truth for engine version
├── lib/                     # Engine modules (90 files)
│   ├── ui_core.sage         # Centralized theme + widget system
│   ├── ui_widgets.sage      # Advanced widgets (sliders, checkboxes, dropdowns, text fields)
│   ├── ui_window.sage       # Floating windows, menus, modals
│   ├── ui_renderer.sage     # Batched GPU quad rendering
│   ├── forge_version.sage   # Shared engine version + branding helpers
│   ├── launch_screen.sage   # Project browser / template selector
│   ├── hud.sage             # Game HUD (health, crosshair, minimap, score)
│   ├── menu.sage            # Game menus (pause, main, game over)
│   └── ...                  # 80+ more engine modules
├── shaders/                 # GLSL shader pairs + SPIR-V
├── examples/                # 8 demo programs
├── tests/                   # 50 suites, 1,499 checks
├── assets/                  # Fonts, models, scenes, prefabs
│   └── prefabs/             # Saved entity templates
└── build/                   # Distribution output
```

**Total codebase:** ~22,400 lines of SageLang + ~700 lines of GLSL

## Engine Systems

### Core
`ecs` (dict-based, queries, systems, tags) · `events` · `game_loop` (**coroutine system** via generators) · `components` (Transform, Name, Camera, Light, Material, Audio, TriggerVolume) · `engine_math` · `input`

### Math
`math3d` — vec2/3/4, mat4 (multiply, translate, scale, rotate, perspective, look_at, ortho, inverse), quaternions (mul, slerp, from_euler, to_matrix, rotate_vec3)

### Rendering
`renderer` (Vulkan swapchain, frame sync, **pipeline cache**, **secondary command buffers**) · `render_system` (**indirect draw**, **compute dispatch**, **anisotropic samplers**, **pipeline barriers**) · `lighting` (16 lights, fog, UBO) · `sky` (procedural presets, **cubemap skybox**) · `pbr_material` (Cook-Torrance BRDF) · `textures` · `shadow_map` (depth pass, PCF) · `deferred` (G-buffer MRT) · `frustum` (culling) · `lod` (5 distance levels) · `taa` (temporal anti-aliasing) · `frame_graph` (pass dependencies, **GPU barrier integration**) · `editor_grid` · `post_fx` (vignette, color grading, fade) · `postprocess` (bloom, tone mapping, fullscreen passes, **offscreen targets**)

### Physics
`collision` (AABB/sphere/ray/capsule, collision callbacks/events) · `physics` (rigidbody, gravity, restitution, fixed/distance/hinge constraints, constraint solver) · `spatial_grid` (broadphase, **octree** for large scenes)

### Gameplay
`player_controller` (FPS, ground check, step climbing, slope limits) · `gameplay` (health, damage/heal, timers, state machines, spawners, scoring with combos)

### Content
`asset_manager` (caching) · `asset_cache` · `scene_serial` (JSON save/load, prefab save/load, **imported asset references**) · `asset_import` (glTF 2.0, **async loading queue**, **HTTP download**, imported material metadata + textures, **node hierarchy draws**, **transform-animation clip sampling**, **skin/joint palette generation**, **clip/state helpers**) · `asset_browser` (search, filter, categories) · `audio` (OpenAL FFI) · `hot_reload` (directory watching) · `codegen` (game script generation, **scene light/camera export**, **runtime glTF re-import**, **hierarchical imported draws**, **imported transform-animation playback**, **imported skin/joint palette parity**, **animation state export parity**, **LLVM native compilation**) · `material` (8 PBR presets) · `mesh` (**device-local uploads**, **struct vertex packing**)

### Animation & AI
`tween` (18 easings) · `animation` (skeletal, keyframes, blend trees, state machine, two-bone IK solver, animation events) · `navigation` (A* pathfinding, steering: seek/flee/arrive/wander/avoid) · `behavior_tree` (action/condition/sequence/selector/inverter/repeater/wait)

### UI Framework
`ui_core` (**centralized theme system** with 40+ named colors, spacing constants, font sizing, border/shadow helpers, hover/active/disabled/pressed widget states, focus rings) · `ui_renderer` (batched quads) · `ui_widgets` (buttons, sliders, checkboxes, dropdowns, text input fields, number fields, tree views, scroll panels, section headers, **visible scrollbars**, **per-widget quad collection**) · `ui_window` (floating windows, context menus, modal dialogs, snap-to-edge) · `font` (TrueType via stb_truetype) · `launch_screen` (project browser with templates) · `hud` (health bar with 4-stage color transition, gapped crosshair, themed minimap, score display) · `menu` (themed pause/main/game-over menus with visual hierarchy, button styles, fade animations) · `inspector` (entity property inspector with accent bars, color-coded booleans)

### World
`terrain` (heightmap, procedural noise) · `water` (animated waves) · `foliage` (scatter rules) · `day_night` (sun cycle) · `scene` (scene graph, level streaming)

### VFX & Post-Processing
`particles` (CPU pool, emitter shapes) · `vfx_presets` (fire/smoke/sparks/rain/magic) · `particle_renderer` · `post_fx` (vignette, color grading, fade, presets) · `postprocess` (bloom extract/blur/composite, HDR tone mapping, fullscreen pass infrastructure)

### Networking
`net_protocol` (binary messages) · `net_server` (TCP, 16 clients, **SSL/TLS**) · `net_client` (**secure connect**) · `net_replication` · `lobby`

### Editor Tools
`undo_redo` (command pattern, 100 levels) · `inspector` · `gizmo` (translate/rotate/scale) · `asset_browser` · `scene_editor` (multi-select, raycast picking) · `editor_viewport` · `editor_layout` · `codegen` · `editor_grid` · `debug_ui` (overlay, frame stats)

## Shaders

| Shader | Purpose |
|--------|---------|
| engine_lit | Blinn-Phong forward lighting (16 lights, spot/point/directional, fog) |
| engine_pbr | Cook-Torrance PBR (metallic-roughness, normal mapping, GGX/Smith/Fresnel) |
| engine_sky | Procedural sky dome with sun disc and glow |
| engine_grid | Infinite editor grid with red X-axis and blue Z-axis |
| engine_shadow_depth | Depth-only shadow map pass |
| engine_bloom_extract | Bright pixel extraction with soft knee threshold |
| engine_bloom_blur | 9-tap separable Gaussian blur |
| engine_tonemap | HDR tone mapping (Reinhard/ACES/Uncharted2) + bloom composite + gamma |
| engine_ssao | Screen-space ambient occlusion (16-sample hemisphere kernel) |
| engine_fullscreen | Vertex-bufferless fullscreen triangle |
| engine_ui | 2D colored quad rendering |
| engine_ui_text | TrueType text rendering with smoothstep anti-aliasing |
| engine_unlit | Flat color rendering (no lighting) |

## Demos

```bash
./run.sh examples/demo.sage              # Basic spinning cubes
./run.sh examples/demo_lighting.sage     # Dynamic lighting + sky
./run.sh examples/demo_physics.sage      # Physics + raycasting
./run.sh examples/demo_assets.sage       # Asset pipeline + save/load
./run.sh examples/demo_ai.sage           # AI pathfinding + behavior trees
./run.sh examples/demo_ui.sage           # HUD + menus
./run.sh examples/demo_world.sage        # Terrain + water + day/night
./run.sh examples/demo_particles.sage    # Particles + VFX
```

## Testing

```bash
./tests/run_all.sh            # 50 suites, 1,499 individual checks
./run.sh tests/test_ecs.sage  # Run individual suite
```

## Building for Distribution

```bash
# Build a self-contained distributable package
./build_dist.sh

# Output: build/dist/ (3.9MB extracted)
# Contains: sage runtime + 108 .sage modules + VERSION + shaders + assets

# Run from dist:
cd build/dist && ./forge_engine

# Package for sharing:
tar -czf forge_engine-$(cat VERSION).tar.gz -C build dist
```

The distribution build bundles the SageLang interpreter with all engine source, shaders, assets, and the root `VERSION` file into a portable directory. Native LLVM compilation is not yet supported for multi-module projects (the LLVM backend resolves GPU constants but not cross-module `from X import Y` imports).

## SageLang Features Used

Forge Engine leverages these SageLang capabilities:

**Language Features:**

- `match`/`case`/`default` pattern matching for UI state machines
- `defer` blocks for resource cleanup
- Text input via GLFW char callback + ring buffer
- Native C functions: `build_quad_verts`, `array_extend`, `build_line_quads`
- stb_truetype font rendering, cgltf model loading

**GPU Module (135+ functions):**
- Vulkan rendering pipeline (swapchain, render passes, pipelines, command buffers)
- Compute shader dispatch (`cmd_dispatch`, `cmd_dispatch_indirect`)
- Indirect rendering (`cmd_draw_indirect`, `cmd_draw_indexed_indirect`)
- Secondary command buffers for parallel recording
- Pipeline caching, advanced samplers, cubemaps
- Offscreen targets, MRT render passes, pipeline barriers
- Screenshot capture, device-local memory uploads
- Text input API (`text_input_available`, `text_input_read`)

**Networking:**
- TCP/UDP sockets, HTTP client (get/post/download), SSL/TLS

## Known Issues

- Audio requires OpenAL; gracefully degrades if absent
- No MSAA (pipeline hardcoded to 1x sample)
- Deferred G-buffer fill pass not yet wired (infrastructure and shaders ready)
- Networking is TCP-only (UDP planned)
- LLVM backend does not support multi-module compilation (use interpreter or dist build)
- Pre-existing "Operands must be numbers or strings" warning at startup (non-fatal, does not affect functionality)

## License

Same as [SageLang](../sagelang).
