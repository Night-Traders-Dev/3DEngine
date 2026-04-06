# Test just the initialization part of the demo
import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from player_controller import create_player_controller, player_forward

print "=== Testing Basic Initialization ==="

# Initialize systems
let r = create_renderer(1280, 720, "Test")
if r == nil:
    raise "Failed to create renderer"
print "✓ Renderer created"

let inp = create_input()
default_fps_bindings(inp)
print "✓ Input created"

let player = create_player_controller()
let player_pos = vec3(32.0, 30.0, 32.0)
player["position"] = player_pos
print "✓ Player created"

print "✓ Basic systems initialized"
shutdown_renderer(r)
print "✓ Test completed successfully"