import gpu
from renderer import create_renderer, begin_frame, end_frame

print "Creating renderer..."
let r = create_renderer(800, 600, "Test")
print "Renderer created"

print "Checking gpu module attributes..."
print "gpu.clear_color exists: " + str(dict_has(gpu, "clear_color"))
print "gpu.clear exists: " + str(dict_has(gpu, "clear"))

print "Available gpu functions:"
let keys = dict_keys(gpu)
let i = 0
while i < len(keys):
    print "  - " + keys[i]
    i = i + 1
