# test_audio.sage - Sanity checks for the audio system (non-FFI parts)
# Run: ./run.sh tests/test_audio.sage

from audio import create_sound_emitter, calculate_attenuation
from audio import set_channel_volume, get_channel_volume, get_effective_volume
from audio import AudioEmitterComponent, AudioListenerComponent
from math3d import vec3

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

proc approx(a, b):
    return math.abs(a - b) < 0.05

print "=== Audio System Sanity Checks ==="

# --- Sound emitter ---
let se = create_sound_emitter("sfx", 0.8, true)
check("emitter created", se != nil)
check("emitter channel", se["channel"] == "sfx")
check("emitter volume", approx(se["volume"], 0.8))
check("emitter loop", se["loop"] == true)
check("emitter not playing", se["playing"] == false)
check("emitter min distance", se["min_distance"] > 0.0)
check("emitter max distance > min", se["max_distance"] > se["min_distance"])
check("emitter rolloff > 0", se["rolloff"] > 0.0)
check("emitter pitch", approx(se["pitch"], 1.0))

# --- Attenuation ---
# At min distance -> full volume
se["position"] = vec3(0.0, 0.0, 0.0)
se["min_distance"] = 1.0
se["max_distance"] = 50.0
se["rolloff"] = 1.0
let att1 = calculate_attenuation(se, vec3(0.0, 0.0, 0.0))
check("at source = full volume", approx(att1, 1.0))

# At min distance boundary
let att2 = calculate_attenuation(se, vec3(1.0, 0.0, 0.0))
check("at min distance = full", approx(att2, 1.0))

# Beyond max distance
let att3 = calculate_attenuation(se, vec3(100.0, 0.0, 0.0))
check("beyond max = silent", approx(att3, 0.0))

# Mid-range: should be between 0 and 1
se["position"] = vec3(0.0, 0.0, 0.0)
let att4 = calculate_attenuation(se, vec3(25.0, 0.0, 0.0))
check("mid-range attenuation between 0 and 1", att4 > 0.0 and att4 < 1.0)

# Closer = louder
let att_near = calculate_attenuation(se, vec3(5.0, 0.0, 0.0))
let att_far = calculate_attenuation(se, vec3(30.0, 0.0, 0.0))
check("closer is louder", att_near > att_far)

# --- Volume channels ---
# Test with a mock am dict
let am = {}
am["channels"] = {}
am["channels"]["master"] = 1.0
am["channels"]["music"] = 0.7
am["channels"]["sfx"] = 1.0

check("get sfx volume", approx(get_channel_volume(am, "sfx"), 1.0))
check("get music volume", approx(get_channel_volume(am, "music"), 0.7))
check("get unknown volume = 1.0", approx(get_channel_volume(am, "voice"), 1.0))

set_channel_volume(am, "sfx", 0.5)
check("set volume works", approx(am["channels"]["sfx"], 0.5))

# Clamping
set_channel_volume(am, "sfx", -0.5)
check("volume clamped low", approx(am["channels"]["sfx"], 0.0))
set_channel_volume(am, "sfx", 2.0)
check("volume clamped high", approx(am["channels"]["sfx"], 1.0))

# Effective volume (master * channel)
am["channels"]["master"] = 0.8
am["channels"]["sfx"] = 0.5
let eff = get_effective_volume(am, "sfx")
check("effective volume", approx(eff, 0.4))

am["channels"]["master"] = 0.0
let eff_muted = get_effective_volume(am, "sfx")
check("master mute = silent", approx(eff_muted, 0.0))

# --- Audio Components ---
let aec = AudioEmitterComponent("gunshot.wav", "sfx", 0.9, false)
check("audio emitter comp", aec != nil)
check("aec sound name", aec["sound_name"] == "gunshot.wav")
check("aec channel", aec["channel"] == "sfx")
check("aec volume", approx(aec["volume"], 0.9))
check("aec no loop", aec["loop"] == false)

let alc = AudioListenerComponent()
check("audio listener comp", alc != nil)
check("listener active", alc["active"] == true)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Audio sanity checks failed!"
else:
    print "All audio sanity checks passed!"
