# Forge Engine Guide

A complete guide to building games and interactive experiences with the Forge Engine.

## Table of Contents

1. [Getting Started](#getting-started)
2. [The Editor](#the-editor)
3. [Engine Architecture](#engine-architecture)
4. [Creating a Game](#creating-a-game)
5. [Entity Component System](#entity-component-system)
6. [Rendering](#rendering)
7. [Physics](#physics)
8. [Input System](#input-system)
9. [UI Framework](#ui-framework)
10. [Audio](#audio)
11. [Animation](#animation)
12. [AI Systems](#ai-systems)
13. [Terrain and World](#terrain-and-world)
14. [Particles and VFX](#particles-and-vfx)
15. [Networking](#networking)
16. [Scene Serialization](#scene-serialization)
17. [Code Generation](#code-generation)
18. [Performance Tips](#performance-tips)
19. [SageLang Reference](#sagelang-reference)

---

## Getting Started

### Prerequisites

- **SageLang** compiler/interpreter (located at `../sagelang`)
- **Vulkan** GPU drivers
- **Linux** (tested on Ubuntu/Arch with NVIDIA GPUs)

### Quick Start

```bash
# Clone or copy the engine
cd ~/Devel/3DEngine

# Launch the visual editor
./editor.sh

# Run a demo
./run.sh examples/demo_world.sage

# Run all tests
./tests/run_all.sh
```

### Project Structure

```
forge-engine/
├── editor.sage          # Visual editor application
├── editor.sh            # Editor launcher script
├── run.sh               # Script runner
├── build.sh             # Build system
├── lib/                 # Engine modules
├── shaders/             # GLSL + SPIR-V shaders
├── assets/              # Fonts, textures, saved scenes
├── examples/            # Demo programs
├── tests/               # Test suites
└── build/               # Distribution output
```

---

## The Editor

The Forge Editor is a UE5-inspired visual scene editor with floating windows, a menu bar, and inline property editing. Build scenes by placing and transforming objects, edit properties directly, then generate a complete SageLang game script.

Press **F1** at any time to see the full keyboard shortcuts overlay.

### Editor Layout

- **Menu Bar** (top) — File, Edit, Window, Tools, Help dropdown menus
- **Toolbar** (below menu) — Move/Rotate/Scale mode buttons, Play button, Save button
- **Viewport** (center) — 3D scene with overlay bar showing Perspective/Lit/Show
- **Floating Windows** — Draggable, resizable panels that snap to screen edges:
  - **Outliner** — Scrollable list of all entities, click to select
  - **Details** — Editable transform properties (click values to type new numbers)
  - **Content Browser** — Asset list, shortcuts, imported model info
- **Status Bar** (bottom) — Entity count, draw count, mode, FPS

### Editor Controls

| Input | Action |
|-------|--------|
| RMB + Drag | Orbit camera |
| MMB + Drag | Pan camera |
| Scroll Wheel | Zoom viewport / scroll panels |
| Left Click (viewport) | Select entity by raycast |
| Left Click (outliner) | Select entity from list |
| Left Click (details value) | Edit property inline (type number, Enter to commit) |
| Right Click (viewport) | Context menu (Add Cube/Sphere/Physics, Delete) |
| 1 / 2 / 3 | Translate / Rotate / Scale gizmo mode |
| R / F / E | Place Cube / Sphere / Model |
| D / Q | Delete / Duplicate selected |
| TAB | Toggle physics on selected entity |
| ENTER | Play-in-Editor (generates game, toggles play mode) |
| Arrow Keys | Nudge selected entity |
| ESC | Deselect / cancel edit / close modal |
| CTRL+S / CTRL+N / CTRL+O | Save / New / Open scene |
| CTRL+Z / CTRL+Y | Undo / Redo (property edits, with command history) |
| CTRL+A | Select all entities |
| CTRL+Q | Quit (with confirmation dialog) |
| F1 | Toggle keyboard shortcuts overlay |

### Inline Property Editing

Click any X, Y, or Z value in the Details panel to enter edit mode:
- Type a new number using the keyboard
- Press **Enter** to commit (creates an undo-able command)
- Press **Escape** to cancel and restore the original value
- A blinking cursor shows the current edit position
- Use **Backspace**, **Delete**, **Home**, **End**, **Left/Right** to navigate

### Menu Bar

| Menu | Actions |
|------|---------|
| File | New Scene, Open Scene, Save Scene, Export Game, Quit |
| Edit | Delete, Duplicate, Select All |
| Window | Show/hide Outliner, Details, Content Browser |
| Tools | Add Cube/Sphere/Physics Cube, Toggle Physics, Generate Code |
| Help | Controls (F1 overlay), About |

### Modal Dialogs

Certain actions (like Quit) show a modal confirmation dialog with Yes/No buttons. Press Escape to dismiss.

---

## Engine Architecture

Forge Engine is built as a collection of SageLang modules. Each module handles a specific concern:

```
┌─────────────────────────────────────────────┐
│                  Your Game                   │
├─────────┬──────────┬──────────┬─────────────┤
│ Gameplay│ Physics  │ AI       │ Networking   │
├─────────┴──────────┴──────────┴─────────────┤
│ ECS (Entity Component System)                │
├──────────┬──────────┬───────────────────────┤
│ Rendering│ UI       │ Animation             │
├──────────┴──────────┴───────────────────────┤
│ Vulkan GPU Backend (SageLang gpu module)     │
└─────────────────────────────────────────────┘
```

---

## Creating a Game

### Minimal Game

```python
from engine import create_engine, on_update, on_render, run

let eng = create_engine("My Game", 1280, 720)

proc update(e, dt):
    # Game logic (called at fixed timestep, 60 Hz)
    pass

proc render(e, frame):
    # Rendering (called every frame)
    pass

on_update(eng, update)
on_render(eng, render)
run(eng)
```

### Adding Objects

```python
from ecs import spawn, add_component
from components import TransformComponent, NameComponent
from mesh import cube_mesh, upload_mesh

let world = eng["world"]
let cube_gpu = upload_mesh(cube_mesh())

let entity = spawn(world)
add_component(world, entity, "transform", TransformComponent(0.0, 1.0, 0.0))
add_component(world, entity, "name", NameComponent("MyCube"))
add_component(world, entity, "mesh_id", {"mesh": cube_gpu})
```

### Adding Lighting

```python
from lighting import create_light_scene, directional_light, point_light
from lighting import add_light, set_ambient, init_light_gpu

let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.8, 0.5, 1.0, 0.95, 0.85, 1.2))
add_light(ls, point_light(5.0, 3.0, 0.0, 1.0, 0.4, 0.2, 3.0, 15.0))
set_ambient(ls, 0.15, 0.15, 0.2, 0.3)
```

### Player Controller

```python
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position

let player = create_player_controller()
player["position"] = vec3(0.0, 2.0, 10.0)

# In update:
update_player(player, inp, dt)
```

---

## Entity Component System

The ECS is the core of Forge Engine. Entities are integer IDs. Components are dicts stored by type. Systems are functions that operate on entities with matching components.

### Creating Entities

```python
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, destroy, add_tag

let world = create_world()
let e = spawn(world)
add_component(world, e, "transform", TransformComponent(0.0, 0.0, 0.0))
```

### Querying Entities

```python
# Find all entities with both transform and mesh_id components
let renderers = query(world, ["transform", "mesh_id"])

# Find entities by tag
let enemies = query_tag(world, "enemy")
```

### Systems

```python
from ecs import register_system, tick_systems

proc spin_system(world, entities, dt):
    let i = 0
    while i < len(entities):
        let t = get_component(world, entities[i], "transform")
        t["rotation"][1] = t["rotation"][1] + dt
        t["dirty"] = true
        i = i + 1

register_system(world, "spin", ["transform", "velocity"], spin_system)

# In game loop:
tick_systems(world, dt)
```

### Built-in Components

| Component | Constructor | Fields |
|-----------|------------|--------|
| Transform | `TransformComponent(x, y, z)` | position, rotation, scale, matrix, dirty |
| Velocity | `VelocityComponent()` | linear, angular, damping |
| Camera | `CameraComponent(fov, near, far)` | fov, near, far, yaw, pitch |
| PointLight | `PointLightComponent(r,g,b, intensity, radius)` | type, color, intensity, radius |
| DirectionalLight | `DirectionalLightComponent(r,g,b, intensity)` | type, color, intensity |
| Name | `NameComponent(name)` | name |
| Health | `HealthComponent(max_hp)` | current, max, alive |

---

## Rendering

### Materials

```python
from render_system import create_lit_material, draw_mesh_lit

let lit_mat = create_lit_material(render_pass, ls["desc_layout"], ls["desc_set"])

# In render loop:
let model = transform_to_matrix(t)
let mvp = mat4_mul(vp, model)
draw_mesh_lit(cmd, lit_mat, mesh_gpu, mvp, model, ls["desc_set"])
```

### Sky

```python
from sky import create_sky, sky_preset_day, init_sky_gpu, draw_sky

let sky = create_sky()
sky_preset_day(sky)   # Also: sky_preset_sunset, sky_preset_night, sky_preset_overcast
init_sky_gpu(sky, render_pass)

# In render: draw before geometry
draw_sky(sky, cmd, view, aspect, radians(60.0), time)
```

### Frustum Culling

```python
from frustum import extract_frustum_planes, aabb_in_frustum

let planes = extract_frustum_planes(vp)
if aabb_in_frustum(planes, position, half_extent):
    # Object is visible, draw it
```

---

## Physics

```python
from physics import RigidbodyComponent, BoxColliderComponent, create_physics_world, create_physics_system

let pw = create_physics_world()
pw["gravity"] = vec3(0.0, -9.81, 0.0)

register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(pw))

# Add to entity:
add_component(world, e, "rigidbody", RigidbodyComponent(1.0))
add_component(world, e, "collider", BoxColliderComponent(0.5, 0.5, 0.5))
```

### Collision Detection

```python
from collision import ray_vs_aabb, ray_vs_sphere, sphere_vs_sphere, aabb_vs_aabb

let hit = ray_vs_aabb(origin, direction, box_pos, box_half)
if hit != nil:
    print "Hit at t=" + str(hit["t"])
```

---

## Input System

```python
from input import create_input, update_input, bind_action, bind_axis
from input import action_held, action_just_pressed, axis_value

let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "shoot", [gpu.KEY_E])

# In update:
update_input(inp)
if action_just_pressed(inp, "shoot"):
    # Fire!
```

### Available Keys

Letters: `KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_R, KEY_F`
Numbers: `KEY_1` through `KEY_5`
Special: `KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_SHIFT, KEY_CTRL`
Arrows: `KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT`
Mouse: `MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE`

---

## Animation

### Tweening

```python
from tween import create_tween, update_tween, tween_value

let tw = create_tween(0.0, 100.0, 2.0, "out_bounce")
tw["loop"] = true

# In update:
update_tween(tw, dt)
let val = tween_value(tw)
```

Available easings: `linear`, `in_quad`, `out_quad`, `in_out_quad`, `in_cubic`, `out_cubic`, `in_sine`, `out_sine`, `in_expo`, `out_expo`, `in_elastic`, `out_elastic`, `out_bounce`, `in_bounce`, `in_back`, `out_back`

### Skeletal Animation

```python
from animation import create_skeleton, add_bone, create_clip, create_anim_controller

let sk = create_skeleton()
add_bone(sk, "root", nil)
add_bone(sk, "spine", "root")
add_bone(sk, "head", "spine")
```

---

## AI Systems

### Pathfinding

```python
from navigation import create_nav_grid, find_path, steer_arrive

let grid = create_nav_grid(20, 20, 1.0)
set_blocked(grid, 5, 5)

let path = find_path(grid, 0, 0, 19, 19)
```

### Behavior Trees

```python
from behavior_tree import bt_sequence, bt_selector, bt_action, bt_condition, bt_tick

let tree = bt_selector("root", [
    bt_sequence("attack", [
        bt_condition("see_player", see_player_fn),
        bt_action("fire", fire_fn)
    ]),
    bt_action("patrol", patrol_fn)
])

# In update:
bt_tick(tree, context)
```

---

## Terrain and World

```python
from terrain import create_terrain, generate_terrain_noise, upload_terrain, sample_height
from water import create_water, upload_water
from day_night import create_day_cycle, update_day_cycle

let terrain = create_terrain(32, 32, 200.0, 200.0, 15.0)
generate_terrain_noise(terrain, 42.0, 5, 0.5, 2.0, 4.0)
let terrain_gpu = upload_terrain(terrain)

let water = create_water(200.0, 16, 3.0)

let day = create_day_cycle(120.0)  # 2-minute day
set_time_of_day(day, 0.35)         # Morning
```

---

## Particles and VFX

```python
from vfx_presets import vfx_fire, vfx_explosion, vfx_rain
from particles import update_emitter

let fire = vfx_fire(vec3(0.0, 0.0, 0.0), 1.0)
let boom = vfx_explosion(vec3(5.0, 1.0, 0.0), 2.0)

# In update:
update_emitter(fire, dt)
```

Presets: `vfx_fire`, `vfx_smoke`, `vfx_sparks`, `vfx_explosion`, `vfx_rain`, `vfx_dust`, `vfx_magic`

---

## Networking

```python
from net_server import create_server, start_server, poll_server
from net_client import create_client, connect_to_server, poll_client
from net_replication import create_replication_manager

# Server
let srv = create_server(7777)
start_server(srv)

# Client
let cl = create_client()
connect_to_server(cl, "localhost", 7777, "Player1")
```

---

## Scene Serialization

```python
from scene_serial import save_scene, load_scene

# Save
save_scene(world, "MyScene", "assets/my_scene.json")

# Load
let result = load_scene("assets/my_scene.json")
let loaded_world = result["world"]
```

---

## Code Generation

The editor generates complete SageLang game scripts:

```python
from codegen import generate_game_script

let code = generate_game_script(world, "MyGame", {"width": 1280, "height": 720})
io.writefile("my_game.sage", code)

# Run the generated game:
# ./run.sh my_game.sage
```

---

## Performance Tips

1. **Use frustum culling** — `extract_frustum_planes` + `aabb_in_frustum` to skip off-screen objects
2. **Use the spatial grid** — `create_spatial_grid` for broadphase collision instead of O(n^2) pair checks
3. **Batch text rendering** — use `begin_text` / `add_text` / `flush_text` instead of individual `draw_text` calls
4. **Use native functions** — `build_quad_verts` and `array_extend` are C-native and 50x faster than SageLang equivalents
5. **Cache when possible** — only rebuild UI/text when state changes, not every frame
6. **Limit entity count** — the ECS uses dict-based storage; keep entity counts reasonable (<1000)

---

## SageLang Reference

### Key Language Features

```python
# Variables
let x = 42
let name = "hello"

# Functions
proc greet(name):
    print "Hello " + name

# Classes
class Animal:
    proc init(self, name):
        self.name = name

# Control flow
if condition:
    # ...
while running:
    # ...
for item in array:
    # ...

# Error handling
try:
    risky_operation()
catch e:
    print "Error: " + e.message

# Imports
import gpu
from math3d import vec3, mat4_mul
```

### Native Functions Added by Forge Engine

| Function | Description |
|----------|-------------|
| `build_quad_verts(quads)` | Convert quad dicts to vertex float array (C native, 50x faster) |
| `array_extend(target, source)` | Append all elements of source to target (C native memcpy) |
| `gpu.load_font(path, size)` | Rasterize TTF font to atlas texture |
| `gpu.font_text_verts(handle, text, x, y, r, g, b, a)` | Generate text vertex data |
| `gpu.font_measure(handle, text)` | Measure text dimensions |
| `gpu.font_atlas(handle)` | Get font atlas info (texture, sampler) |
| `build_line_quads(lines, thickness, r, g, b, a)` | Convert line segments to quad array |

---

## Building for Distribution

```bash
./build.sh editor.sage -o forge_editor

# Output:
# build/dist/forge_editor   — native launcher
# build/dist/lib/           — all engine modules
# build/dist/shaders/       — compiled SPIR-V
# build/dist/assets/        — fonts, textures
# build/dist/examples/      — demo programs
```
