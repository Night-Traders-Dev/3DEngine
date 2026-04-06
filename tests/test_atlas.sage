import gpu
from font import create_font_renderer, load_font
from renderer import create_renderer
let r = create_renderer(400, 300, "test")
let fr = create_font_renderer(r["render_pass"])
let f = load_font(fr, "main", "assets/DejaVuSans.ttf", 20.0)
print "font loaded"
let atlas = gpu.font_atlas(f["handle"])
print "tex=" + str(atlas["texture"]) + " samp=" + str(atlas["sampler"])
print "desc_set=" + str(f["desc_set"])
from renderer import shutdown_renderer
shutdown_renderer(r)
