# build.sh - Technical Reference

## Script Architecture

### Functional Modules

```
build.sh
├── Configuration Section
│   ├── BUILD_DIR, SRC_DIR, LIB_DIR
│   ├── SAGE_FILES[], SAGE_MODULES
│   └── TARGET, BUILD_TYPE, VERBOSE
├── Utility Functions
│   ├── print_status()
│   ├── print_error()
│   ├── print_warning()
│   ├── print_info()
│   └── show_usage()
├── Argument Parsing
│   ├── Parse -j, -v, -d, -o flags
│   ├── Parse targets (engine, editor, all, clean, help)
│   └── Set JOBS, VERBOSE, BUILD_TYPE
├── Module Discovery
│   ├── discover_modules()
│   └── Populate SAGE_FILES[]
├── Build Module String
│   ├── build_module_string()
│   └── Generate SAGE_MODULES flags
├── Target Building
│   ├── build_target()
│   └── Execute sagec compiler
└── Main Orchestration
    └── main()
```

## Variable Dictionary

### Configuration Variables
| Variable | Default | Type | Purpose |
|----------|---------|------|---------|
| `BUILD_DIR` | "build" | string | Output directory for compiled binaries |
| `SRC_DIR` | "src" | string | New-structure module directory |
| `LIB_DIR` | "lib" | string | Legacy-structure module directory |
| `SAGE_FILES` | () | array | Discovered .sage files |
| `SAGE_MODULES` | "" | string | Compiler include flags (-i file) |
| `TARGET` | "engine" | string | Build target (engine/editor/all) |
| `BUILD_TYPE` | "Release" | string | Build configuration (Release/Debug) |
| `VERBOSE` | 0 | bool | Enable verbose output |

### Runtime Variables
| Variable | Used In | Purpose |
|----------|---------|---------|
| `JOBS` | Main | Number of parallel compilation jobs |
| `CLEAN` | Arg parsing | Flag to clean build artifacts |
| `main_file` | `build_target()` | Entry point .sage file for target |
| `output_name` | `build_target()` | Output binary name |
| `cmd` | `build_target()` | Assembled sagec command line |

### Color Constants
```bash
RED='\033[0;31m'      # Error messages
GREEN='\033[0;32m'    # Status messages
YELLOW='\033[1;33m'   # Warning messages
NC='\033[0m'          # No color / reset
```

## Function Reference

### Utility Functions

#### `print_status(message)`
**Purpose:** Print status message in green  
**Usage:** `print_status "Building target: engine"`  
**Output:** `[BUILD] Building target: engine` (in green)

#### `print_error(message)`
**Purpose:** Print error message in red  
**Usage:** `print_error "Module not found"`  
**Output:** `[ERROR] Module not found` (in red)

#### `print_warning(message)`
**Purpose:** Print warning message in yellow  
**Usage:** `print_warning "No modules found in lib/"`  
**Output:** `[WARN] No modules found in lib/` (in yellow)

#### `print_info(message)`
**Purpose:** Print debug info (only if VERBOSE=1)  
**Usage:** `print_info "Found: src/core/engine.sage"`  
**Output:** Shows only when `./build.sh -v`

#### `show_usage()`
**Purpose:** Display help message  
**Usage:** Called when user passes `help` or on error  
**Output:** Full usage documentation

### Core Functions

#### `discover_modules(search_dir)`
**Purpose:** Find all .sage files in a directory  
**Parameters:** 
- `search_dir`: Directory to search (e.g., "src" or "lib")

**Algorithm:**
```
1. Check if search_dir exists
2. If not, return 0 (not an error)
3. Use find to locate *.sage files
4. For each file found:
   a. Add to SAGE_FILES[]
   b. Print debug info (if VERBOSE=1)
5. If no files found, print warning
```

**Example:**
```bash
discover_modules "src"
# Scans src/ for .sage files
# Updates SAGE_FILES[] array
```

#### `build_module_string()`
**Purpose:** Generate compiler include flags from discovered modules  
**Algorithm:**
```
1. Initialize SAGE_MODULES=""
2. If src/ exists:
   a. For each file in SAGE_FILES that starts with "src/":
      - Append "-i $file" to SAGE_MODULES
3. If lib/ exists:
   a. For each file in SAGE_FILES that starts with "lib/":
      - Append "-i $file" to SAGE_MODULES
4. Result: "-i file1.sage -i file2.sage ..."
```

**Example:**
```bash
# After discovering:
# SAGE_FILES=("src/core/engine.sage" "lib/math.sage")
# Result: "-i src/core/engine.sage -i lib/math.sage"
```

#### `build_target(main_file, output_name)`
**Purpose:** Compile a target (engine/editor)  
**Parameters:**
- `main_file`: Entry point .sage file (e.g., "engine.sage")
- `output_name`: Output binary name (e.g., "sage_engine")

**Algorithm:**
```
1. Verify main_file exists
2. Assemble sagec command:
   a. Base: "sagec"
   b. Add SAGE_MODULES (include flags)
   c. Add optimization: -g if Debug
   d. Add verbosity: -v if VERBOSE=1
   e. Add output: -o BUILD_DIR/output_name
   f. Add source: main_file
3. Execute command with eval
4. Check exit code
5. Report success or failure
```

**Example Command Generated:**
```bash
sagec -i src/core/engine.sage -i lib/math.sage -g -o build/sage_engine engine.sage
```

### Main Orchestration

#### `main()`
**Purpose:** Orchestrate the entire build process  
**Flow:**
```
1. Discover modules from src/ and lib/
2. Verify at least one module found
3. Build module include string
4. Switch on TARGET:
   - "engine": build_target("engine.sage", "sage_engine")
   - "editor": build_target("editor.sage", "sage_editor")
   - "all": call both targets
5. Report completion
```

## Argument Parsing Logic

### Flag Handling
```bash
-j N          Set JOBS = N
-v            Set VERBOSE = 1
-d            Set BUILD_TYPE = "Debug"
-o DIR        Set BUILD_DIR = DIR
```

### Target Handling
```bash
engine        Set TARGET = "engine"
editor        Set TARGET = "editor"
all           Set TARGET = "all"
clean         Set CLEAN = 1, then remove BUILD_DIR
help          Show usage, exit(0)
```

### Default Values
- `JOBS`: Output of `nproc` (CPU core count)
- `TARGET`: "engine" (if not specified)
- `BUILD_TYPE`: "Release"
- `VERBOSE`: 0

## Compiler Integration

### sagec Command Structure
```bash
sagec [options] [-i module.sage] [-o output] main.sage

Options:
  -i module.sage   Include module
  -o output        Output file name
  -g               Generate debug symbols
  -v               Verbose output
  -c               Check syntax only
```

### How build.sh Constructs Commands

**Example 1: Simple Engine Build**
```bash
./build.sh engine

# Produces:
sagec -i lib/engine_math.sage -i lib/physics.sage -i lib/renderer.sage \
  -o build/sage_engine engine.sage
```

**Example 2: Debug Build with Details**
```bash
./build.sh -v -d engine

# Produces:
sagec -i lib/engine_math.sage -i lib/physics.sage -i lib/renderer.sage \
  -g -v -o build/sage_engine engine.sage
```

**Example 3: Build to Custom Directory**
```bash
./build.sh -o dist/ engine

# Produces:
sagec -i lib/engine_math.sage -i lib/physics.sage -i lib/renderer.sage \
  -o dist/sage_engine engine.sage
```

## Error Handling

### Error Conditions
```bash
# Module files not found
SAGE_FILES is empty → print_error, exit(1)

# Main file missing
engine.sage not found → print_error, exit(1)

# Unknown arguments
case *) → print_error, show_usage, exit(1)

# Build failure
sagec returns non-zero → catch with ||, exit(1)
```

### Set -e Behavior
The script uses `set -e` to exit immediately on error:
```bash
set -e
# Any command that fails will:
# 1. Stop execution
# 2. Exit the script
# 3. Return non-zero exit code to shell
```

## Performance Considerations

### Parallel Compilation
- Default: `JOBS=$(nproc || echo 4)` uses all CPU cores
- Override: `./build.sh -j 2 engine` uses 2 parallel jobs
- Note: sagec is invoked once, not in parallel (depends on compiler support)

### Module Discovery
- Uses `find` with `-print0` and process substitution
- Handles filenames with spaces correctly
- Single pass through directories

### Build Caching
- Currently: Full rebuild each time
- Future enhancement: Incremental builds with dependency tracking

## Extension Points

### Adding New Build Targets
To add a new target (e.g., `tests`):

```bash
# Add to case statement:
tests)
    if [ -f "tests/run_tests.sage" ]; then
        build_target "tests/run_tests.sage" "sage_tests" || exit 1
    fi
    ;;
```

### Adding New Compiler Flags
To add optimization flag:

```bash
# In build_target():
if [ "$OPTIMIZE" = "1" ]; then
    cmd="$cmd -O3"
fi
```

### Custom Build Hooks
Create wrapper script:

```bash
#!/bin/bash
# build_release.sh
./build.sh -j $(nproc) all
strip build/sage_*
zip release.zip build/sage_*
```

## Testing the Build System

### Basic Tests
```bash
# Test help
./build.sh help

# Test module discovery
./build.sh -v engine 2>&1 | grep "Found:"

# Test clean
./build.sh clean && [ ! -d build ] && echo "OK"

# Test default target
./build.sh && [ -f build/sage_engine ] && echo "OK"
```

### Integration Tests
```bash
# Test flags
./build.sh -v -d -j 4 engine

# Test output directory
./build.sh -o custom_build engine && [ -f custom_build/sage_engine ] && echo "OK"

# Test both targets
./build.sh all && [ -f build/sage_engine ] && [ -f build/sage_editor ] && echo "OK"
```

## Maintenance Notes

### When to Update build.sh
- ✓ Adding new modules: Automatic (discovery)
- ✓ Changing directory structure: Update `SRC_DIR`, `LIB_DIR`
- ✓ Adding compiler flags: Update `build_target()`
- ✓ New targets: Add case statement
- ✓ New options: Add flag parsing

### Version Compatibility
- Bash 4.0+: Arrays, parameter expansion
- GNU find: `-print0` for filename safety
- POSIX: Portable shell features

### Known Limitations
1. No circular dependency detection
2. No syntax validation during discovery
3. sagec invoked once per target (no parallel module compilation)
4. No incremental/cached compilation

## Related Files

- `BUILD_REFACTORING.md`: User guide and migration path
- `build.sh.bak`: Backup of previous version
- `Makefile` (if exists): Alternative/complementary build system
- `.github/workflows/`: CI/CD build scripts

