#!/bin/bash

# 3D Engine Build Script
# Supports both old lib/ structure and new src/ structure
# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BUILD_DIR="build"
SRC_DIR="src"
LIB_DIR="lib"
SAGE_FILES=()
SAGE_MODULES=""  # Module include string for sagec
TARGET=""
BUILD_TYPE="${BUILD_TYPE:-Release}"
VERBOSE="${VERBOSE:-0}"

# Print utility functions
print_status() {
    echo -e "${GREEN}[BUILD]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_info() {
    if [ "$VERBOSE" = "1" ]; then
        echo -e "${NC}[INFO]${NC} $1"
    fi
}

# Show usage
show_usage() {
    cat << 'EOF'
Usage: ./build.sh [OPTIONS] [TARGET]

Targets:
  engine          Build the game engine (default)
  editor          Build the editor
  all             Build engine and editor
  clean           Clean build artifacts
  help            Show this help message

Options:
  -j N            Number of parallel jobs (default: auto-detect)
  -v              Verbose output
  -d              Debug build (default is Release)
  -o DIR          Output directory (default: build/)

Module Discovery:
  Searches for .sage files in lib/ (legacy) and src/ (new)
  Automatically includes all modules in the build
EOF
}

# Parse command-line arguments
JOBS=$(nproc || echo 4)
CLEAN=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -j)
            JOBS=$2
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -d|--debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        -o)
            BUILD_DIR=$2
            shift 2
            ;;
        clean)
            CLEAN=1
            TARGET="clean"
            shift
            ;;
        engine)
            TARGET="engine"
            shift
            ;;
        editor)
            TARGET="editor"
            shift
            ;;
        all)
            TARGET="all"
            shift
            ;;
        help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Default target is engine
if [ -z "$TARGET" ]; then
    TARGET="engine"
fi

print_status "3D Engine Build System"
print_status "Build Type: $BUILD_TYPE"
print_status "Jobs: $JOBS"
print_status "Build Dir: $BUILD_DIR"

# Handle clean
if [ "$CLEAN" = "1" ]; then
    print_status "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    print_status "Clean complete"
    exit 0
fi

# Create build directory if it doesn't exist
if [ ! -d "$BUILD_DIR" ]; then
    print_status "Creating build directory: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
fi

# Discover .sage module files
discover_modules() {
    local search_dir=$1
    local found_any=0
    
    if [ ! -d "$search_dir" ]; then
        return 0
    fi
    
    print_status "Scanning $search_dir for module files..."
    
    # Find all .sage files in the directory and subdirectories (excluding examples and tests)
    while IFS= read -r -d '' file; do
        found_any=1
        SAGE_FILES+=("$file")
        print_info "  Found: $file"
    done < <(find "$search_dir" -name "*.sage" -type f -print0 | sort -z)
    
    if [ "$found_any" = "0" ]; then
        print_warning "No .sage files found in $search_dir"
    fi
}

# Build module include string for sagec
build_module_string() {
    SAGE_MODULES=""
    
    # Add src/ files first (if they exist) - new structure takes precedence
    if [ -d "$SRC_DIR" ]; then
        for file in "${SAGE_FILES[@]}"; do
            if [[ "$file" == "$SRC_DIR"* ]]; then
                SAGE_MODULES="$SAGE_MODULES -i $file"
            fi
        done
    fi
    
    # Add lib/ files (legacy structure)
    if [ -d "$LIB_DIR" ]; then
        for file in "${SAGE_FILES[@]}"; do
            if [[ "$file" == "$LIB_DIR"* ]]; then
                SAGE_MODULES="$SAGE_MODULES -i $file"
            fi
        done
    fi
}

# Build a specific target
build_target() {
    local main_file=$1
    local output_name=$2
    
    if [ ! -f "$main_file" ]; then
        print_error "Main file not found: $main_file"
        return 1
    fi
    
    print_status "Building target: $output_name from $main_file"
    
    # Run sagec compiler with discovered modules
    local cmd="sagec"
    
    # Add module includes
    if [ ! -z "$SAGE_MODULES" ]; then
        cmd="$cmd $SAGE_MODULES"
    fi
    
    # Add compilation flags
    if [ "$BUILD_TYPE" = "Debug" ]; then
        cmd="$cmd -g"
    fi
    
    if [ "$VERBOSE" = "1" ]; then
        cmd="$cmd -v"
    fi
    
    # Add output and source
    cmd="$cmd -o $BUILD_DIR/$output_name $main_file"
    
    print_info "Command: $cmd"
    
    if eval "$cmd"; then
        print_status "Successfully built: $output_name"
        return 0
    else
        print_error "Build failed for: $output_name"
        return 1
    fi
}

# Main build logic
main() {
    # Discover all modules from src/ and lib/
    discover_modules "$SRC_DIR"
    discover_modules "$LIB_DIR"
    
    if [ ${#SAGE_FILES[@]} -eq 0 ]; then
        print_error "No module files (.sage) found in $SRC_DIR/ or $LIB_DIR/"
        exit 1
    fi
    
    print_status "Found ${#SAGE_FILES[@]} module file(s)"
    
    # Build module include string
    build_module_string
    
    # Execute build targets
    case $TARGET in
        engine)
            if [ -f "engine.sage" ]; then
                build_target "engine.sage" "sage_engine" || exit 1
            elif [ -f "$SRC_DIR/engine.sage" ]; then
                build_target "$SRC_DIR/engine.sage" "sage_engine" || exit 1
            else
                print_error "engine.sage not found in root or $SRC_DIR/"
                exit 1
            fi
            ;;
        editor)
            if [ -f "editor.sage" ]; then
                build_target "editor.sage" "sage_editor" || exit 1
            elif [ -f "$SRC_DIR/editor.sage" ]; then
                build_target "$SRC_DIR/editor.sage" "sage_editor" || exit 1
            else
                print_error "editor.sage not found in root or $SRC_DIR/"
                exit 1
            fi
            ;;
        all)
            # Build engine
            if [ -f "engine.sage" ]; then
                build_target "engine.sage" "sage_engine" || exit 1
            elif [ -f "$SRC_DIR/engine.sage" ]; then
                build_target "$SRC_DIR/engine.sage" "sage_engine" || exit 1
            fi
            
            # Build editor
            if [ -f "editor.sage" ]; then
                build_target "editor.sage" "sage_editor" || exit 1
            elif [ -f "$SRC_DIR/editor.sage" ]; then
                build_target "$SRC_DIR/editor.sage" "sage_editor" || exit 1
            fi
            ;;
        *)
            print_error "Unknown target: $TARGET"
            show_usage
            exit 1
            ;;
    esac
    
    print_status "Build complete!"
}

# Run main function
main
