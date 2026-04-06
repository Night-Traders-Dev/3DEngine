gc_disable()
# cutscene.sage — Cutscene / Sequencer System
# Supports: camera tracks, entity animations, dialog triggers,
# fade in/out, letterboxing, timed events, skip handling
#
# Usage:
#   let cs = create_cutscene("intro")
#   add_camera_track(cs, 0.0, cam_pos1, cam_target1)
#   add_camera_track(cs, 3.0, cam_pos2, cam_target2)
#   add_dialog_event(cs, 1.0, "narrator", "Welcome to the world...")
#   add_fade(cs, 0.0, "in", 1.0)
#   add_fade(cs, 8.0, "out", 1.5)
#   play_cutscene(cs)

from math3d import vec3, v3_add, v3_scale

# ============================================================================
# Cutscene Track Types
# ============================================================================

let TRACK_CAMERA = "camera"
let TRACK_DIALOG = "dialog"
let TRACK_FADE = "fade"
let TRACK_ENTITY_MOVE = "entity_move"
let TRACK_SOUND = "sound"
let TRACK_CALLBACK = "callback"
let TRACK_WAIT = "wait"

# ============================================================================
# Cutscene Creation
# ============================================================================

proc create_cutscene(name):
    return {
        "name": name,
        "tracks": [],
        "duration": 0.0,
        "current_time": 0.0,
        "playing": false,
        "paused": false,
        "skippable": true,
        "letterbox": true,
        "letterbox_amount": 0.12,
        "fade_alpha": 0.0,
        "fade_color": [0.0, 0.0, 0.0],
        "current_dialog": nil,
        "dialog_queue": [],
        "on_complete": nil,
        "events_fired": {}
    }

# ============================================================================
# Track Events
# ============================================================================

proc add_camera_track(cs, time, position, target):
    let track = {"type": TRACK_CAMERA, "time": time, "position": position, "target": target}
    push(cs["tracks"], track)
    if time > cs["duration"]:
        cs["duration"] = time

proc add_dialog_event(cs, time, speaker, text):
    let track = {"type": TRACK_DIALOG, "time": time, "speaker": speaker, "text": text, "duration": 3.0}
    push(cs["tracks"], track)
    if time + track["duration"] > cs["duration"]:
        cs["duration"] = time + track["duration"]

proc add_fade(cs, time, direction, fade_duration):
    let track = {"type": TRACK_FADE, "time": time, "direction": direction, "duration": fade_duration}
    push(cs["tracks"], track)
    if time + fade_duration > cs["duration"]:
        cs["duration"] = time + fade_duration

proc add_entity_move(cs, time, entity_id, start_pos, end_pos, move_duration):
    let track = {"type": TRACK_ENTITY_MOVE, "time": time, "entity": entity_id,
                 "start": start_pos, "end": end_pos, "duration": move_duration}
    push(cs["tracks"], track)
    if time + move_duration > cs["duration"]:
        cs["duration"] = time + move_duration

proc add_sound_event(cs, time, sound_id):
    push(cs["tracks"], {"type": TRACK_SOUND, "time": time, "sound": sound_id})

proc add_callback_event(cs, time, callback):
    push(cs["tracks"], {"type": TRACK_CALLBACK, "time": time, "callback": callback})

proc add_wait(cs, time, wait_duration):
    push(cs["tracks"], {"type": TRACK_WAIT, "time": time, "duration": wait_duration})
    if time + wait_duration > cs["duration"]:
        cs["duration"] = time + wait_duration

# ============================================================================
# Playback Control
# ============================================================================

proc play_cutscene(cs):
    cs["playing"] = true
    cs["paused"] = false
    cs["current_time"] = 0.0
    cs["events_fired"] = {}
    cs["fade_alpha"] = 0.0
    cs["current_dialog"] = nil

proc pause_cutscene(cs):
    cs["paused"] = true

proc resume_cutscene(cs):
    cs["paused"] = false

proc skip_cutscene(cs):
    if cs["skippable"]:
        cs["current_time"] = cs["duration"]
        cs["playing"] = false
        cs["fade_alpha"] = 0.0
        cs["current_dialog"] = nil
        if cs["on_complete"] != nil:
            cs["on_complete"]()

proc is_cutscene_playing(cs):
    return cs["playing"] and not cs["paused"]

proc cutscene_progress(cs):
    if cs["duration"] <= 0:
        return 1.0
    return cs["current_time"] / cs["duration"]

# ============================================================================
# Update — process events and interpolate tracks
# ============================================================================

proc update_cutscene(cs, dt):
    if not cs["playing"] or cs["paused"]:
        return nil

    cs["current_time"] = cs["current_time"] + dt
    let t = cs["current_time"]

    let result = {"camera_pos": nil, "camera_target": nil, "dialog": nil, "fade": cs["fade_alpha"]}

    # Process all tracks
    let ti = 0
    while ti < len(cs["tracks"]):
        let track = cs["tracks"][ti]
        let key = str(ti)

        # Camera interpolation — find the two surrounding keyframes
        if track["type"] == TRACK_CAMERA:
            if track["time"] <= t:
                result["camera_pos"] = track["position"]
                result["camera_target"] = track["target"]
                # Interpolate to next camera key
                let next_ti = ti + 1
                while next_ti < len(cs["tracks"]):
                    if cs["tracks"][next_ti]["type"] == TRACK_CAMERA:
                        let next = cs["tracks"][next_ti]
                        if next["time"] > t:
                            let range = next["time"] - track["time"]
                            let local_t = (t - track["time"]) / range
                            result["camera_pos"] = v3_add(
                                v3_scale(track["position"], 1.0 - local_t),
                                v3_scale(next["position"], local_t)
                            )
                            result["camera_target"] = v3_add(
                                v3_scale(track["target"], 1.0 - local_t),
                                v3_scale(next["target"], local_t)
                            )
                            break
                    next_ti = next_ti + 1

        # Dialog events
        if track["type"] == TRACK_DIALOG:
            if t >= track["time"] and t < track["time"] + track["duration"]:
                result["dialog"] = {"speaker": track["speaker"], "text": track["text"]}
            if not dict_has(cs["events_fired"], key) and t >= track["time"]:
                cs["events_fired"][key] = true
                cs["current_dialog"] = {"speaker": track["speaker"], "text": track["text"]}

        # Fade events
        if track["type"] == TRACK_FADE:
            if t >= track["time"] and t < track["time"] + track["duration"]:
                let progress = (t - track["time"]) / track["duration"]
                if track["direction"] == "in":
                    cs["fade_alpha"] = 1.0 - progress
                else:
                    cs["fade_alpha"] = progress
                result["fade"] = cs["fade_alpha"]
            elif t >= track["time"] + track["duration"]:
                if track["direction"] == "in":
                    cs["fade_alpha"] = 0.0
                else:
                    cs["fade_alpha"] = 1.0

        # Callback events (fire once)
        if track["type"] == TRACK_CALLBACK:
            if not dict_has(cs["events_fired"], key) and t >= track["time"]:
                cs["events_fired"][key] = true
                track["callback"]()

        ti = ti + 1

    # Check completion
    if t >= cs["duration"]:
        cs["playing"] = false
        if cs["on_complete"] != nil:
            cs["on_complete"]()

    return result
