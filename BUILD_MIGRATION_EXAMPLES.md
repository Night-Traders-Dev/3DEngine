# build.sh Migration Examples

## Quick Start: Using Current System

You don't need to change anything right away. The new `build.sh` works with existing `lib/` structure:

```bash
# Current workflow - just works!
cd /path/to/3DEngine
./build.sh engine      # Builds engine from lib/
./build.sh editor      # Builds editor from lib/
./build.sh all         # Builds both
./build.sh clean       # Clean build/
```

All your existing `.sage` files in `lib/` will be automatically discovered and included.

## Gradual Migration: Moving to src/

### Step 1: Create src/ Directory Structure

```bash
cd /path/to/3DEngine

# Create new directory structure
mkdir -p src/core
mkdir -p src/rendering
mkdir -p src/ui
mkdir -p src/gameplay
mkdir -p src/tools
```

### Step 2: Move Core Module Group

Move fundamental systems first (they have fewest dependencies):

```bash
# Move core systems
mv lib/engine_math.sage src/core/
mv lib/components.sage src/core/
mv lib/ecs.sage src/core/
mv lib/utils.sage src/core/

# Test the build
./build.sh -v engine

# You should see output like:
# [BUILD] Scanning src/ for module files...
# [BUILD] Found: src/core/engine_math.sage
# [BUILD] Found: src/core/components.sage
# [BUILD] Found: src/core/ecs.sage
# [BUILD] Found: src/core/utils.sage
# [BUILD] Found 4 module file(s)
# [BUILD] Scanning lib/ for module files...
# ... (remaining lib/ files) ...
```

If the build succeeds, you've successfully moved your first module group!

### Step 3: Move Rendering Systems

```bash
# Move rendering modules
mv lib/renderer.sage src/rendering/
mv lib/material.sage src/rendering/
mv lib/textures.sage src/rendering/
mv lib/shader_compiler.sage src/rendering/
mv lib/pbr.sage src/rendering/
mv lib/mesh.sage src/rendering/

# Test again
./build.sh -v engine
```

### Step 4: Move UI Systems

```bash
# Move UI modules
mv lib/ui_core.sage src/ui/
mv lib/ui_widgets.sage src/ui/
mv lib/ui_window.sage src/ui/
mv lib/ui_layout.sage src/ui/
mv lib/ui_renderer.sage src/ui/
mv lib/ui_text.sage src/ui/

# Test
./build.sh -v engine
```

### Step 5: Move Gameplay and Tools

```bash
# Move gameplay
mkdir -p src/gameplay
mv lib/player_controller.sage src/gameplay/
mv lib/npc.sage src/gameplay/
mv lib/dialogue.sage src/gameplay/

# Move tools
mkdir -p src/tools
mv lib/debug_ui.sage src/tools/
mv lib/profiler.sage src/tools/
mv lib/hot_reload.sage src/tools/

# Final test
./build.sh -v engine
```

### Step 6: Verify and Archive Legacy Structure

```bash
# Check what's left in lib/
ls lib/

# Archive the old structure (keep as backup)
tar czf lib_archive.tar.gz lib/

# Remove old directory after confirming archive
find lib -name "*.sage" -type f | wc -l  # Count remaining files
```

## Example: Complete Migration Session

Here's a complete session showing the migration process:

```bash
#!/bin/bash
# migrate_to_src.sh - Complete migration script

set -e

PROJECT_DIR="/path/to/3DEngine"
cd "$PROJECT_DIR"

echo "=== Starting Migration to src/ Structure ==="

# Create directory structure
echo "Creating src/ directories..."
mkdir -p src/core
mkdir -p src/rendering
mkdir -p src/ui
mkdir -p src/gameplay
mkdir -p src/assets
mkdir -p src/tools
mkdir -p src/editor

# Phase 1: Core modules (no dependencies)
echo "Moving core modules..."
for module in engine_math.sage components.sage ecs.sage utils.sage arrays.sage dicts.sage iter.sage assert.sage strings.sage; do
    [ -f "lib/$module" ] && mv "lib/$module" "src/core/" && echo "  ✓ $module"
done

# Verify build
echo "Testing build..."
./build.sh -v engine >/dev/null 2>&1 && echo "  ✓ Build successful" || { echo "  ✗ Build failed"; exit 1; }

# Phase 2: Rendering modules
echo "Moving rendering modules..."
for module in renderer.sage material.sage textures.sage gpu.sage mesh.sage pbr.sage deferred.sage shadow_map.sage shadows.sage lighting.sage sky.sage water.sage pbr_material.sage post_fx.sage postprocess.sage render_system.sage particle_renderer.sage; do
    [ -f "lib/$module" ] && mv "lib/$module" "src/rendering/" && echo "  ✓ $module"
done

./build.sh -v engine >/dev/null 2>&1 && echo "  ✓ Build successful" || { echo "  ✗ Build failed"; exit 1; }

# Phase 3: UI modules
echo "Moving UI modules..."
for module in ui_core.sage ui_widgets.sage ui_window.sage ui_layout.sage ui_renderer.sage ui_text.sage hud.sage menu.sage; do
    [ -f "lib/$module" ] && mv "lib/$module" "src/ui/" && echo "  ✓ $module"
done

./build.sh -v engine >/dev/null 2>&1 && echo "  ✓ Build successful" || { echo "  ✗ Build failed"; exit 1; }

# Phase 4: Gameplay modules
echo "Moving gameplay modules..."
for module in player_controller.sage gameplay.sage input.sage events.sage behavior_tree.sage navigation.sage; do
    [ -f "lib/$module" ] && mv "lib/$module" "src/gameplay/" && echo "  ✓ $module"
done

./build.sh -v engine >/dev/null 2>&1 && echo "  ✓ Build successful" || { echo "  ✗ Build failed"; exit 1; }

# Phase 5: Asset modules
echo "Moving asset modules..."
for module in asset_manager.sage asset_browser.sage asset_import.sage asset_cache.sage gltf.sage gltf_import.sage; do
    [ -f "lib/$module" ] && mv "lib/$module" "src/assets/" && echo "  ✓ $module"
done

./build.sh -v engine >/dev/null 2>&1 && echo "  ✓ Build successful" || { echo "  ✗ Build failed"; exit 1; }

# Phase 6: Tools and Development
echo "Moving tool modules..."
for module in debug_ui.sage profiler.sage hot_reload.sage undo_redo.sage; do
    [ -f "lib/$module" ] && mv "lib/$module" "src/tools/" && echo "  ✓ $module"
done

./build.sh -v engine >/dev/null 2>&1 && echo "  ✓ Build successful" || { echo "  ✗ Build failed"; exit 1; }

# Archive remaining lib/ directory
echo "Archiving legacy lib/ directory..."
[ -d lib ] && tar czf lib_archive_$(date +%Y%m%d_%H%M%S).tar.gz lib && echo "  ✓ Created lib_archive.tar.gz"

# Summary
echo ""
echo "=== Migration Complete ==="
echo "✓ Modules organized in src/ subdirectories"
echo "✓ Builds passing at each stage"
echo "✓ Legacy lib/ archived"
echo ""
echo "New structure:"
tree src/ -L 2 2>/dev/null || find src/ -type d | head -20
```

Run with: `bash migrate_to_src.sh`

## Rollback Procedure

If something goes wrong during migration:

```bash
# 1. Check git status
git status

# 2. Restore from archive
tar xzf lib_archive_20240101_120000.tar.gz

# 3. Verify build
./build.sh engine

# 4. Remove src/ directory if needed
rm -rf src/
```

Or use git to undo:
```bash
# Undo all file moves
git checkout HEAD -- .

# Verify
./build.sh engine
```

## Validation Checklist

After each phase, verify:

- [ ] Build completes: `./build.sh engine`
- [ ] No errors: Check return code `echo $?` (should be 0)
- [ ] All modules discovered: `./build.sh -v engine | grep "Found:"`
- [ ] Output binary exists: `[ -f build/sage_engine ] && echo "OK"`
- [ ] Editor builds: `./build.sh editor`

Example validation script:

```bash
#!/bin/bash
# validate_migration.sh

validate() {
    echo "Validating build for target: $1"
    
    # Clean and build
    ./build.sh clean
    ./build.sh "$1" || { echo "✗ Build failed"; return 1; }
    
    # Check output
    [ -f "build/sage_$1" ] || { echo "✗ Binary not found"; return 1; }
    
    echo "✓ $1 validation passed"
}

validate "engine"
validate "editor"

# Summary
echo ""
echo "=== Validation Complete ==="
du -sh build/
```

## Undoing Accidental Clean

If you accidentally run `./build.sh clean`:

```bash
# The script only removes build/, not src/ or lib/
# Just rebuild:
./build.sh engine

# If you need git history:
git logs --oneline -- '<script>' | head -5
git checkout <commit> -- '<filename>'
```

## Performance Comparison

### Before Migration (lib/)
```bash
$ time ./build.sh engine
Build target: sage_engine
... compilation output ...
real    0m2.345s
user    0m1.234s
sys     0m0.456s
```

### After Migration (src/)
Build time should be identical since discovery is fast. Check:

```bash
# Detailed timing
time ./build.sh -v engine

# Module count
./build.sh -v engine 2>&1 | grep -c "Found:"
```

## Interactive Migration

Step through migration interactively:

```bash
#!/bin/bash
# migrate_interactive.sh

for phase in core rendering ui gameplay assets tools; do
    echo ""
    echo "=== Migrate $phase modules? ==="
    read -p "Press Enter to continue, Ctrl+C to skip..."
    
    # Move files for this phase...
    # Test build...
    # Wait for confirmation...
done
```

## Troubleshooting Migration Issues

### Issue: Build fails after moving modules

```bash
# 1. Check what modules were moved
find src/ -name "*.sage" | head -20

# 2. Check build output with verbose
./build.sh -v engine 2>&1 | head -50

# 3. Check module locations
find . -name "*.sage" -type f | sort
```

### Issue: Circular dependencies

```bash
# Check for import loops
grep -r "^\s*import\|^\s*require" src/

# Create dependency graph (requires graphviz):
# for file in $(find src -name "*.sage"); do
#   echo "$file:"
#   grep "import\|require" "$file"
# done
```

### Issue: Missing modules after move

```bash
# List all .sage files
find . -name "*.sage" -type f | wc -l

# Compare before/after
ls lib/*.sage 2>/dev/null | wc -l  # Count in lib/
find src -name "*.sage" -type f | wc -l  # Count in src/
```

## Documenting Your Migration

After migration, update your project:

```markdown
# Project Structure - Post Migration

## Directory Organization

src/
├── core/        - ECS, math, utilities
├── rendering/   - Graphics pipeline
├── ui/          - UI framework and widgets
├── gameplay/    - Game logic
├── assets/      - Asset management
└── tools/       - Development tools

## Build Commands

# Build engine with new structure
./build.sh engine

# Build with debug info
./build.sh -d engine

# Build everything
./build.sh all
```

Save this in README or ARCHITECTURE.md

