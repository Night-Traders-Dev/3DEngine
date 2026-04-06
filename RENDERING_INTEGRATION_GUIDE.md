# Rendering Integration Guide

## Architecture

Forge Engine uses a Vulkan-based forward rendering pipeline with optional deferred and HDR paths.

### Rendering Pipeline

```
begin_frame(r)                        # Acquire swapchain image, begin command buffer
├── cmd_begin_render_pass()           # Color + depth clear
├── cmd_set_viewport/scissor()        # Set render area
│
├── draw_sky(sky, cmd, view, ...)     # Sky dome (optional)
│
├── For each visible entity:          # Scene geometry
│   └── draw_mesh_lit(cmd, mat, mesh, mvp, model, desc_set)
│       ├── cmd_bind_graphics_pipeline()
│       ├── cmd_bind_descriptor_set()   # Lighting UBO
│       ├── cmd_push_constants()        # MVP + model + color
│       ├── cmd_bind_vertex_buffer()
│       ├── cmd_bind_index_buffer()
│       └── cmd_draw_indexed()
│
├── draw_ui(cmd, ui_renderer)         # HUD overlay (optional)
│
end_frame(r, frame)                   # End render pass, submit, present
```

### Required Setup

```sage
import gpu
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize
from lighting import create_light_scene, directional_light, add_light
from lighting import set_ambient, set_fog, set_view_position, init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from mesh import upload_mesh, cube_mesh

# Init
let r = create_renderer(1280, 720, "My Game")
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.8, 0.5, 1.0, 0.95, 0.85, 1.4))
set_ambient(ls, 0.2, 0.22, 0.28, 0.4)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
let mesh_gpu = upload_mesh(cube_mesh())
```

### Frame Loop

```sage
while running:
    set_view_position(ls, camera_pos)
    update_light_ubo(ls)

    let frame = begin_frame(r)
    if frame == nil:
        check_resize(r)
        continue
    let cmd = frame["cmd"]

    draw_mesh_lit(cmd, lit_mat, mesh_gpu, mvp, model, ls["desc_set"])

    end_frame(r, frame)
    check_resize(r)
```

### Voxel Rendering

For voxel worlds, use `voxel_visible_draws()` which returns pre-uploaded GPU meshes:

```sage
from voxel_world import voxel_visible_draws
from render_system import draw_mesh_lit_surface_controlled

let visible = voxel_visible_draws(voxel, px, py, pz, chunk_radius)
let vi = 0
while vi < len(visible):
    let draw = visible[vi]
    draw_mesh_lit_surface_controlled(cmd, lit_mat, draw["gpu_mesh"],
        mvp, model, ls["desc_set"], draw["surface"], true)
    vi = vi + 1
```

### Material Types

| Material | Function | Use Case |
|----------|----------|----------|
| Lit | `create_lit_material()` | Standard PBR with shadows |
| Unlit | `create_unlit_material()` | UI, debug, wireframe |
| PBR | `create_pbr_material_from_imported()` | glTF imported assets |
| Sky | `init_sky_gpu()` | Procedural sky dome |

### Shadow Mapping

```sage
from shadow_map import create_shadow_renderer, begin_shadow_frame, end_shadow_frame

let shadow = create_shadow_renderer(r, 2048)
# In render loop, before main pass:
begin_shadow_frame(shadow, sun_direction, camera_pos)
shadow_draw_mesh(shadow, mesh_gpu, model)
end_shadow_frame(shadow)
set_lit_material_shadow_source(lit_mat, shadow)
```
