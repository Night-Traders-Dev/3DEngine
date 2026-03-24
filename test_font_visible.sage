import gpu
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer
from font import create_font_renderer, load_font, draw_text
from ui_renderer import create_ui_renderer, draw_ui
from ui_core import create_widget, create_rect, add_child

let r = create_renderer(800, 600, "Font Visibility Test")
r["clear_color"] = [0.14, 0.14, 0.16, 1.0]
let fr = create_font_renderer(r["render_pass"])
load_font(fr, "main", "assets/DejaVuSans.ttf", 24.0)

# Also set up colored UI quads for comparison
let ui_r = create_ui_renderer(r["render_pass"])
let root = create_widget("root")
root["width"] = 800.0
root["height"] = 600.0
# White rectangle for contrast
let bg = create_rect(10.0, 10.0, 400.0, 50.0, [0.25, 0.25, 0.28, 1.0])
add_child(root, bg)

let i = 0
while i < 60:
    let frame = begin_frame(r)
    if frame == nil:
        i = 100
        continue
    let cmd = frame["cmd"]
    # Draw bg quad
    draw_ui(ui_r, cmd, root, 800.0, 600.0)
    # Draw text
    draw_text(fr, cmd, "main", "Hello Forge Engine!", 20.0, 20.0, 1.0, 1.0, 1.0, 1.0, 800.0, 600.0)
    draw_text(fr, cmd, "main", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 20.0, 60.0, 0.3, 0.7, 1.0, 1.0, 800.0, 600.0)
    draw_text(fr, cmd, "main", "abcdefghijklmnopqrstuvwxyz", 20.0, 100.0, 1.0, 0.5, 0.3, 1.0, 800.0, 600.0)
    draw_text(fr, cmd, "main", "0123456789 +-=()[]{}.,;:!?", 20.0, 140.0, 0.7, 0.7, 0.7, 1.0, 800.0, 600.0)
    end_frame(r, frame)
    i = i + 1

shutdown_renderer(r)
print "Done"
