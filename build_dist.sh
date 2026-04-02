#!/bin/bash
# build_dist.sh - Build a distributable Forge Engine package
# Creates a self-contained directory with the sage runtime + all engine files
#
# Output: build/dist/  (ready to zip/tar and distribute)
# Run:    build/dist/forge_engine [script]  (default: editor)

set -e

SAGE_DIR="$(cd "$(dirname "$0")/../sagelang" && pwd)"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST="$ENGINE_DIR/build/dist"
VERSION_FILE="$ENGINE_DIR/VERSION"
ENGINE_VERSION="unknown"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: VERSION file not found at $VERSION_FILE"
    exit 1
fi

ENGINE_VERSION="$(tr -d '\r\n' < "$VERSION_FILE")"
if [[ ! "$ENGINE_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Error: VERSION must use x.y.z semantic versioning (found '$ENGINE_VERSION')"
    exit 1
fi

echo "=== Forge Engine Build ==="
echo "Engine: $ENGINE_DIR"
echo "Version: $ENGINE_VERSION"
if [[ "$ENGINE_VERSION" =~ ^0\. ]]; then
    echo "Stage: pre-1.0.0 development release"
else
    echo "Stage: stable release"
fi
echo "SageLang: $SAGE_DIR"

# Ensure sage is built
if [ ! -f "$SAGE_DIR/sage" ]; then
    echo "Building SageLang..."
    (cd "$SAGE_DIR" && make -j$(nproc))
fi

# Clean and create dist directory
rm -rf "$DIST"
mkdir -p "$DIST"
mkdir -p "$DIST/lib"
mkdir -p "$DIST/assets"
mkdir -p "$DIST/shaders"
mkdir -p "$DIST/examples"

# Copy sage runtime binary
cp "$SAGE_DIR/sage" "$DIST/sage"

# Copy SageLang standard library (needed at runtime for imports)
if [ -d "$SAGE_DIR/lib" ]; then
    mkdir -p "$DIST/stdlib"
    cp "$SAGE_DIR"/lib/*.sage "$DIST/stdlib/"
fi

# Copy engine library modules
echo "Copying engine libraries..."
cp "$ENGINE_DIR"/lib/*.sage "$DIST/lib/"

# Copy engine entry points
cp "$ENGINE_DIR/editor.sage" "$DIST/"
cp "$ENGINE_DIR/VERSION" "$DIST/"
cp "$ENGINE_DIR"/examples/*.sage "$DIST/examples/" 2>/dev/null || true

# Copy assets
echo "Copying assets..."
cp "$ENGINE_DIR"/assets/*.ttf "$DIST/assets/" 2>/dev/null || true
cp "$ENGINE_DIR"/assets/*.png "$DIST/assets/" 2>/dev/null || true
cp "$ENGINE_DIR"/assets/*.gltf "$DIST/assets/" 2>/dev/null || true
cp "$ENGINE_DIR"/assets/*.bin "$DIST/assets/" 2>/dev/null || true
cp "$ENGINE_DIR"/assets/*.json "$DIST/assets/" 2>/dev/null || true
if [ -d "$ENGINE_DIR/assets/prefabs" ]; then
    cp -r "$ENGINE_DIR/assets/prefabs" "$DIST/assets/"
fi

# Copy compiled shaders
echo "Copying shaders..."
cp "$ENGINE_DIR"/shaders/*.spv "$DIST/shaders/" 2>/dev/null || true
cp "$ENGINE_DIR"/shaders/*.vert "$DIST/shaders/" 2>/dev/null || true
cp "$ENGINE_DIR"/shaders/*.frag "$DIST/shaders/" 2>/dev/null || true

# Create launcher script
cat > "$DIST/forge_engine" << 'LAUNCHER'
#!/bin/bash
# Forge Engine Launcher
DIR="$(cd "$(dirname "$0")" && pwd)"
SAGE="$DIR/sage"
SCRIPT="${1:-editor.sage}"

if [ ! -f "$SAGE" ]; then
    echo "Error: sage runtime not found at $SAGE"
    exit 1
fi

cd "$DIR"
exec "$SAGE" "$SCRIPT"
LAUNCHER
chmod +x "$DIST/forge_engine"

# Summary
echo ""
echo "=== Build Complete ==="
TOTAL_SAGE=$(find "$DIST" -name "*.sage" | wc -l)
TOTAL_SIZE=$(du -sh "$DIST" | cut -f1)
echo "Output:  $DIST"
echo "Files:   $TOTAL_SAGE .sage modules"
echo "Size:    $TOTAL_SIZE"
echo ""
echo "Run:     cd build/dist && ./forge_engine"
echo "Package: tar -czf forge_engine-$ENGINE_VERSION.tar.gz -C build dist"
