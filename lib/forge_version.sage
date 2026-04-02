gc_disable()
# -----------------------------------------
# forge_version.sage - Shared Forge Engine version helpers
# Single source of truth for engine branding and release version strings
# -----------------------------------------

import io

let ENGINE_NAME = "Forge Engine"
let ENGINE_VERSION_FILE = "VERSION"
let SCENE_FORMAT_VERSION = 1

let _cached_engine_version = nil

proc _load_engine_version():
    if _cached_engine_version != nil:
        return _cached_engine_version

    let raw = io.readfile(ENGINE_VERSION_FILE)
    if raw == nil:
        _cached_engine_version = "unknown"
        return _cached_engine_version

    let parsed = strip(raw)
    if parsed == "":
        _cached_engine_version = "unknown"
    else:
        _cached_engine_version = parsed
    return _cached_engine_version

proc engine_name():
    return ENGINE_NAME

proc engine_version():
    return _load_engine_version()

proc engine_banner():
    return ENGINE_NAME + " v" + engine_version()

proc editor_title():
    return ENGINE_NAME + " Editor"

proc editor_play_title():
    return editor_title() + " | PLAYING"

proc about_text(gpu_name):
    return engine_banner() + " | GPU: " + gpu_name + " | SageLang + Vulkan"

proc scene_format_version():
    return SCENE_FORMAT_VERSION
