# Forge Engine

A Vulkan-powered 3D game engine built with [SageLang](../sagelang). Features a UE5-inspired visual editor with floating windows, menu bar, TrueType font rendering, real-time PBR lighting, quaternion math, and 86+ engine modules.

For the complete engine guide, see **[GUIDE.md](GUIDE.md)**.

## Quick Start

```bash
# Launch the editor
./editor.sh

# Run a game demo
./run.sh examples/demo_world.sage

# Run tests (47 suites, 1299 checks)
./tests/run_all.sh
```

## Editor

The Forge Editor is a visual scene editor inspired by Unreal Engine 5. Build scenes by placing and transforming objects, edit properties inline, then generate a complete SageLang game script.

### Features

- **Floating windows** — Draggable, resizable Outliner, Details, and Content Browser panels with snap-to-edge docking
- **Menu bar** — File, Edit, Window, Tools, Help menus with dropdown actions
- **Editable properties** — Click transform values to type new numbers with blinking cursor
- **Scrollable panels** — Mouse wheel scrolls Outliner, Details, and Content Browser
- **Undo/Redo** — CTRL+Z / CTRL+Y for property edits with full command history
- **Modal dialogs** — Quit confirmation and other modal prompts
- **Context menus** — Right-click in viewport for quick actions
- **Play-in-Editor** — Press ENTER to generate and test your game
- **Viewport overlay** — Perspective/Lit/Show indicator bar
- **Keyboard shortcuts** — Press F1 to see all shortcuts

### Controls

Press **F1** in the editor to see the full shortcut list, or:

| Input | Action |
|-------|--------|
| RMB + Drag | Orbit camera |
| MMB + Drag | Pan camera |
| Scroll Wheel | Zoom / scroll panels |
| Left Click | Select entity (viewport raycast or outliner) |
| Right Click (viewport) | Context menu |
| 1 / 2 / 3 | Translate / Rotate / Scale gizmo |
| R / F / E | Place Cube / Sphere / Model |
| D / Q | Delete / Duplicate selected |
| TAB | Toggle physics on selected |
| ENTER | Play-in-Editor (generate + run) |
| Arrow Keys | Nudge selected entity |
| CTRL+S / CTRL+N / CTRL+O | Save / New / Open scene |
| CTRL+Z / CTRL+Y | Undo / Redo |
| CTRL+Q | Quit (with confirmation) |
| F1 | Toggle shortcuts overlay |

### Code Generation

Press **ENTER** or use File > Export Game to generate `assets/generated_game.sage` — a complete, runnable game with all entities, physics, HUD, FPS controls, and game loop.

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
├── editor.sage              # Visual editor (1500+ lines)
├── editor.sh                # Editor launcher
├── lib/                     # Engine modules (86 files, 15,675 lines)
├── shaders/                 # GLSL + SPIR-V (16 shader pairs)
├── examples/                # 8 demo programs (2,557 lines)
├── tests/                   # 47 suites, 1,299 checks
├── assets/                  # Fonts, models, scenes, generated code
└── build/                   # Distribution output
```

**Total codebase:** 145 .sage files, 25,000+ lines of SageLang + 496 lines of GLSL

## Engine Systems

### Core
`engine` · `ecs` · `events` · `game_loop` · `components` · `engine_math` · `input`

### Math
`math3d` — vec2/3/4, mat4 (full suite), **quaternions** (slerp, euler conversion, rotation), mat4_inverse (Cramer's rule)

### Rendering
`renderer` · `render_system` · `lighting` (16 dynamic lights, fog) · `sky` (procedural, presets) · `pbr_material` (Cook-Torrance BRDF) · `textures` (PNG/JPG) · `shadow_map` (PCF) · `frustum` (culling) · `editor_grid` · `post_fx` (vignette, color grading) · `postprocess` (bloom, tone mapping)

### Physics
`collision` (AABB/sphere/ray/capsule) · `physics` (rigidbody, gravity, restitution) · `spatial_grid` (broadphase)

### Gameplay
`player_controller` (FPS) · `gameplay` (health, timers, state machines, scoring)

### Content
`asset_manager` · `scene_serial` (JSON save/load) · `asset_import` (glTF 2.0 via cgltf) · `audio` (OpenAL FFI) · `hot_reload` · `codegen` (full game script generation)

### Animation & AI
`tween` (18 easings) · `animation` (skeletal, blend trees, state machine) · `navigation` (A* pathfinding) · `behavior_tree`

### UI
`ui_core` (widget hierarchy, anchoring, hit testing) · `ui_renderer` (batched quads) · `ui_widgets` (buttons, sliders, checkboxes, dropdowns, **text input fields**, number fields, tree views, scroll panels) · `ui_window` (floating windows, menus, **modal dialogs**, snap-to-edge) · `font` (TrueType via stb_truetype) · `hud` · `menu`

### World
`terrain` (heightmap + noise) · `water` (animated waves) · `foliage` (scatter) · `day_night` (sun cycle)

### VFX
`particles` (CPU pool) · `vfx_presets` (fire/smoke/sparks/rain/magic) · `particle_renderer` · `post_fx`

### Networking
`net_protocol` · `net_server` · `net_client` · `net_replication` · `lobby`

### Editor
`undo_redo` (command pattern, 100 levels) · `inspector` · `gizmo` (translate/rotate/scale) · `asset_browser` · `scene_editor` (multi-select, raycast picking) · `editor_viewport` · `editor_layout` · `codegen` · `editor_grid`

## Demos

```bash
./run.sh examples/demo.sage              # Basic spinning cubes
./run.sh examples/demo_lighting.sage     # Dynamic lighting + sky
./run.sh examples/demo_physics.sage      # Physics + raycasting
./run.sh examples/demo_assets.sage       # Asset pipeline + save/load
./run.sh examples/demo_ai.sage           # AI pathfinding + behavior
./run.sh examples/demo_ui.sage           # HUD + menus
./run.sh examples/demo_world.sage        # Terrain + water + day/night
./run.sh examples/demo_particles.sage    # Particles + VFX
```

## Testing

```bash
./tests/run_all.sh            # 47 suites, 1,299 checks
./run.sh tests/test_ecs.sage  # Individual suite
```

## SageLang Enhancements

Forge Engine includes improvements to the SageLang interpreter and GPU module:

- **Text input** — GLFW char callback for keyboard text entry in editor
- **`str()` for arrays** — arrays display as `[1, 2, 3]` instead of nil
- **Better runtime errors** — shows function name and value type on call failures
- **Native performance** — `build_quad_verts`, `array_extend`, `build_line_quads` in C
- **Font rendering** — stb_truetype integration with atlas-based text pipeline
- **glTF import** — cgltf integration for model/material/animation loading
- **Extended key constants** — KEY_Z, KEY_Y, KEY_BACKSPACE, KEY_DELETE, KEY_F1, etc.

## Known Issues

- Audio requires OpenAL; gracefully degrades if absent
- No MSAA yet (planned for next release)
- Deferred rendering pipeline and SSAO are stub implementations
- Networking is TCP-only (UDP planned)

## License

Same as [SageLang](../sagelang).
