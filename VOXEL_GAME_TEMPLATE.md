# Voxel Game Template

This template provides a complete starting point for creating voxel-based games with the Forge Engine. It includes all the essential systems: world generation, player controls, mob AI, weather, fluids, and inventory management.

## Features Included

- **Voxel World System**: 64x48x64 block world with 15+ block types
- **Player Controller**: WASD movement, mouse look, scroll for vertical movement
- **Mob System**: AI-controlled mobs with behavior trees (zombies, skeletons, creepers, spiders)
- **Weather System**: Dynamic weather transitions (clear, rain, thunderstorm)
- **Fluid Physics**: Water and lava with realistic flow mechanics
- **Inventory & Crafting**: Block collection, tool usage, and recipe crafting
- **Biome System**: Multiple terrain types with different generation rules

## Getting Started

1. **Copy the template**:
   ```bash
   cp examples/voxel_game_template.sage my_game.sage
   ```

2. **Customize the configuration** at the top of the file:
   ```sage
   let GAME_TITLE = "My Awesome Game"
   let WORLD_SIZE_X = 128  # Larger world
   let ENABLE_MOBS = false  # Disable for peaceful mode
   ```

3. **Modify world generation** in the `generate_world()` function:
   - Add custom terrain features
   - Create structures, caves, or landscapes
   - Implement procedural generation algorithms

4. **Add gameplay mechanics**:
   - Custom tools and items
   - New mob types and behaviors
   - Mini-games or objectives
   - Multiplayer support

5. **Customize rendering** in the game loop:
   - Add particle effects
   - Implement custom shaders
   - Create UI elements
   - Add post-processing effects

## Key Functions to Customize

### World Generation
```sage
proc generate_world(world):
    # Add your terrain generation logic here
    # Examples: mountains, caves, villages, dungeons
```

### Game Logic
```sage
# In the main game loop:
# Add custom game mechanics
# Handle player interactions
# Update game state
# Check win/lose conditions
```

### Rendering
```sage
# In the rendering section:
# Draw custom elements
# Add visual effects
# Render UI overlays
```

## Advanced Features

### Adding New Block Types
```sage
# In voxel_world.sage, add to the palette
# Then use set_voxel() to place them
```

### Creating Custom Mobs
```sage
# Extend voxel_gameplay.sage
# Add new mob types to spawn_voxel_mob()
# Create custom AI behaviors in voxel_mobai.sage
```

### Weather Effects
```sage
# Modify voxel_weather.sage
# Add new weather types
# Implement custom visual effects
```

## Example Customizations

### Peaceful Building Game
```sage
let ENABLE_MOBS = false
let ENABLE_WEATHER = true
# Focus on building and exploration
```

### Survival Horror
```sage
let MAX_MOBS = 50
let ENABLE_WEATHER = true
# Add darkness mechanics, limited resources
```

### Creative Mode
```sage
let ENABLE_FLUIDS = false
# Unlimited resources, no mob spawning
```

## Running the Template

```bash
# From the 3DEngine directory
./run.sh examples/voxel_game_template.sage
```

## Dependencies

This template requires all the voxel system modules:
- `voxel_world.sage` - Core world management
- `voxel_gameplay.sage` - Tools, mobs, inventory
- `voxel_mobai.sage` - AI behaviors
- `voxel_weather.sage` - Weather system
- `voxel_fluids.sage` - Fluid physics
- `voxel_biomes.sage` - Terrain generation
- `voxel_hud.sage` - UI display

Additionally, rendering requires:
- `renderer.sage` - Vulkan swapchain and frame management
- `lighting.sage` - Directional light, ambient, fog
- `render_system.sage` - Lit material pipeline and draw functions
- `math3d.sage` - Vector/matrix math
- `player_controller.sage` - FPS camera with view/projection matrices

Make sure all these files are present in the `lib/` directory.