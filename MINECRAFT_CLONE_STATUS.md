# Minecraft Clone — Implementation Status

## Current State: ✅ FULLY PLAYABLE

The voxel sandbox is the most complete game template in Forge Engine. It provides a Minecraft-style experience with terrain generation, lit block rendering, mobs, weather, and chunk streaming.

## Feature Checklist

### World System ✅
- [x] 64x48x64 voxel world with block storage
- [x] 16-block palette (grass, dirt, stone, wood, leaves, sand, water, lava, ores)
- [x] Chunk-based storage (16x16x16) with dirty tracking
- [x] Face-culled mesh generation (only visible surfaces rendered)
- [x] Chunk streaming around player (load/unload by distance)
- [x] Procedural terrain: flat ground, stone underground, water lakes, lava pools, trees

### Rendering ✅
- [x] Full Vulkan lit rendering with directional sun + ambient + fog
- [x] Per-face surface colors from block palette (top/side/bottom)
- [x] GPU mesh upload (vertex + index buffers via upload_mesh)
- [x] Chunk pre-loading on startup (no blank first frame)
- [x] draw_mesh_lit_surface_controlled() per visible chunk
- [x] Camera matrices (view + projection) from player controller
- [x] FPS counter in window title

### Gameplay ✅
- [x] Inventory with stack tracking
- [x] Crafting recipes (wood → planks, etc.)
- [x] Tool system with durability and harvest levels
- [x] Block raycasting for mining/placing
- [x] 4 mob types: zombie, skeleton, creeper, spider
- [x] Mob spawning with population management

### Advanced ✅
- [x] Dynamic weather (clear, rain, thunderstorm, snow)
- [x] 5 biomes (Plains, Forest, Desert, Mountains, Swamp)
- [x] Ore generation (height-stratified)
- [x] Cave system generation
- [x] Mob AI with behavior trees
- [x] Fluid flow simulation (water/lava)

## Demo Files

| File | Purpose |
|------|---------|
| `examples/demo_voxel.sage` | Primary demo with full rendering |
| `examples/demo_voxel_enhanced.sage` | All systems enabled |
| `examples/voxel_game_template.sage` | Starter template |

## Run

```bash
./run.sh examples/demo_voxel.sage
```

Controls: WASD=Move | Mouse=Look | Scroll=Fly | ESC=Quit
