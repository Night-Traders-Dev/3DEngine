gc_disable()
# -----------------------------------------
# audio.sage - Audio system for Sage Engine
# Uses OpenAL via FFI for 3D spatial audio
# Gracefully degrades if OpenAL is not available
# -----------------------------------------

import math
from math3d import vec3, v3_sub, v3_length, v3_normalize

# ============================================================================
# Audio Manager
# ============================================================================
proc create_audio_manager():
    let am = {}
    am["available"] = false
    am["lib"] = nil
    am["device"] = nil
    am["context"] = nil
    am["sources"] = {}
    am["buffers"] = {}
    am["next_id"] = 1
    am["listener_pos"] = vec3(0.0, 0.0, 0.0)
    am["listener_fwd"] = vec3(0.0, 0.0, -1.0)
    am["master_volume"] = 1.0
    am["music_volume"] = 0.7
    am["sfx_volume"] = 1.0
    am["channels"] = {}
    am["channels"]["master"] = 1.0
    am["channels"]["music"] = 0.7
    am["channels"]["sfx"] = 1.0
    am["channels"]["ambient"] = 0.5
    am["channels"]["voice"] = 0.9

    # Try to initialize OpenAL
    _init_openal(am)
    return am

# ============================================================================
# OpenAL initialization via FFI
# ============================================================================
proc _init_openal(am):
    try:
        let lib = ffi_open("libopenal.so.1")
        if lib == nil:
            print "Audio: OpenAL not found, audio disabled"
            return nil
        am["lib"] = lib

        # Open default device
        let device = ffi_call(lib, "alcOpenDevice", "long", [0])
        if device == nil or device == 0:
            print "Audio: Failed to open audio device"
            ffi_close(lib)
            am["lib"] = nil
            return nil
        am["device"] = device

        # Create context
        let context = ffi_call(lib, "alcCreateContext", "long", [device, 0])
        if context == nil or context == 0:
            print "Audio: Failed to create audio context"
            ffi_call(lib, "alcCloseDevice", "void", [device])
            ffi_close(lib)
            am["lib"] = nil
            return nil
        am["context"] = context

        # Make context current
        ffi_call(lib, "alcMakeContextCurrent", "int", [context])

        am["available"] = true
        print "Audio: OpenAL initialized"
    catch e:
        print "Audio: Init failed (" + str(e) + "), audio disabled"
        am["available"] = false

# ============================================================================
# Sound handle (lightweight reference)
# ============================================================================
proc _next_sound_id(am):
    let id = am["next_id"]
    am["next_id"] = id + 1
    return id

# ============================================================================
# Sound emitter (high-level, non-FFI)
# ============================================================================
proc create_sound_emitter(channel, volume, loop):
    let se = {}
    se["channel"] = channel
    se["volume"] = volume
    se["loop"] = loop
    se["playing"] = false
    se["position"] = vec3(0.0, 0.0, 0.0)
    se["min_distance"] = 1.0
    se["max_distance"] = 50.0
    se["rolloff"] = 1.0
    se["pitch"] = 1.0
    se["sound_name"] = ""
    return se

# ============================================================================
# Listener update (call each frame with camera position)
# ============================================================================
proc update_listener(am, position, forward, up):
    am["listener_pos"] = position
    am["listener_fwd"] = forward
    # Note: alListener3f requires 4 args which exceeds FFI void limit (0-1 args)
    # Listener position is tracked in software for attenuation calculations
    # Full OpenAL positional audio would need a C helper library

# ============================================================================
# Volume control
# ============================================================================
proc set_channel_volume(am, channel, volume):
    if volume < 0.0:
        volume = 0.0
    if volume > 1.0:
        volume = 1.0
    am["channels"][channel] = volume

proc get_channel_volume(am, channel):
    if dict_has(am["channels"], channel) == false:
        return 1.0
    return am["channels"][channel]

proc get_effective_volume(am, channel):
    let master = am["channels"]["master"]
    let ch = get_channel_volume(am, channel)
    return master * ch

# ============================================================================
# 3D sound attenuation (used for software mixing fallback)
# ============================================================================
proc calculate_attenuation(emitter, listener_pos):
    let dist = v3_length(v3_sub(emitter["position"], listener_pos))
    if dist <= emitter["min_distance"]:
        return 1.0
    if dist >= emitter["max_distance"]:
        return 0.0
    let range = emitter["max_distance"] - emitter["min_distance"]
    let d = dist - emitter["min_distance"]
    let rolloff = emitter["rolloff"]
    return 1.0 / (1.0 + rolloff * d / range)

# ============================================================================
# Shutdown
# ============================================================================
proc shutdown_audio(am):
    if am["available"] == false:
        return nil
    try:
        let lib = am["lib"]
        if am["context"] != nil and am["context"] != 0:
            ffi_call(lib, "alcMakeContextCurrent", "int", [0])
            ffi_call(lib, "alcDestroyContext", "void", [am["context"]])
        if am["device"] != nil and am["device"] != 0:
            ffi_call(lib, "alcCloseDevice", "int", [am["device"]])
        ffi_close(lib)
    catch e:
        print "Audio: Shutdown error: " + str(e)
    am["available"] = false
    am["lib"] = nil
    am["device"] = nil
    am["context"] = nil
    print "Audio: Shutdown complete"

# ============================================================================
# Audio Component (for ECS integration)
# ============================================================================
proc AudioEmitterComponent(sound_name, channel, volume, loop):
    let c = {}
    c["sound_name"] = sound_name
    c["channel"] = channel
    c["volume"] = volume
    c["loop"] = loop
    c["playing"] = false
    c["min_distance"] = 1.0
    c["max_distance"] = 50.0
    c["rolloff"] = 1.0
    c["pitch"] = 1.0
    return c

proc AudioListenerComponent():
    let c = {}
    c["active"] = true
    return c
