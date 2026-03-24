# Forge Engine

A Vulkan-powered 3D game engine built with [SageLang](../sagelang). Features a visual editor with auto-generated SageLang code output, TrueType font rendering, real-time lighting, and 50+ engine modules.

For the complete engine guide, see **[GUIDE.md](GUIDE.md)**.

## Quick Start

```bash
# Launch the editor
./editor.sh

# Run a game demo
./run.sh examples/demo_world.sage

# Build distributable
./build.sh editor.sage -o forge_editor
```

## Editor

The Forge Editor is a visual scene editor in the style of Unreal Engine. Build scenes by placing and transforming objects, then press **5** to auto-generate a complete SageLang game script.

### Controls

**Viewport**
| Input | Action |
|-------|--------|
| Right Mouse + Drag | Orbit camera |
| Middle Mouse + Drag | Pan camera |
| Scroll Wheel | Zoom in/out |
| Left Click (viewport) | Select entity |
| Left Click (outliner) | Select entity from list |

**Scene Editing**
| Key | Action |
|-----|--------|
| R | Place cube |
| F | Place sphere |
| D | Delete selected |
| Q | Duplicate selected |
| Arrow Keys | Nudge selected entity |
| Ctrl + Click (outliner/viewport) | Add/remove from selection |
| ESC | Deselect |

**Gizmo Modes**
| Key | Mode |
|-----|------|
| 1 | Translate |
| 2 | Rotate |
| 3 | Scale |

**File Operations**
| Key | Action |
|-----|--------|
| 4 | Save scene (JSON) |
| Enter | Toggle Play-In-Editor |
| **5** | **Generate SageLang game script** |
| Ctrl+N / Ctrl+O / Ctrl+S | New / Open / Save scene |
| Ctrl+Z / Ctrl+Y | Undo / Redo |
| Ctrl+A | Select all entities |
| Ctrl+Q | Quit editor |

### Content Menu

The **Tools** menu and viewport context menu now include content-browser actions:

- `Browse Assets`
- `Browse Textures`
- `Browse Sprites`
- `Browse Animations`
- `Place Selected Asset`

Use the **Content Browser** panel to filter by type, pick an item, then place it into the scene.

### Code Generation

Press **5** → generates `assets/generated_game.sage` — a complete, runnable game with all entities, renderer setup, player controller, and game loop.

```bash
./run.sh assets/generated_game.sage
```

## Requirements

- [SageLang](../sagelang) with Vulkan GPU module
- Vulkan-capable GPU and drivers
- Linux (tested on Ubuntu/Arch with NVIDIA)

## Architecture

```
forge-engine/
├── editor.sage              # Visual editor
├── editor.sh                # Editor launcher
├── lib/                     # Engine modules (55+)
├── shaders/                 # GLSL + SPIR-V (18 shaders)
├── examples/                # 8 demo programs
├── tests/                   # 47 suites, 1,299 checks
├── assets/                  # Saved scenes + generated code
└── build/                   # Distribution output
```

## Engine Systems

### Core
`engine` · `ecs` · `events` · `game_loop` · `components` · `engine_math` · `input`

### Rendering
`render_system` · `lighting` (16 dynamic lights) · `sky` (procedural) · `pbr_material` (Cook-Torrance) · `textures` (PNG/JPG) · `shadow_map` · `frustum` (culling) · `editor_grid`

### Physics
`collision` (AABB/sphere/ray) · `physics` (rigidbody, gravity) · `spatial_grid` (broadphase)

### Gameplay
`player_controller` (FPS) · `gameplay` (health, timers, state machines, scoring)

### Content
`asset_manager` · `scene_serial` (JSON) · `gltf_import` (glTF 2.0) · `audio` (OpenAL) · `hot_reload`

### Animation & AI
`tween` (18 easings) · `animation` (skeletal) · `navigation` (A* pathfinding) · `behavior_tree`

### UI
`ui_core` · `ui_renderer` · `ui_text` (bitmap font) · `ui_widgets` · `hud` · `menu`

### World
`terrain` (heightmap + noise) · `water` (animated waves) · `foliage` (scatter) · `day_night` (sun cycle)

### VFX
`particles` (CPU pool) · `vfx_presets` (fire/smoke/sparks/rain) · `particle_renderer` · `post_fx`

### Networking
`net_protocol` · `net_server` · `net_client` · `net_replication` · `lobby`

### Editor
`undo_redo` · `inspector` · `gizmo` · `asset_browser` · `scene_editor` · `editor_viewport` · `editor_layout` · `codegen` · `editor_grid`

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

## Writing a Game

```python
from engine import create_engine, on_update, on_render, run
from ecs import spawn, add_component
from components import TransformComponent
from mesh import cube_mesh, upload_mesh

let eng = create_engine("My Game", 1280, 720)
let world = eng["world"]

let cube = upload_mesh(cube_mesh())
let e = spawn(world)
add_component(world, e, "transform", TransformComponent(0.0, 1.0, 0.0))
add_component(world, e, "mesh_id", {"mesh": cube})

proc update(e, dt):
    pass

proc render(e, frame):
    pass

on_update(eng, update)
on_render(eng, render)
run(eng)
```

Or just use the editor and press **5**.

## Testing

```bash
./tests/run_all.sh          # 47 suites, 1,299 checks
./run.sh tests/test_ecs.sage  # Individual suite
```

## Building

```bash
./build.sh editor.sage -o forge_editor

# Output:
# build/dist/forge_editor    (native launcher)
# build/dist/lib/             (84 .sage modules)
# build/dist/shaders/         (18 SPIR-V shaders)
```

## SageLang Patches

Forge Engine includes improvements to the SageLang interpreter:

- **`str()` for arrays** — arrays display as `[1, 2, 3]` instead of nil
- **Better runtime errors** — shows function name and value type on call failures

## Known Issues

- Editor bitmap font is pixel-based (no TTF support yet)
- Audio requires OpenAL; gracefully degrades if absent
- FFI `void` return supports max 1 argument (SageLang limitation)

## License

Same as [SageLang](../sagelang).
