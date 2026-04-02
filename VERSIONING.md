# Forge Engine Versioning

Forge Engine uses `x.y.z` semantic versioning, with the canonical value stored in the repo-root `VERSION` file.

## Policy

- `x` is the major version.
- `y` is the minor version.
- `z` is the patch version.
- The engine stays on `0.y.z` while core engine/editor/runtime workflows are still under active construction.
- `1.0.0` is reserved for the point where the engine is broadly functional end-to-end rather than a milestone reached by calendar time.

## Source Of Truth

- `VERSION` is the only file that should contain the current release number.
- `lib/forge_version.sage` reads `VERSION` for runtime/editor branding.
- `build_dist.sh` reads and validates `VERSION` before building a distributable package.

## Bump Rules

- Increase `z` for fixes, regressions, and documentation-only polish that do not meaningfully expand engine capability.
- Increase `y` for meaningful new engine milestones such as major content-pipeline, rendering, animation, editor, or runtime/export improvements.
- Increase `x` to `1` only when Forge is ready to be treated as a fully functional engine release.
