gc_disable()
# replay.sage — Replay Recording and Playback System
# Records input and entity states for replay, killcam, and debugging.

proc create_replay_system(tick_rate):
    return {
        "recording": false,
        "playing": false,
        "tick_rate": tick_rate,
        "frames": [],
        "current_frame": 0,
        "playback_speed": 1.0,
        "max_frames": tick_rate * 300    # 5 minutes at tick_rate
    }

proc start_recording(replay):
    replay["recording"] = true
    replay["frames"] = []
    replay["current_frame"] = 0

proc stop_recording(replay):
    replay["recording"] = false

proc record_frame(replay, frame_data):
    if not replay["recording"]:
        return
    push(replay["frames"], frame_data)
    if len(replay["frames"]) > replay["max_frames"]:
        let trimmed = []
        let i = 1
        while i < len(replay["frames"]):
            push(trimmed, replay["frames"][i])
            i = i + 1
        replay["frames"] = trimmed

proc start_playback(replay):
    replay["playing"] = true
    replay["current_frame"] = 0

proc stop_playback(replay):
    replay["playing"] = false

proc get_playback_frame(replay):
    if not replay["playing"] or replay["current_frame"] >= len(replay["frames"]):
        replay["playing"] = false
        return nil
    let frame = replay["frames"][replay["current_frame"]]
    replay["current_frame"] = replay["current_frame"] + 1
    return frame

proc set_playback_speed(replay, speed):
    replay["playback_speed"] = speed

proc seek_to(replay, frame_index):
    if frame_index >= 0 and frame_index < len(replay["frames"]):
        replay["current_frame"] = frame_index

proc replay_duration(replay):
    return len(replay["frames"]) / replay["tick_rate"]

proc replay_frame_count(replay):
    return len(replay["frames"])

proc is_recording(replay):
    return replay["recording"]

proc is_playing(replay):
    return replay["playing"]
