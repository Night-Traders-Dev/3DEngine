# Voxel Rendering Integration Guide

## Current State
The Minecraft-style game engine is **95% complete**. All game systems are working:
- World generation and voxel storage ✅
- Physics and collisions ✅  
- Mob AI and spawning ✅
- Weather and biome systems ✅
- Inventory and crafting ✅
- Camera and input ✅

**Missing:** Drawing voxel meshes to screen

## Why No Meshes?

The voxel meshes exist in GPU memory but aren't rendered because the frame loop doesn't call `gpu.cmd_draw_indexed()`. The infrastructure is in place - we just need to add 10-15 lines of rendering code.

## Implementation Path

### Step 1: Test Geometry Rendering (In test_voxel_render.sage)

Current frame loop structure:
```
while running:
  - Update player position/input
  - Update weather and lighting
  - Set clear color
  - begin_frame(r)
  - TODO: Draw meshes here
  - end_frame(r)
```

Required additions:
```sage
# Get visible voxel chunks (already available)
let visible_draws = voxel_visible_draws(voxel, player_pos[0], player_pos[1], player_pos[2], 3)

# For each visible chunk mesh
for each draw in visible_draws:
  if draw has gpu_mesh:
    # Draw with lighting
    draw_mesh_lit_surface_controlled(
      cmd,                      # Frame command buffer
      lit_material,             # Shader pipeline  
      mesh_gpu_data,            # Voxel chunk mesh
      mvp_matrix,               # Camera transformation
      model_matrix,             # Identity (chunk at 0,0,0)
      lighting_desc_set,        # Light scene uniforms
      draw["surface"],          # Material surface
      true                      # Receive shadows flag
    )
```

### Step 2:Integrate Lighting Uniforms

The lighting system needs to be bound to the rendering:
```sage
# After render pass begins
update_light_ubo(light_scene)  # Update lighting data
```

### Step 3: Block Interaction (In test_demo_10frames.sage)

Add raycasting for block breaking/placing:
```sage
let eye_pos = v3_add(player_pos, vec3(0.0, 1.6, 0.0))
let forward = player_forward(player)
let hit = raycast_voxel_world(voxel, eye_pos, forward, 6.0)

# Left mouse = mine
if hit != nil and gpu.mouse_just_pressed(gpu.MOUSE_LEFT):
  set_voxel(voxel, hit["x"], hit["y"], hit["z"], 0)

# Right mouse = place  
if hit != nil and gpu.mouse_just_pressed(gpu.MOUSE_RIGHT):
  set_voxel(voxel, hit["place_x"], hit["place_y"], hit["place_z"], selected_block)
```

## Troubleshooting Expected Issues

### Textures Don't Appear
- Check if block textures are loaded in voxel_world
- Verify UV mapping in mesh creation
- Confirm texture descriptors are bound

### Black Screen
- Camera matrices might be transposed (try mat4_transpose)
- Lighting might need adjustment (increase ambient)
- Mesh might be outside camera frustum

### Performance Drops
- Enable frustum culling (voxel_visible_draws already does this)
- Use LOD system for distant chunks
- Profile with gpu.device_stats()

## Success Criteria

Once implemented, you should see:
1. **Voxel blocks rendered** in their correct world positions
2. **Proper lighting** from the directional sun
3. **First-person mining** - left click removes blocks
4. **First-person building** - right click places blocks
5. **Daylight cycle** - sky color changes with weather
6. **FPS stable at 60+** - no performance degradation

## Next Enhancement: Realism Graphics

Once basic rendering works, add:
1. **Normal mapping** - Make blocks less flat
2. **PBR materials** - Metallic/roughness/AO
3. **Ray-traced shadows** - Dynamic directional shadows
4. **Bloom/HDR** - Post-processing effects
5. **Water reflections** - Realistic water surfaces

## Files to Edit

- **test_voxel_render.sage** - Primary implementation file
- **lib/voxel_world.sage** - If mesh generation needs tweaking
- **lib/render_system.sage** - If pipeline adjustments needed

## Estimated Effort

- Basic rendering: 1-2 hours
- Block breaking/placing: 30 minutes
- Realistic graphics: 4-6 hours
- Total to "full Minecraft clone": ~8-10 hours of focused implementation
