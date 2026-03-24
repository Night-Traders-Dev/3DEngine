import gpu
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer
from font import create_font_renderer, load_font, draw_text

let r = create_renderer(800, 600, "Font Test")
if r == nil:
    raise "Failed"
r["clear_color"] = [0.14, 0.14, 0.16, 1.0]

let fr = create_font_renderer(r["render_pass"])
if fr == nil:
    raise "Font renderer failed"

let f = load_font(fr, "main", "assets/DejaVuSans.ttf", 18.0)
if f == nil:
    raise "Font load failed"
print "Font loaded!"

let f2 = load_font(fr, "bold", "assets/DejaVuSans-Bold.ttf", 18.0)
print "Bold font loaded!"

let i = 0
while i < 5:
    let frame = begin_frame(r)
    if frame == nil:
        i = 100
        continue
    let cmd = frame["cmd"]
    draw_text(fr, cmd, "main", "Hello Forge Engine!", 20.0, 30.0, 1.0, 1.0, 1.0, 1.0, 800.0, 600.0)
    draw_text(fr, cmd, "bold", "The quick brown fox", 20.0, 60.0, 0.8, 0.8, 0.8, 1.0, 800.0, 600.0)
    draw_text(fr, cmd, "main", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 20.0, 90.0, 0.3, 0.6, 1.0, 1.0, 800.0, 600.0)
    draw_text(fr, cmd, "main", "0123456789 +-=()[]", 20.0, 120.0, 0.6, 0.6, 0.6, 1.0, 800.0, 600.0)
    end_frame(r, frame)
    i = i + 1

shutdown_renderer(r)
print "Done!"
