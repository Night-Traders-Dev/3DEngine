# Forge Engine Guide

A complete guide to building games and interactive experiences with the Forge Engine.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Project Browser](#project-browser)
3. [The Editor](#the-editor)
4. [Engine Architecture](#engine-architecture)
5. [Creating a Game](#creating-a-game)
6. [Entity Component System](#entity-component-system)
7. [Rendering](#rendering)
8. [Physics](#physics)
9. [Input System](#input-system)
10. [UI Framework](#ui-framework)
11. [Audio](#audio)
12. [Animation](#animation)
13. [AI Systems](#ai-systems)
14. [Terrain and World](#terrain-and-world)
15. [Particles and VFX](#particles-and-vfx)
16. [Networking](#networking)
17. [Scene Serialization](#scene-serialization)
18. [Content Pipeline](#content-pipeline)
19. [Code Generation](#code-generation)
20. [Building for Distribution](#building-for-distribution)
21. [Coroutines](#coroutines)
22. [Environment Configuration](#environment-configuration)
23. [Performance Tips](#performance-tips)
24. [SageLang Reference](#sagelang-reference)

---

## Getting Started

### Prerequisites

- **SageLang** compiler/interpreter (located at `../sagelang`)
- **Vulkan** GPU drivers
- **Linux** (tested on Ubuntu/Arch with NVIDIA and AMD GPUs)

### Quick Start

```bash
# Clone or copy the engine
cd ~/Devel/3DEngine

# Launch the visual editor (opens project browser first)
./run.sh editor.sage

# Run the voxel sandbox demo
./run.sh examples/demo_voxel.sage

# Run all tests
./tests/run_all.sh

# Build distributable package
./build_dist.sh
```

### Project Structure

```text
forge-engine/
├── editor.sage          # Visual editor application (~1,700 lines)
├── run.sh               # Script runner
├── build_dist.sh        # Distribution builder (sage runtime + engine bundle)
├── VERSION              # Single source of truth for engine version
├── lib/                 # Engine modules (93 files)
├── shaders/             # GLSL + SPIR-V shaders
├── assets/              # Fonts, textures, saved scenes
├── examples/            # 9 demo programs
├── tests/               # 58 test suites, 1,700 checks
└── build/               # Distribution output
    └── dist/            # Self-contained distributable
```

Runtime/editor version strings and distribution packaging are sourced from the repo-root `VERSION` file through `lib/forge_version.sage`.
Forge uses `x.y.z` semantic versioning and intentionally remains on `0.y.z` until the engine is functionally complete enough to justify `1.0.0`. See [VERSIONING.md](VERSIONING.md) for the repo policy.
The automated suite now includes a dedicated renderer sanity check for startup helpers like pipeline cache state, a focused shadow-map helper suite, the new voxel world and voxel gameplay suites, a packaged voxel-template Play-In-Editor smoke that exercises the real dist launch path, plus runtime startup and longer stability shells that verify those paths stay alive through transient frame-loss conditions instead of force-closing early.

---

## Project Browser

When you launch the editor, a **Project Browser** screen appears before the editor loads. This is similar to Unreal Engine's project selection screen.

### Layout

- **Left panel — Templates**: 7 game type templates displayed as selectable cards, each with a colored badge, name, and description
- **Right panel — Actions**: Three buttons for Create New Project, Open Existing Project, and Exit
- **Preview area**: Shows the selected template's description and a list of included features (e.g., "Player controller + camera", "Weapon system + raycasting")

### Templates

| Template | Description | Includes |
| --- | --- | --- |
| **FPS** | First Person Shooter | Player controller, weapons, health/damage HUD, AI enemies |
| **RPG** | Role-Playing Game | Third-person camera, inventory, quests, stats/leveling |
| **Top-Down** | Top-Down Action | Overhead camera, twin-stick controls, projectiles, spawner |
| **Voxel** | Voxel World | Shared voxel sandbox module, first-class editor voxel world actor, place/break tools, color-aware block palette, hotbar/backpack HUD, inventory/crafting/chunk-save loop |
| **Racing** | Racing Game | Vehicle physics, chase camera, lap timer, speed HUD |
| **Survival** | Survival | Crafting, hunger/thirst, day-night cycle, buildable shelters |
| **Sandbox** | Sandbox / Empty | Empty scene with grid, basic lighting, full creative freedom |

### Controls

| Input | Action |
| --- | --- |
| Click | Select template / click buttons |
| Up / Down arrows | Navigate templates |
| Enter | Create project with selected template |
| ESC | Exit |

---

## The Editor

The Forge Editor is a UE5-inspired visual scene editor with floating windows, a menu bar, and inline property editing. Build scenes by placing and transforming objects, edit properties directly, then generate a complete SageLang game script.

Press **F1** at any time to see the full keyboard shortcuts overlay.

Choosing the `Voxel` launcher template now seeds a first-class voxel world actor in the editor using the same shared voxel generation rules as the playable sandbox demo. Selected voxel worlds support `SHIFT+LMB/RMB` block editing plus `SHIFT+Z/X` brush cycling in the editor, and the playable voxel sandbox now supports inventory-backed mining/placement, world drops with magnetic pickup collection, a first plank-crafting loop, hostile slime mobs with simple chase/attack behavior, lazy chunk generation, incremental streamed chunk uploads, more saturated top/side/bottom voxel colors with procedural detail, a shared hotbar/backpack/crafting HUD, plus chunked JSON save/load controls.

### Editor Layout

- **Menu Bar** (top) — File, Edit, Window, Tools, Help dropdown menus
- **Toolbar** (below menu) — Move/Rotate/Scale mode buttons, Play button, Save button
- **Viewport** (center) — 3D scene with dark background so lit objects stand out clearly
- **Floating Windows** — Draggable, resizable panels that snap to screen edges and reposition on window resize:
  - **Outliner** — Scrollable list of all entities, click to select
  - **Details** — Editable transform and light properties, inline render/shadow toggles, component sections with accent bars, color-coded booleans
  - **Content Browser** — Asset list, shortcuts, imported model info
- **Status Bar** (bottom) — Entity count, draw count, mode, FPS

### Editor Controls

| Input | Action |
| --- | --- |
| RMB + Drag | Orbit camera |
| MMB + Drag | Pan camera |
| Scroll Wheel | Zoom viewport / scroll panels |
| Left Click (viewport) | Select entity by raycast |
| Left Click (outliner) | Select entity from list |
| Left Click (details value) | Edit transform/light numbers or toggle render/shadow flags inline |
| Shift+Left Click / Shift+Right Click | Break / place voxel in selected voxel world |
| Shift+Z / Shift+X | Previous / next voxel brush on selected voxel world |
| Right Click (viewport) | Context menu (Add Cube/Sphere/Physics, Delete) |
| 1 / 2 / 3 | Translate / Rotate / Scale gizmo mode |
| R / F / E | Place Cube / Sphere / Model |
| D / Q | Delete / Duplicate selected |
| TAB | Toggle physics on selected entity |
| Space / Shift+Space | Play-pause / toggle looping on selected imported animation |
| Ctrl+Left / Ctrl+Right | Previous / next clip on selected imported animation |
| Ctrl+Up / Ctrl+Down | Scrub selected imported animation time |
| `-` / `=` | Decrease / increase selected imported animation speed |
| ENTER | Play-in-Editor (generates game, toggles play mode) |
| Arrow Keys | Nudge selected entity |
| ESC | Deselect / cancel edit / close modal |
| CTRL+S / CTRL+N / CTRL+O | Save / New / Open scene |
| CTRL+Z / CTRL+Y | Undo / Redo (property edits, with command history) |
| CTRL+A | Select all entities |
| CTRL+Q | Quit (with confirmation dialog) |
| F1 | Toggle keyboard shortcuts overlay |

### Inline Property Editing

Click transform axes or light numeric values in the Details panel to enter edit mode:

- Type a new number using the keyboard
- Press **Enter** to commit (creates an undo-able command)
- Press **Escape** to cancel and restore the original value
- A blinking cursor shows the current edit position
- Use **Backspace**, **Delete**, **Home**, **End**, **Left/Right** to navigate
- Use the mouse wheel to nudge the active numeric field, with **Shift** for a larger step

Render and shadow booleans such as mesh visibility, mesh `cast_shadows` / `receive_shadows`, and directional-light `cast_shadows` can now be toggled directly from the Details panel as well as from the Tools/context menus.

### Menu Bar

| Menu | Actions |
| --- | --- |
| File | New Scene, Open Scene, Save Scene, Save Screenshot, Export Game, Compile Native, Quit |
| Edit | Undo, Redo, Delete, Duplicate, Select All |
| Window | Show/hide Outliner, Details, Content Browser, Reset Layout |
| Tools | Add Cube/Sphere/Physics Cube/Voxel World/Light, Apply Materials, Toggle Visibility, Toggle Cast Shadows, Toggle Receive Shadows, Save as Prefab, Toggle Physics, Generate Code |
| Help | Controls (F1 overlay), About |

### Modal Dialogs

Certain actions (like Quit) show a modal confirmation dialog with themed Yes/No buttons. Press Escape to dismiss.

---

## Engine Architecture

Forge Engine is built as a collection of SageLang modules. Each module handles a specific concern:

```text
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

### UI Architecture

The UI system uses a centralized theme defined in `ui_core.sage`:

```text
ui_core.sage          Theme system (40+ colors, spacing, sizing, helpers)
  ├── ui_widgets.sage   Advanced widgets (sliders, checkboxes, dropdowns, text fields)
  ├── ui_window.sage    Floating windows, context menus, modals
  ├── ui_renderer.sage  Batched GPU quad rendering
  ├── launch_screen.sage  Project browser
  ├── hud.sage          Game HUD components
  ├── menu.sage         Game menu screens
  └── inspector.sage    Entity property inspector
```

All UI modules reference `ui_core.THEME_*` constants instead of hardcoding colors, ensuring visual consistency across the entire engine.

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
| --- | --- | --- |
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

### Collision Callbacks

```python
from physics import register_collision_callback

proc on_hit(event):
    print "Entity " + str(event["entity_a"]) + " hit " + str(event["entity_b"])
    print "Normal: " + str(event["normal"]) + " Depth: " + str(event["depth"])

register_collision_callback(physics_world, entity_id, on_hit)
# Callbacks fire automatically during physics_update
# Access all frame events: physics_world["collision_events"]
```

### Physics Constraints

```python
from physics import FixedConstraint, DistanceConstraint, HingeConstraint

# Fixed: entity_b stays at offset from entity_a
let fixed = FixedConstraint(entity_a, entity_b, vec3(2.0, 0.0, 0.0))
push(physics_world["constraints"], fixed)

# Distance: maintain distance between two entities
let dist = DistanceConstraint(entity_a, entity_b, 5.0)
dist["stiffness"] = 0.8
push(physics_world["constraints"], dist)

# Hinge: rotation limits around an axis
let hinge = HingeConstraint(entity_a, entity_b, vec3(0.0, 1.0, 0.0), [-1.57, 1.57])
push(physics_world["constraints"], hinge)
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

Letters: `KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_R, KEY_F, KEY_Z, KEY_Y, KEY_X, KEY_C, KEY_V, KEY_N, KEY_O`
Numbers: `KEY_1` through `KEY_5`
Special: `KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_SHIFT, KEY_CTRL, KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, KEY_F1`
Arrows: `KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT`
Mouse: `MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE`

---

## UI Framework

The UI system provides a complete widget toolkit with a centralized theme.

### Theme System

All colors, spacing, and sizing are defined in `ui_core.sage`:

```python
import ui_core

# Surface colors (wider spread for contrast)
ui_core.THEME_BG          # Darkest background
ui_core.THEME_SURFACE     # Recessed surfaces
ui_core.THEME_PANEL       # Panel backgrounds
ui_core.THEME_HEADER      # Section headers
ui_core.THEME_ELEVATED    # Elevated elements (menus, tooltips)

# Interactive states
ui_core.THEME_BUTTON        # Default button
ui_core.THEME_BUTTON_HOVER  # Hovered button
ui_core.THEME_BUTTON_ACTIVE # Pressed button

# Accent colors
ui_core.THEME_ACCENT       # Primary accent (blue)
ui_core.THEME_ACCENT_HOVER # Hovered accent

# Semantic colors
ui_core.THEME_SUCCESS   # Green (true values, health high)
ui_core.THEME_WARNING   # Yellow (health medium)
ui_core.THEME_DANGER    # Red (false values, health low, quit buttons)

# Spacing constants
ui_core.SP_XS   # 2px
ui_core.SP_SM   # 4px
ui_core.SP_MD   # 8px
ui_core.SP_LG   # 12px
ui_core.SP_XL   # 16px
ui_core.SP_XXL  # 24px

# Font sizes
ui_core.FONT_SM    # 1.8
ui_core.FONT_MD    # 2.2
ui_core.FONT_LG    # 2.8
ui_core.FONT_TITLE # 4.5
```

### Widget States

Buttons support four visual states:

- **Default** — `bg_color`
- **Hover** — `hover_color` (brightened) + focus ring + top highlight
- **Pressed** — `active_color` (darkened)
- **Disabled** — `disabled_color` (dimmed, ignores clicks)

### Advanced Widgets

```python
import ui_widgets

# Slider with track, fill, and thumb handle
let sl = ui_widgets.create_slider(x, y, 200.0, 0.0, 100.0, 50.0)

# Checkbox with accent fill when checked
let cb = ui_widgets.create_checkbox(x, y, "Enable Physics", true)

# Dropdown with open/close animation and selected highlight
let dd = ui_widgets.create_dropdown(x, y, 150.0, ["Low", "Medium", "High"], 1)

# Text field with blinking cursor and focus border
let tf = ui_widgets.create_text_field(x, y, 200.0, "default value")

# Section header with accent bar and collapse indicator
let sh = ui_widgets.create_section_header(x, y, 240.0, "Transform")
```

### Quad Collection for Rendering

Each advanced widget type has a dedicated quad collector:

```python
# Collect visual quads for custom rendering
ui_widgets.collect_slider_quads(slider, quads)
ui_widgets.collect_checkbox_quads(checkbox, quads)
ui_widgets.collect_dropdown_quads(dropdown, quads)
ui_widgets.collect_text_field_quads(text_field, quads)
ui_widgets.collect_section_header_quads(header, quads)
ui_widgets.collect_scrollbar_quads(scroll_panel, quads)
```

### Game HUD

```python
from hud import create_game_hud, update_game_hud

let hud = create_game_hud()

# In update:
update_game_hud(hud, health_pct, score_pts, combo, fps, entity_count)
```

HUD includes:

- **Health bar** — 4-stage smooth color transition (green > yellow > red > critical pulsing)
- **Crosshair** — Modern gapped-line style with center dot
- **Score display** — Points + combo counter
- **Info panel** — FPS + entity count
- **Minimap** — Top-down view with themed player (cyan) and enemy (red) dots

### Game Menus

```python
from menu import create_menu_system, create_pause_menu, show_menu

let menus = create_menu_system()
let pause = create_pause_menu(on_resume, on_quit)
register_menu(menus, "pause", pause)

# Show with fade animation:
show_menu(menus, "pause")
```

Menu types: `create_pause_menu`, `create_main_menu`, `create_game_over_menu`

Buttons use style variants: `"primary"` (accent), `"danger"` (red), `"success"` (green). Menus include title headers with accent underlines, visual hierarchy between primary and secondary actions, and hint text.

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

### Two-Bone IK

```python
from animation import solve_ik_two_bone, apply_ik_to_skeleton

let result = solve_ik_two_bone(shoulder_pos, elbow_pos, hand_pos, target_pos, pole_target)
apply_ik_to_skeleton(skeleton, "upper_arm", "lower_arm", "hand", target_pos, pole_target)
```

### Animation Events

```python
from animation import add_animation_event, fire_animation_events

add_animation_event(walk_clip, 0.25, "footstep_left", {"volume": 0.8})
add_animation_event(walk_clip, 0.75, "footstep_right", {"volume": 0.8})

proc on_anim_event(evt):
    if evt["name"] == "footstep_left":
        play_sound(audio, "step_l", "sfx", evt["data"]["volume"], false)

fire_animation_events(controller, walk_clip, prev_time, curr_time, on_anim_event)
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

### Secure Networking

```python
from net_server import create_secure_server
from net_client import connect_secure

let srv = create_secure_server(8443, "cert.pem", "key.pem")
let client = connect_secure("game.example.com", 8443)
```

---

## Scene Serialization

```python
from scene_serial import save_scene, load_scene
from scene_serial import save_prefab, load_prefab, list_prefabs

# Save scene
save_scene(world, "MyScene", "assets/my_scene.json")

# Load scene
let result = load_scene("assets/my_scene.json")
let loaded_world = result["world"]

# Prefabs
save_prefab(world, entity_id, "EnemyTank", "assets/prefabs/tank.prefab.json")
let new_eid = load_prefab(world, "assets/prefabs/tank.prefab.json")
let prefab_list = list_prefabs("assets/prefabs")
```

---

## Content Pipeline

### Asset Import

```python
from asset_import import import_gltf, scan_importable_assets

let assets = scan_importable_assets("assets")
let model = import_gltf("assets/character.gltf")
# model["gpu_meshes"], model["materials"], model["animations"]
```

Imported glTF assets keep their per-material albedo, metallic, roughness, and texture references. In the editor, imported meshes now prefer the PBR render path when material data is available, with a lit-material fallback for meshes that only provide partial surface data. Imported node transforms are also preserved, so multi-node glTF assets render with their authored hierarchy instead of flattening every mesh to the parent entity transform. When a glTF includes transform animation clips, the importer also keeps the clip channels so authored node translation/rotation/scale animation can play back in the editor and in generated games. glTF skin metadata is now parsed as well, with joints, inverse bind matrices, per-node skin assignments, and skinned vertex attributes exposed through imported assets and shared draw generation. Selected imported assets expose clip switching, scrubbing, speed adjustment, looping controls, imported skin/joint counts, and live directional-shadow participation directly in the editor.

Imported skin support now reaches the actual render path: joints/weights are expanded into the shared mesh vertex format, joint palettes are uploaded through a shared skin UBO, and imported skinned meshes deform in both the editor and generated runtime. That same shared draw data now feeds the directional shadow depth pass, so imported skinned meshes cast the same first-pass sun shadows as static meshes. The current implementation is a first pass with a shared 128-joint-per-draw budget and no higher-level character tooling beyond playback.

Scene save/load and Play-In-Editor snapshots preserve imported asset references by storing the stable source path and rehydrating the full GPU-ready asset on load. That keeps imported content alive across open/save/play cycles instead of limiting it to the original live editor session.

### Material Presets

```python
from material import create_material_preset, get_material_presets

# Available: Metal, Wood, Concrete, Glass, Plastic, Gold, Rubber, Emissive
let gold = create_material_preset("Gold")
add_component(world, entity_id, "material", gold)
```

### Hot Reload

```python
from hot_reload import create_file_watcher, watch_asset_directory, check_asset_changes

let hr = create_file_watcher()

proc on_asset_change(filename, path, change_type):
    print filename + " was " + change_type

watch_asset_directory(hr, "assets/textures", on_asset_change)

# Poll each frame:
let changes = check_asset_changes(hr)
```

### Level Streaming

```python
from scene import create_level_manager, request_level_load, process_level_queue

let lm = create_level_manager()
request_level_load(lm, "dungeon_1", "assets/levels/dungeon_1.json")

# Process in game loop:
process_level_queue(lm, world)
```

### Async Asset Loading

```python
from asset_import import request_async_load, process_async_loads, get_async_results

request_async_load("assets/character.gltf", "gltf")
request_async_load("assets/terrain.png", "texture")

# Process one load per frame (no freeze):
process_async_loads()
let loaded = get_async_results()
```

---

## Code Generation

The editor generates complete SageLang game scripts:

```python
from codegen import generate_game_script, compile_game_native

# Generate script
let code = generate_game_script(world, "MyGame", {"width": 1280, "height": 720})
io.writefile("my_game.sage", code)

# Run interpreted:
# ./run.sh my_game.sage
```

Generated scripts now carry more of the authored scene intent across the editor/runtime boundary:

- Authored point and directional light entities are emitted into the generated lighting setup.
- The primary scene camera seeds the runtime player controller position, yaw, pitch, FOV, near plane, and far plane.
- Generated games now run the same first-pass directional shadow prepass used by the editor, with a single primary directional light feeding the forward lit/PBR path and the light-space projection snapped to the shadow texel grid for better stability.
- Mesh-backed entities now preserve `mesh_renderer` visibility plus `cast_shadows` / `receive_shadows` flags through export, so the generated runtime respects the same authored render/shadow controls as the editor viewport.
- Voxel world actors are restored from serialized block data and rendered through the shared voxel streaming helpers in generated games, so authored voxel scenes are no longer editor-only.
- Imported glTF entities are re-imported on startup, rendered through the generated PBR path when material data is available, keep their authored node hierarchy transforms, preserve transform-animation clip playback through `animation_state`, including clip, time, speed, and looping state, and deform imported skinned meshes through the same shared 128-joint skinning path and shadow depth path used by the editor.
- Material-bearing entities continue to use the material-aware lit draw path after export.

### GPU-Driven Rendering

```python
from render_system import create_indirect_buffer, draw_mesh_lit_indirect
from render_system import create_compute_pipeline, dispatch_compute
from render_system import barrier_compute_to_graphics

let indirect_buf = create_indirect_buffer(1024)
draw_mesh_lit_indirect(cmd, material, indirect_buf, draw_count, 20)

let cp = create_compute_pipeline("shaders/cull.comp.spv", desc_layout, 16)
dispatch_compute(cmd, cp, 64, 1, 1, desc_set, push_data)
barrier_compute_to_graphics(cmd)
```

---

## Building for Distribution

### Distribution Build

```bash
# Build a self-contained package
./build_dist.sh

# Output: build/dist/ (~4.1MB, 112 .sage modules)
# Contains: sage runtime binary + engine libs + stdlib + VERSION + shaders + assets

# Run:
cd build/dist && ./forge_engine

# Optional deterministic launch shortcuts:
FORGE_TEMPLATE=voxel ./forge_engine
FORGE_TEMPLATE=voxel FORGE_AUTOPLAY=1 ./forge_engine

# Package for sharing:
tar -czf forge_engine-$(cat VERSION).tar.gz -C build dist
```

### What's Included

| Component | Description |
| --- | --- |
| `sage` | SageLang runtime binary (ELF x86-64, links Vulkan/GLFW/OpenGL) |
| `VERSION` | Shared engine release version copied into the distributable |
| `lib/` | 93 engine .sage modules |
| `stdlib/` | 33 SageLang standard library modules |
| `shaders/` | Compiled SPIR-V shaders |
| `assets/` | Fonts (DejaVuSans), glTF models, textures, saved scenes |
| `editor.sage` | Editor entry point |
| `examples/` | 9 demo programs |
| `forge_engine` | Launch script |

### Native Compilation Status

The SageLang LLVM backend supports native compilation for GPU-centric programs via `sage --compile-llvm`, but does not yet support multi-module projects with `from X import Y` imports. The editor uses 30+ modules with 130+ cross-module imports, which exceeds the current LLVM backend's capabilities. Use the interpreter-based distribution build for now.

---

## Coroutines

SageLang generators enable game sequences without blocking the frame loop:

```python
from game_loop import start_coroutine, update_coroutines, is_coroutine_running

proc cutscene_intro():
    print "Camera panning..."
    yield true
    print "Title appears..."
    yield true
    yield true
    print "Cutscene done"

start_coroutine("intro", cutscene_intro())

# In game loop:
update_coroutines(dt)
```

---

## Environment Configuration

Set engine parameters via environment variables:

```bash
FORGE_WIDTH=1920 FORGE_HEIGHT=1080 FORGE_FULLSCREEN=1 ./run.sh editor.sage
```

Supported: `FORGE_WIDTH`, `FORGE_HEIGHT`, `FORGE_FULLSCREEN`, `FORGE_VSYNC`, `FORGE_DEBUG`

---

## Performance Tips

1. **Use frustum culling** — `extract_frustum_planes` + `aabb_in_frustum` to skip off-screen objects
2. **Use the spatial grid** — `create_spatial_grid` for broadphase collision instead of O(n^2) pair checks
3. **Batch text rendering** — use `begin_text` / `add_text` / `flush_text` instead of individual calls
4. **Use native functions** — `build_quad_verts` and `array_extend` are C-native and 50x faster than SageLang equivalents
5. **Cache when possible** — only rebuild UI/text when state changes, not every frame
6. **Use indirect rendering** — `cmd_draw_indirect` for GPU-driven draw calls (10K+ objects)
7. **Use pipeline cache** — `create_pipeline_cache` reduces pipeline compilation stutter
8. **Use device-local uploads** — `upload_mesh_device_local` for optimal GPU memory placement
9. **Use LOD** — `compute_lod` skips distant objects automatically
10. **GC tuning** — `gc_disable()` at file top, `gc_collect()` at frame boundary
11. **Limit entity count** — the ECS uses dict-based storage; keep entity counts reasonable (<1000)

---

## SageLang Reference

### Current Status

- SageLang is currently on the March 2026 `v2.0.0` specification-lock release, so core semantics and module-system behavior are intentionally frozen.
- The official updates also add REPL `:runtime jit` and `:runtime aot` modes, and the project reports 1987+ tests passing in that line.
- Sage centralizes its own version string through a repo-root `VERSION` file now, which matches Forge's single-source versioning approach.
- Sage's roadmap still lists native codegen for module/class/GPU support as future work, so Forge keeps validating the interpreted/editor/export runtime path directly inside this repo.

### Key Language Features

```python
# Variables
let x = 42
let name = "hello"

# Functions
proc greet(name):
    print "Hello " + name

# Pattern matching
match value:
    case 1:
        print "one"
    case 2:
        print "two"
    default:
        print "other"

# Defer (cleanup on scope exit)
defer:
    close_resource(handle)

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
| --- | --- |
| `build_quad_verts(quads)` | Convert quad dicts to vertex float array (C native, 50x faster) |
| `array_extend(target, source)` | Append all elements of source to target (C native memcpy) |
| `gpu.load_font(path, size)` | Rasterize TTF font to atlas texture |
| `gpu.font_text_verts(handle, text, x, y, r, g, b, a)` | Generate text vertex data |
| `gpu.font_measure(handle, text)` | Measure text dimensions |
| `gpu.font_atlas(handle)` | Get font atlas info (texture, sampler) |
| `gpu.text_input_available()` | Check if keyboard input is pending |
| `gpu.text_input_read()` | Read next UTF-8 character from input buffer |
| `build_line_quads(lines, thickness, r, g, b, a)` | Convert line segments to quad array |
