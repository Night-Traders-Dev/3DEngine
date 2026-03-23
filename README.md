# Sage Engine

A 3D game engine written in [SageLang](../sagelang), powered by Vulkan. Inspired by Unreal Engine with a focus on user-friendly mechanics and high-quality rendering.

## Quick Start

```bash
# Launch the visual editor
./editor.sh

# Run a demo
./run.sh examples/demo_world.sage

# Run all tests (1,299 checks)
./tests/run_all.sh

# Build distributable binary
./build.sh editor.sage -o sage_editor
```

## Requirements

- **SageLang** — located at `../sagelang` (with Vulkan GPU module)
- **Vulkan SDK** — GPU drivers with Vulkan support
- **GLFW** — windowed mode (bundled with sagelang)
- **glslc** — shader compiler (for modifying shaders)

## Editor

The Sage Engine Editor is an in-engine visual editor similar to Unreal Engine. You build scenes visually and it **auto-generates SageLang code** as output.

```
┌────────────────────────────────────────────────────────┐
│ Sage Editor | Mode: translate                    [Toolbar]
├──────────┬────────────────────────────┬────────────────┤
│ Scene    │                            │ Details        │
│ Hierarchy│     3D Viewport            │                │
│          │                            │ Name: Cube_1   │
│ Ground   │     (orbit/pan/zoom)       │ Pos: 1.0 2.0  │
│ Cube_1   │     (gizmo handles)        │ Rot: 0.0 0.0  │
│ Cube_2   │                            │ Scl: 1.0 1.0  │
│ Sphere_1 │                            │                │
├──────────┴────────────────────────────┤                │
│ Assets | R=Cube F=Sphere | 5=Generate │                │
├───────────────────────────────────────┴────────────────┤
│ Entities: 4 | Mode: translate | Selected: #2  [Status] │
└────────────────────────────────────────────────────────┘
```

### Editor Controls

| Key | Action |
|-----|--------|
| E + Mouse | Orbit viewport camera |
| SHIFT + Mouse | Pan viewport |
| Scroll | Zoom in/out |
| R | Place cube at camera target |
| F | Place sphere at camera target |
| D | Delete selected entity |
| Q | Duplicate selected entity |
| ESC | Deselect |
| 1 / 2 / 3 | Translate / Rotate / Scale gizmo |
| 4 | Save scene to JSON |
| **5** | **Generate SageLang game script** |
| CTRL | Quit editor |

### Code Generation

Press **5** in the editor to generate a complete, runnable `.sage` game script:

```bash
# Generated file appears at:
assets/generated_game.sage

# Run it:
./run.sh assets/generated_game.sage
```

The generated script includes all imports, renderer setup, entity spawning, player controller, and a full game loop.

## Architecture

```
sage_engine/
├── editor.sage              # Visual editor application
├── editor.sh                # Editor launcher
├── run.sh                   # Script runner
├── build.sh                 # Build system (produces distributable binary)
├── lib/                     # Engine modules (50+)
│   ├── engine.sage          # Core engine context and main loop
│   ├── ecs.sage             # Entity-Component System
│   ├── ...                  # (see module list below)
│   └── [stdlib]             # SageLang standard library copies
├── shaders/                 # GLSL shaders + compiled SPIR-V
│   ├── engine_lit.*         # Blinn-Phong lit shader (16 lights, fog)
│   ├── engine_pbr.*         # PBR Cook-Torrance shader (texture maps)
│   ├── engine_sky.*         # Procedural sky with sun
│   ├── engine_ui.*          # 2D screen-space UI quads
│   ├── engine_unlit.*       # Flat color shader
│   └── engine_shadow_depth.*# Shadow map depth pass
├── examples/                # 8 progressive demo programs
├── tests/                   # 47 test suites, 1,299 checks
├── assets/                  # Game assets and saved scenes
└── build/                   # Build output (binary + distribution)
```

## Engine Modules

### Core

| Module | Description |
|--------|-------------|
| `engine.sage` | Engine context, main loop, built-in systems |
| `ecs.sage` | Entity-Component System with queries, tags, systems |
| `events.sage` | Event bus with subscribe/emit/flush |
| `game_loop.sage` | Fixed-timestep loop with interpolation |
| `components.sage` | Transform, Velocity, Camera, Light, Name, Parent |
| `engine_math.sage` | Clamp, lerp, smoothstep, AABB, transforms |
| `input.sage` | Action mapping, axes, mouse, keyboard |

### Rendering

| Module | Description |
|--------|-------------|
| `render_system.sage` | Material registry, lit/unlit draw helpers |
| `lighting.sage` | 16 dynamic lights (point/directional/spot), UBO, fog |
| `sky.sage` | Procedural gradient sky with sun disc and presets |
| `pbr_material.sage` | Cook-Torrance PBR with albedo/normal/metallic-roughness maps |
| `textures.sage` | PNG/JPG texture loading via stb_image, sampler cache |
| `shadow_map.sage` | Depth-only shadow pass, directional light shadows |
| `frustum.sage` | Frustum plane extraction, AABB/sphere culling, draw batching |

### Physics

| Module | Description |
|--------|-------------|
| `collision.sage` | AABB, sphere, ray intersections (6 test types) |
| `physics.sage` | Rigidbody, gravity, integration, ground collision, impulse |
| `spatial_grid.sage` | Uniform hash grid broadphase, collision pairs, radius query |

### Gameplay

| Module | Description |
|--------|-------------|
| `player_controller.sage` | FPS movement, mouse look, jump, sprint, noclip, head bob |
| `gameplay.sage` | Health/damage, timers, state machines, spawners, scoring |

### Content Pipeline

| Module | Description |
|--------|-------------|
| `asset_manager.sage` | Mesh/shader/file caching with stats |
| `scene_serial.sage` | JSON scene save/load with component registries |
| `gltf_import.sage` | glTF 2.0 JSON parser (meshes, materials, textures, nodes) |
| `audio.sage` | OpenAL via FFI, spatial audio, volume channels |
| `hot_reload.sage` | File watcher, change detection, reload callbacks |

### Animation & AI

| Module | Description |
|--------|-------------|
| `tween.sage` | 18 easing functions, property/vec3 tweens, tween manager |
| `animation.sage` | Skeleton, bones, keyframes, clips, blending, procedural walk |
| `navigation.sage` | A* pathfinding on grid, 5 steering behaviors, path follower |
| `behavior_tree.sage` | 7 node types (sequence, selector, inverter, wait...), AI actions |

### UI Framework

| Module | Description |
|--------|-------------|
| `ui_core.sage` | Widget system, anchoring, layout, hit testing |
| `ui_renderer.sage` | GPU batched quad rendering for UI |
| `ui_text.sage` | Bitmap pixel font, text-to-quad rendering |
| `ui_widgets.sage` | Scroll panels, tree views, sliders, checkboxes, dropdowns |
| `hud.sage` | Health bar, crosshair, score display, minimap |
| `menu.sage` | Pause/main/game-over menus with fade transitions |

### World

| Module | Description |
|--------|-------------|
| `terrain.sage` | Heightmap generation (FBM noise), mesh building, height sampling |
| `water.sage` | Animated wave plane with multi-frequency displacement |
| `foliage.sage` | Rule-based scattering with height/slope filtering |
| `day_night.sage` | Sun orbit, sky/ambient/fog animation, time-of-day control |

### VFX

| Module | Description |
|--------|-------------|
| `particles.sage` | CPU particle system with pool, 4 emitter shapes, forces |
| `vfx_presets.sage` | Fire, smoke, sparks, explosion, rain, dust, magic |
| `particle_renderer.sage` | 3D-to-screen projected particle quads |
| `post_fx.sage` | Color grading, vignette, fade transitions, 6 presets |

### Networking

| Module | Description |
|--------|-------------|
| `net_protocol.sage` | 20 message types, length-prefixed framing, JSON serialization |
| `net_server.sage` | TCP server, client management, broadcast, non-blocking polling |
| `net_client.sage` | TCP client, connect/disconnect, ping measurement |
| `net_replication.sage` | Entity sync, delta compression, interpolation buffers |
| `lobby.sage` | Lobby management, player list, ready state, game settings |

### Editor

| Module | Description |
|--------|-------------|
| `undo_redo.sage` | Command history with execute/undo/redo |
| `inspector.sage` | Property panel displaying entity components |
| `gizmo.sage` | 3-axis translate/rotate/scale handles with ray picking |
| `asset_browser.sage` | Asset listing with categories and filtering |
| `scene_editor.sage` | Entity selection, placement, deletion, duplication, snap grid |
| `editor_viewport.sage` | Orbit/pan/zoom camera, mouse picking |
| `editor_layout.sage` | Unreal-style panel layout (toolbar, hierarchy, viewport, inspector) |
| `codegen.sage` | SageLang source code generator from ECS world state |

## Demos

| Demo | Command | Features |
|------|---------|----------|
| Basic | `./run.sh examples/demo.sage` | Spinning cubes, FPS camera |
| Lighting | `./run.sh examples/demo_lighting.sage` | Point/directional lights, fog, sky presets |
| Physics | `./run.sh examples/demo_physics.sage` | Falling objects, raycasting, health/damage |
| Assets | `./run.sh examples/demo_assets.sage` | Asset caching, scene save/load |
| AI | `./run.sh examples/demo_ai.sage` | Wandering/fleeing AI, behavior, tweens |
| UI | `./run.sh examples/demo_ui.sage` | HUD, health bar, crosshair, minimap, pause menu |
| World | `./run.sh examples/demo_world.sage` | Terrain, water, foliage, day/night cycle |
| Particles | `./run.sh examples/demo_particles.sage` | Fire, smoke, sparks, explosions, vignette |

## Writing a Game

Create a `.sage` file in the engine directory:

```python
import gpu
from engine import create_engine, on_update, on_render, run
from ecs import spawn, add_component
from components import TransformComponent, NameComponent
from mesh import cube_mesh, upload_mesh
from math3d import mat4_mul, radians
from engine_math import transform_to_matrix
from render_system import create_lit_material, draw_mesh_lit

let eng = create_engine("My Game", 1280, 720)
let world = eng["world"]

# Create a cube
let cube_gpu = upload_mesh(cube_mesh())
let e = spawn(world)
add_component(world, e, "transform", TransformComponent(0.0, 1.0, 0.0))
add_component(world, e, "mesh_id", {"mesh": cube_gpu})

proc my_update(e, dt):
    # Game logic runs at fixed timestep
    pass

proc my_render(e, frame):
    # Draw calls go here
    pass

on_update(eng, my_update)
on_render(eng, my_render)
run(eng)
```

Or use the visual editor and press **5** to generate the code automatically.

## Building

```bash
# Build with default entry point
./build.sh editor.sage -o sage_editor

# Build a specific game
./build.sh examples/demo_world.sage -o my_game

# Output structure
build/dist/
├── sage_editor          # Native launcher binary
├── lib/                 # 80+ .sage modules
├── shaders/             # Compiled SPIR-V shaders
├── examples/            # Demo programs
└── assets/              # Game assets
```

The build system compiles a C launcher that auto-discovers the SageLang interpreter and sets up the working directory.

## Testing

```bash
# Run all 47 test suites (1,299 checks)
./tests/run_all.sh

# Run a specific test
./run.sh tests/test_ecs.sage
./run.sh tests/test_physics.sage
./run.sh tests/test_navigation.sage
```

Test coverage spans every engine system: ECS, physics, collision, lighting, terrain, particles, networking, UI, animation, AI, serialization, and editor tools.

## Known Issues

- `gc_disable()` at the top of library modules produces non-fatal "Value is not callable" warnings during deep import chains. This is a SageLang interpreter issue with native function resolution in module scopes. The engine runs correctly despite these warnings. Use `./editor.sh` or `2>/dev/null` to suppress.
- `from module import let_variable` returns nil for variables initialized with function calls. Use `import module` + `module.variable` as a workaround.
- FFI `void` return type only supports 0-1 arguments (SageLang limitation).
- Audio system requires OpenAL; gracefully degrades if unavailable.

## License

Same license as the parent SageLang project.
