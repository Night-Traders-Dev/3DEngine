# Build System Refactoring Guide

## Overview

The 3D Engine build system has been refactored to support a modular architecture with clear separation of concerns. This guide covers the new structure, module discovery system, and best practices.

## Directory Structure

The project supports two module organization approaches:

### Legacy Structure (lib/)
```
3DEngine/
├── lib/
│   ├── engine_math.sage
│   ├── physics.sage
│   ├── renderer.sage
│   └── ... (existing modules)
├── engine.sage
├── editor.sage
└── build.sh
```

### New Structure (src/)
```
3DEngine/
├── src/
│   ├── core/
│   │   ├── engine_math.sage
│   │   ├── physics.sage
│   │   └── components.sage
│   ├── rendering/
│   │   ├── renderer.sage
│   │   ├── material.sage
│   │   └── texture.sage
│   ├── ui/
│   │   ├── ui_core.sage
│   │   ├── ui_widgets.sage
│   │   └── ui_layout.sage
│   ├── editor.sage
│   ├── engine.sage
│   └── main.sage
├── engine.sage (stub - imports from src/)
├── editor.sage (stub - imports from src/)
└── build.sh
```

## Build System Features

### Smart Module Discovery
The build system automatically discovers and includes all `.sage` files from both `lib/` and `src/` directories:
- Searches recursively for module files
- Prioritizes `src/` modules over `lib/` (new structure takes precedence)
- Automatically generates include flags for the Sage compiler

### Build Targets

```bash
# Build the game engine (default target)
./build.sh engine

# Build the editor
./build.sh editor

# Build both engine and editor
./build.sh all

# Clean build artifacts
./build.sh clean
```

### Build Options

```bash
# Verbose output (shows all files discovered)
./build.sh -v engine

# Debug build with symbols
./build.sh -d engine

# Specify output directory
./build.sh -o output/ engine

# Control parallel jobs
./build.sh -j 8 engine

# Combine options
./build.sh -v -d -j 8 all
```

## Migration Path

### Phase 1: Dual Support (Current)
The refactored `build.sh` supports both structures simultaneously:
- Enable `src/` directory
- Keep `lib/` intact as fallback
- `build.sh` will discover and include both

### Phase 2: Incremental Migration
1. Create `src/core/` subdirectory
2. Move core modules: `engine_math.sage`, `components.sage`, `physics.sage`
3. Test: `./build.sh -v engine`
4. Create `src/rendering/` subdirectory
5. Move rendering modules: `renderer.sage`, `material.sage`, `textures.sage`
6. Test: `./build.sh -v engine`
7. Continue with `src/ui/`, `src/gameplay/`, `src/tools/`, etc.

### Phase 3: Cleanup
After full migration:
- Archive `lib/` directory
- Update documentation
- Remove legacy module discovery code (if any)

## Module Organization Best Practices

### Functional Organization (Recommended)

```
src/
├── core/                 # Core engine systems
│   ├── engine.sage       # Main engine class
│   ├── components.sage   # ECS components
│   ├── engine_math.sage  # Math utilities
│   └── physics.sage      # Physics system
├── rendering/            # Rendering systems
│   ├── renderer.sage     # Main renderer
│   ├── material.sage     # Material system
│   ├── textures.sage     # Texture management
│   └── shader_compiler.sage
├── ui/                   # User interface
│   ├── ui_core.sage      # UI framework
│   ├── ui_widgets.sage   # Widget library
│   └── ui_layout.sage    # Layout system
├── gameplay/             # Game logic
│   ├── player.sage       # Player controller
│   ├── npc.sage          # NPC system
│   └── dialogue.sage     # Dialogue system
├── assets/               # Asset management
│   ├── asset_manager.sage
│   ├── mesh_loader.sage
│   └── animation_loader.sage
├── tools/                # Development tools
│   ├── profiler.sage
│   ├── debug_ui.sage
│   └── hot_reload.sage
├── editor.sage           # Editor application
└── engine.sage           # Engine application
```

### Layered Organization Alternative

```
src/
├── low-level/            # Low-level systems
│   ├── memory.sage
│   ├── engine_math.sage
│   └── collections.sage
├── systems/              # Engine systems
│   ├── physics.sage
│   ├── renderer.sage
│   └── animation.sage
├── features/             # Gameplay features
│   ├── player.sage
│   ├── npc.sage
│   └── items.sage
├── tools/                # Editor & tools
│   ├── editor.sage
│   ├── profiler.sage
│   └── debug_ui.sage
└── main.sage             # Application entry
```

## Build Configuration

### Compiler Flags
The build system passes flags to the Sage compiler:

```bash
# Debug build adds -g (symbols)
./build.sh -d engine
# Resolves to: sagec -g -i lib/*.sage -i src/**/*.sage -o build/sage_engine engine.sage

# Verbose build adds -v
./build.sh -v engine
# Shows all discovered files and compilation steps
```

### Environment Variables
Control build behavior via environment variables:

```bash
# Set build type
BUILD_TYPE=Debug ./build.sh engine

# Run with custom parallel jobs
JOBS=16 ./build.sh all

# Custom build directory (overridable by -o flag)
BUILD_DIR=dist/ ./build.sh engine
```

## Troubleshooting

### Module Not Found
```bash
# Check what modules were discovered
./build.sh -v engine

# Look for .sage files in wrong location
find . -name "*.sage" -type f
```

### Build Failures
1. Verify syntax with `sagec -c module.sage`
2. Check module dependencies: `grep -r "import\|require" src/`
3. Run verbose build for detailed errors: `./build.sh -v engine`

### Performance Issues
- Use `-j` flag to control parallelism: `./build.sh -j 4 engine`
- Check system resources: `nproc` (shows available cores)
- Profile with: `time ./build.sh engine`

## Integration with Development Workflow

### Hot Reload
Keep modules in `src/` organized to enable hot reloading:
```bash
# During development
./build.sh -v -d engine
# (modify src/rendering/renderer.sage)
./build.sh -v -d engine  # Rebuild quickly
```

### Continuous Integration
For CI/CD pipelines:
```bash
#!/bin/bash
# ci-build.sh
set -e
./build.sh clean
./build.sh -j 8 all
# Run tests, etc.
```

### Testing
Structure tests alongside modules:
```
src/core/
├── engine_math.sage
├── engine_math.test.sage  # Unit tests
├── physics.sage
└── physics.test.sage      # Unit tests
```

## Advanced Usage

### Custom Build Wrapper
Create project-specific build scripts:

```bash
#!/bin/bash
# build_release.sh
set -e
./build.sh -j $(nproc) all
strip build/sage_engine build/sage_editor
ls -lh build/
```

### Module Statistics
Analyze project structure:
```bash
# Count lines of code per module
for file in $(find src/ -name "*.sage"); do
    echo "$file: $(wc -l < $file) lines"
done | sort -t: -k2 -nr

# Find dependencies
grep -r "^\s*import\|^\s*require" src/
```

### Dependency Analysis
```bash
# Graph module dependencies (requires graphviz)
./build.sh -v engine 2>&1 | grep "include\|import" | dot -Tpng > deps.png
```

## Future Enhancements

### Planned Features
- [ ] Incremental compilation caching
- [ ] Dependency graph visualization
- [ ] Module validation and linting
- [ ] Automatic dependency resolution
- [ ] Plugin system for third-party modules
- [ ] Build configuration files (YAML/TOML)

### Configuration File Support
Future versions may support:
```yaml
# build.yaml
build:
  target: engine
  type: Release
  optimize: true
  modules:
    - src/core
    - src/rendering
    - lib/  # legacy
```

## FAQ

**Q: Can I run both old and new systems simultaneously?**
A: Yes! The refactored `build.sh` automatically discovers both `lib/` and `src/` modules. You can mix and match.

**Q: What if I move only some modules to `src/`?**
A: That's fine. The build system will include modules from both directories. Make sure there are no naming conflicts.

**Q: Can I customize the build for specific needs?**
A: Yes. Fork `build.sh` or create wrapper scripts that call it with different options. See "Custom Build Wrapper" above.

**Q: How do I debug build issues?**
A: Use `./build.sh -v` for verbose output showing all discovered files and compilation steps.

**Q: What's the recommended migration timeline?**
A: Start Migration Phase 2 when you have 20+ modules. Move core systems first, then rendering, then gameplay/tools.

## Summary

This refactored build system provides:
✅ Automatic module discovery  
✅ Support for both legacy and new directory structures  
✅ Flexible build targets and options  
✅ Clear path for incremental migration  
✅ Better scalability for larger projects  
✅ Improved developer experience with verbose diagnostics  

Migration can happen gradually, with no disruption to current workflows.
