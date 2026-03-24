# Forge Engine

A Vulkan-powered 3D game engine built with [SageLang](../sagelang). Features a visual editor with floating windows, TrueType font rendering, PBR lighting, quaternion math, 21 GLSL shaders, and 86+ engine modules spanning rendering, physics, animation, AI, networking, and content pipelines.

For the complete engine guide, see **[GUIDE.md](GUIDE.md)**.

## Quick Start

```bash
# Build SageLang (if not already built)
cd ../sagelang && ./build.sh --skip-tests && cd ../3DEngine

# Launch the editor
./editor.sh

# Run a game demo
./run.sh examples/demo_world.sage

# Run tests (47 suites, 1,343 checks)
./tests/run_all.sh
```

## Editor

The Forge Editor is a visual scene editor for building 3D games. Place objects, transform them, apply materials, configure physics, then generate a complete SageLang game script.

### Features

- **Floating windows** — Draggable, resizable Outliner, Details, and Content Browser panels with snap-to-edge docking
- **Menu system** — File, Edit, Window, Tools, Help dropdown menus + right-click context menu
- **Editable properties** — Click transform values in Details panel to type new numbers (with blinking cursor, undo support)
- **Scrollable panels** — Mouse wheel scrolls all floating window content
- **Material presets** — Apply Metal, Wood, Glass, Gold materials from Tools menu
- **Prefab system** — Save entities as reusable .prefab.json templates
- **Undo/Redo** — CTRL+Z / CTRL+Y with full command history (100 levels)
- **Modal dialogs** — Quit confirmation, About dialog
- **Play-in-Editor** — Press ENTER to generate and run your game
- **Save Screenshot** — Capture viewport to PNG from File menu
- **Compile Native** — Generate LLVM-compiled standalone executables (~10x faster)
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

Press **ENTER** or use File > Export Game to generate `assets/generated_game.sage` — a complete, runnable game with renderer, physics, HUD, FPS controls, and game loop.

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
├── editor.sage              # Visual editor (~1600 lines)
├── editor.sh                # Editor launcher
├── lib/                     # Engine modules (86 files, ~16,000 lines)
├── shaders/                 # 21 GLSL shader pairs + SPIR-V
├── examples/                # 8 demo programs (2,557 lines)
├── tests/                   # 47 suites, 1,343 checks
├── assets/                  # Fonts, models, scenes, prefabs
│   └── prefabs/             # Saved entity templates
└── build/                   # Distribution output
```

**Total codebase:** ~27,000 lines of SageLang + ~800 lines of GLSL

## Engine Systems

### Core
`engine` (**env var config**: FORGE_WIDTH/HEIGHT/FULLSCREEN/VSYNC/DEBUG) · `ecs` (dict-based, queries, systems, tags) · `events` · `game_loop` (**coroutine system** via generators) · `components` (Transform, Name, Camera, Light, Material, Audio, TriggerVolume) · `engine_math` · `input`

### Math
`math3d` — vec2/3/4, mat4 (multiply, translate, scale, rotate, perspective, look_at, ortho, inverse), quaternions (mul, slerp, from_euler, to_matrix, rotate_vec3)

### Rendering
`renderer` (Vulkan swapchain, frame sync, **pipeline cache**, **secondary command buffers**) · `render_system` (**indirect draw**, **compute dispatch**, **anisotropic samplers**, **pipeline barriers**) · `lighting` (16 lights, fog, UBO) · `sky` (procedural presets, **cubemap skybox**) · `pbr_material` (Cook-Torrance BRDF) · `textures` · `shadow_map` (depth pass, PCF) · `deferred` (G-buffer MRT, **G-buffer pipeline builder**) · `frustum` (culling) · `lod` (5 distance levels) · `taa` (temporal anti-aliasing, **jitter projection**) · `frame_graph` (pass dependencies, **GPU barrier integration**) · `editor_grid` · `post_fx` (vignette, color grading, fade) · `postprocess` (bloom, tone mapping, fullscreen passes, **offscreen targets**)

### Physics
`collision` (AABB/sphere/ray/capsule, collision callbacks/events) · `physics` (rigidbody, gravity, restitution, fixed/distance/hinge constraints, constraint solver) · `spatial_grid` (broadphase, **octree** for large scenes)

### Gameplay
`player_controller` (FPS, ground check, step climbing, slope limits) · `gameplay` (health, damage/heal, timers, state machines, spawners, scoring with combos)

### Content
`asset_manager` (caching) · `asset_cache` · `scene_serial` (JSON save/load, prefab save/load) · `asset_import` (glTF 2.0, **async loading queue**, **HTTP download**) · `asset_browser` (search, filter, categories) · `audio` (OpenAL FFI) · `hot_reload` (directory watching) · `codegen` (game script generation, **LLVM native compilation**) · `material` (8 PBR presets) · `mesh` (**device-local uploads**, **struct vertex packing**)

### Animation & AI
`tween` (18 easings) · `animation` (skeletal, keyframes, blend trees, state machine, two-bone IK solver, animation events) · `navigation` (A* pathfinding, steering: seek/flee/arrive/wander/avoid) · `behavior_tree` (action/condition/sequence/selector/inverter/repeater/wait)

### UI
`ui_core` (widget hierarchy, anchoring, hit testing) · `ui_renderer` (batched quads) · `ui_widgets` (buttons, sliders, checkboxes, dropdowns, text input fields, number fields, tree views, scroll panels, section headers) · `ui_window` (floating windows, menus, modal dialogs, snap-to-edge) · `font` (TrueType via stb_truetype) · `hud` · `menu`

### World
`terrain` (heightmap, procedural noise) · `water` (animated waves) · `foliage` (scatter rules) · `day_night` (sun cycle) · `scene` (scene graph, level streaming)

### VFX & Post-Processing
`particles` (CPU pool, emitter shapes) · `vfx_presets` (fire/smoke/sparks/rain/magic) · `particle_renderer` · `post_fx` (vignette, color grading, fade, presets) · `postprocess` (bloom extract/blur/composite, HDR tone mapping, fullscreen pass infrastructure)

### Networking
`net_protocol` (binary messages) · `net_server` (TCP, 16 clients, **SSL/TLS**) · `net_client` (**secure connect**) · `net_replication` · `lobby`

### Editor Tools
`undo_redo` (command pattern, 100 levels) · `inspector` · `gizmo` (translate/rotate/scale) · `asset_browser` · `scene_editor` (multi-select, raycast picking) · `editor_viewport` · `editor_layout` · `codegen` · `editor_grid` · `debug_ui` (overlay, frame stats)

## Shaders

21 shader pairs (GLSL source + compiled SPIR-V):

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
./tests/run_all.sh            # 47 suites, 1,343 individual checks
./run.sh tests/test_ecs.sage  # Run individual suite
```

## SageLang Features Used

Forge Engine leverages these SageLang capabilities:

**Interpreter Enhancements:**
- Text input via GLFW char callback + ring buffer
- `str()` for arrays, better runtime error messages
- Native C functions: `build_quad_verts`, `array_extend`, `build_line_quads`
- stb_truetype font rendering, cgltf model loading
- Extended key constants (KEY_Z/Y/X, BACKSPACE, DELETE, F1, etc.)

**LLVM Backend:**
- Native compilation via `sage --compile` for ~10x speedup
- 100+ GPU runtime functions linked directly via C ABI
- Bytecode VM with 21 GPU hot-path opcodes for game loops

**GPU Module (135 functions):**
- Vulkan rendering pipeline (swapchain, render passes, pipelines, command buffers)
- Compute shader dispatch (`cmd_dispatch`, `cmd_dispatch_indirect`)
- Indirect rendering (`cmd_draw_indirect`, `cmd_draw_indexed_indirect`)
- Secondary command buffers for parallel recording
- Pipeline caching, advanced samplers, cubemaps
- Offscreen targets, MRT render passes, pipeline barriers
- Screenshot capture, device-local memory uploads

**Networking:**
- TCP/UDP sockets, HTTP client (get/post/download), SSL/TLS

## Known Issues

- Menu bar visibility depends on theme contrast (WIP)
- Audio requires OpenAL; gracefully degrades if absent
- No MSAA (pipeline hardcoded to 1x sample — planned)
- Deferred G-buffer fill pass not yet wired (infrastructure and shaders ready)
- Networking is TCP-only (UDP planned)
- Content browser text can overflow on small windows (scroll support added but clipping WIP)

## License

Same as [SageLang](../sagelang).
