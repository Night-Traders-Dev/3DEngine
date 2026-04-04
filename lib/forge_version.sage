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

proc _is_digit(ch):
    return ch == "0" or ch == "1" or ch == "2" or ch == "3" or ch == "4" or ch == "5" or ch == "6" or ch == "7" or ch == "8" or ch == "9"

proc _is_numeric_part(text):
    if text == "":
        return false
    if len(text) > 1 and text[0] == "0":
        return false
    let i = 0
    while i < len(text):
        if _is_digit(text[i]) == false:
            return false
        i = i + 1
    return true

proc is_semver(version):
    let parts = split(version, ".")
    if len(parts) != 3:
        return false
    return _is_numeric_part(parts[0]) and _is_numeric_part(parts[1]) and _is_numeric_part(parts[2])

proc is_engine_version_semver():
    return is_semver(engine_version())

proc is_pre_1_0_release():
    if is_engine_version_semver() == false:
        return false
    let parts = split(engine_version(), ".")
    return parts[0] == "0"

proc version_policy_text():
    if is_pre_1_0_release():
        return "pre-1.0.0 development release"
    return "stable release"

proc engine_banner():
    return ENGINE_NAME + " v" + engine_version()

proc editor_title():
    return ENGINE_NAME + " Editor"

proc editor_play_title():
    return editor_title() + " | PLAYING"

proc about_text(gpu_name):
    return engine_banner() + " | " + version_policy_text() + " | GPU: " + gpu_name + " | SageLang + Vulkan"

proc scene_format_version():
    return SCENE_FORMAT_VERSION
