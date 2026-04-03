gc_disable()
# -----------------------------------------
# launch_screen.sage - Forge Engine Project Launcher
# Displays project templates and action buttons before entering the editor
# Returns: {"action": "new"/"open"/"exit", "template": template_id_or_nil}
# -----------------------------------------

import gpu
import sys
import ui_core
from ui_core import rgba, color_with_alpha, _push_border_quads, _push_shadow_quads
from ui_renderer import create_ui_renderer
from font import create_font_renderer, load_font, begin_text, add_text, flush_text
from renderer import begin_frame, end_frame, check_resize
from game_loop import create_time_state, update_time
from forge_version import engine_banner

# ============================================================================
# Template definitions
# ============================================================================
proc _make_templates():
    let t = []
    push(t, {"id": "fps",      "name": "First Person Shooter", "desc": "FPS with weapons, health, AI enemies",  "icon": "FPS", "color": rgba(0.85, 0.30, 0.25, 1.0)})
    push(t, {"id": "rpg",      "name": "Role-Playing Game",    "desc": "RPG with inventory, quests, dialogue",  "icon": "RPG", "color": rgba(0.60, 0.35, 0.80, 1.0)})
    push(t, {"id": "topdown",  "name": "Top-Down Action",      "desc": "Overhead camera, twin-stick controls",   "icon": "TOP", "color": rgba(0.25, 0.70, 0.45, 1.0)})
    push(t, {"id": "voxel",    "name": "Voxel World",          "desc": "Block-based terrain, mining, building",  "icon": "VOX", "color": rgba(0.55, 0.75, 0.30, 1.0)})
    push(t, {"id": "race",     "name": "Racing Game",          "desc": "Vehicles, tracks, lap timing",           "icon": "RCE", "color": rgba(0.90, 0.60, 0.15, 1.0)})
    push(t, {"id": "survival", "name": "Survival",             "desc": "Crafting, hunger, day/night cycle",      "icon": "SRV", "color": rgba(0.40, 0.65, 0.75, 1.0)})
    push(t, {"id": "sandbox",  "name": "Sandbox / Empty",      "desc": "Blank project, build from scratch",      "icon": "SBX", "color": rgba(0.50, 0.50, 0.55, 1.0)})
    return t

proc _template_details(id):
    if id == "fps":
        return ["Player controller + camera", "Weapon system + raycasting", "Health + damage + HUD", "AI enemies with navigation"]
    if id == "rpg":
        return ["Third-person camera", "Inventory + equipment", "Quest / dialogue stubs", "Stats + leveling framework"]
    if id == "topdown":
        return ["Overhead camera rig", "WASD + mouse aim controls", "Projectile system", "Wave spawner + scoring"]
    if id == "voxel":
        return ["Block terrain generation", "Place / break block tools", "First-person controller", "Block type palette"]
    if id == "race":
        return ["Vehicle physics + steering", "Chase camera", "Lap timer + checkpoints", "Speed HUD overlay"]
    if id == "survival":
        return ["Crafting + resource system", "Hunger / thirst / stamina", "Day-night cycle", "Buildable shelters"]
    if id == "sandbox":
        return ["Empty scene with grid", "Basic lighting setup", "No preset gameplay", "Full creative freedom"]
    return []

proc _template_index_by_id(templates, id):
    let i = 0
    while i < len(templates):
        if templates[i]["id"] == id:
            return i
        i = i + 1
    return -1

proc _in_rect(mx, my, x, y, w, h):
    return mx >= x and mx < x + w and my >= y and my < y + h

# ============================================================================
# Run the launch screen
# ============================================================================
proc run_launch_screen(r):
    let orig_clear = r["clear_color"]
    r["clear_color"] = [0.055, 0.055, 0.063, 1.0]

    let templates = _make_templates()
    let template_override = sys.getenv("FORGE_TEMPLATE")
    if template_override != nil and template_override != "":
        let idx = _template_index_by_id(templates, template_override)
        r["clear_color"] = orig_clear
        if idx >= 0:
            gpu.set_cursor_mode(gpu.CURSOR_NORMAL)
            return {"action": "new", "template": templates[idx]["id"]}
        print "WARNING: Unknown FORGE_TEMPLATE '" + template_override + "', showing launcher."

    let ui_r = create_ui_renderer(r["render_pass"])
    if ui_r == nil:
        r["clear_color"] = orig_clear
        return {"action": "new", "template": "sandbox"}

    let font_r = create_font_renderer(r["render_pass"])
    load_font(font_r, "ui", "assets/DejaVuSans.ttf", 18.0)

    let selected = 0
    let hovered_tpl = -1
    let hovered_btn = ""
    let result = nil
    let ts = create_time_state()

    gpu.set_cursor_mode(gpu.CURSOR_NORMAL)

    while result == nil:
        update_time(ts)

        # begin_frame handles poll_events + swapchain acquire
        check_resize(r)
        let sw = r["width"] + 0.0
        let sh = r["height"] + 0.0
        if sw < 1.0 or sh < 1.0:
            continue

        # Input (after poll_events inside check_resize path)
        gpu.update_input()
        let mp = gpu.mouse_pos()
        let mx = mp["x"]
        let my = mp["y"]
        let left_click = gpu.mouse_just_pressed(gpu.MOUSE_LEFT)

        if gpu.key_just_pressed(gpu.KEY_ESCAPE):
            result = {"action": "exit", "template": nil}
            continue
        if gpu.key_just_pressed(gpu.KEY_ENTER):
            result = {"action": "new", "template": templates[selected]["id"]}
            continue
        if gpu.key_just_pressed(gpu.KEY_DOWN):
            selected = selected + 1
            if selected >= len(templates):
                selected = 0
        if gpu.key_just_pressed(gpu.KEY_UP):
            selected = selected - 1
            if selected < 0:
                selected = len(templates) - 1

        # ==================================================================
        # Layout
        # ==================================================================
        let margin = 40.0
        let cw = sw - margin * 2.0
        let ch = sh - margin * 2.0
        let cx = margin
        let cy_base = margin
        let title_h = 70.0
        let sidebar_w = 400.0
        if sidebar_w > cw * 0.45:
            sidebar_w = cw * 0.45
        let gap = 16.0

        let tpl_x = cx
        let tpl_y = cy_base + title_h
        let tpl_w = cw - sidebar_w - gap
        if tpl_w < 280.0:
            tpl_w = 280.0
        let tpl_h = ch - title_h

        let act_x = tpl_x + tpl_w + gap
        let act_y = tpl_y
        let act_w = sidebar_w
        let act_h = tpl_h

        let card_pad = 12.0
        let card_w = tpl_w - card_pad * 2.0
        let card_h = 62.0
        let card_gap = 4.0

        let btn_pad = 24.0
        let btn_w = act_w - btn_pad * 2.0
        let btn_h = 46.0
        let btn_gap = 10.0
        let btn_y0 = act_y + 52.0 + btn_pad
        let create_y = btn_y0
        let open_y = btn_y0 + btn_h + btn_gap
        let exit_y = act_y + act_h - btn_pad - btn_h

        # ==================================================================
        # Hit test
        # ==================================================================
        hovered_tpl = -1
        hovered_btn = ""

        let ti = 0
        while ti < len(templates):
            let card_y = tpl_y + 48.0 + card_pad + ti * (card_h + card_gap)
            if _in_rect(mx, my, tpl_x + card_pad, card_y, card_w, card_h):
                hovered_tpl = ti
                if left_click:
                    selected = ti
            ti = ti + 1

        if _in_rect(mx, my, act_x + btn_pad, create_y, btn_w, btn_h):
            hovered_btn = "create"
            if left_click:
                result = {"action": "new", "template": templates[selected]["id"]}
        if _in_rect(mx, my, act_x + btn_pad, open_y, btn_w, btn_h):
            hovered_btn = "open"
            if left_click:
                result = {"action": "open", "template": nil}
        if _in_rect(mx, my, act_x + btn_pad, exit_y, btn_w, btn_h):
            hovered_btn = "exit"
            if left_click:
                result = {"action": "exit", "template": nil}

        # ==================================================================
        # Build quads
        # ==================================================================
        let q = []

        # Top accent stripe
        push(q, {"x": 0.0, "y": 0.0, "w": sw, "h": 3.0, "color": [ui_core.THEME_ACCENT[0], ui_core.THEME_ACCENT[1], ui_core.THEME_ACCENT[2], 0.55]})

        # Title bar
        push(q, {"x": cx, "y": cy_base, "w": cw, "h": title_h, "color": [0.072, 0.072, 0.082, 1.0]})
        push(q, {"x": cx, "y": cy_base + title_h - 2.0, "w": cw, "h": 2.0, "color": color_with_alpha(ui_core.THEME_ACCENT, 0.30)})

        # --- Templates panel ---
        _push_shadow_quads(q, tpl_x, tpl_y, tpl_w, tpl_h)
        push(q, {"x": tpl_x, "y": tpl_y, "w": tpl_w, "h": tpl_h, "color": ui_core.THEME_PANEL})
        _push_border_quads(q, tpl_x, tpl_y, tpl_w, tpl_h, 1.0, ui_core.THEME_BORDER)
        push(q, {"x": tpl_x, "y": tpl_y, "w": tpl_w, "h": 44.0, "color": ui_core.THEME_HEADER})
        push(q, {"x": tpl_x, "y": tpl_y + 43.0, "w": tpl_w, "h": 1.0, "color": ui_core.THEME_BORDER})

        # Template cards
        ti = 0
        while ti < len(templates):
            let tmpl = templates[ti]
            let card_y = tpl_y + 48.0 + card_pad + ti * (card_h + card_gap)
            let is_sel = ti == selected
            let is_hov = ti == hovered_tpl
            let tc = tmpl["color"]

            let cbg = ui_core.THEME_SURFACE
            if is_sel:
                cbg = rgba(tc[0] * 0.18 + 0.05, tc[1] * 0.18 + 0.05, tc[2] * 0.18 + 0.05, 1.0)
            else:
                if is_hov:
                    cbg = ui_core.THEME_ELEVATED
            push(q, {"x": tpl_x + card_pad, "y": card_y, "w": card_w, "h": card_h, "color": cbg})

            if is_sel:
                _push_border_quads(q, tpl_x + card_pad, card_y, card_w, card_h, 2.0, ui_core.THEME_ACCENT)
            else:
                if is_hov:
                    _push_border_quads(q, tpl_x + card_pad, card_y, card_w, card_h, 1.0, ui_core.THEME_BORDER_LIGHT)
                else:
                    _push_border_quads(q, tpl_x + card_pad, card_y, card_w, card_h, 1.0, ui_core.THEME_BORDER)

            # Badge
            let bs = 42.0
            let bx = tpl_x + card_pad + 10.0
            let by = card_y + (card_h - bs) / 2.0
            push(q, {"x": bx, "y": by, "w": bs, "h": bs, "color": color_with_alpha(tc, 0.18)})
            _push_border_quads(q, bx, by, bs, bs, 1.0, color_with_alpha(tc, 0.45))

            if is_hov and is_sel == false:
                push(q, {"x": tpl_x + card_pad, "y": card_y, "w": card_w, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.04]})
            ti = ti + 1

        # --- Actions panel ---
        _push_shadow_quads(q, act_x, act_y, act_w, act_h)
        push(q, {"x": act_x, "y": act_y, "w": act_w, "h": act_h, "color": ui_core.THEME_PANEL})
        _push_border_quads(q, act_x, act_y, act_w, act_h, 1.0, ui_core.THEME_BORDER)
        push(q, {"x": act_x, "y": act_y, "w": act_w, "h": 44.0, "color": ui_core.THEME_HEADER})
        push(q, {"x": act_x, "y": act_y + 43.0, "w": act_w, "h": 1.0, "color": ui_core.THEME_BORDER})

        # Preview area
        let pv_y = open_y + btn_h + btn_gap + 12.0
        let pv_h = exit_y - pv_y - 16.0
        if pv_h > 80.0:
            let stc = templates[selected]["color"]
            push(q, {"x": act_x + btn_pad, "y": pv_y, "w": btn_w, "h": pv_h, "color": ui_core.THEME_SURFACE})
            _push_border_quads(q, act_x + btn_pad, pv_y, btn_w, pv_h, 1.0, ui_core.THEME_BORDER)
            push(q, {"x": act_x + btn_pad, "y": pv_y, "w": btn_w, "h": 3.0, "color": color_with_alpha(stc, 0.55)})

        # Create button
        let c_bg = ui_core.THEME_ACCENT
        if hovered_btn == "create":
            c_bg = ui_core.THEME_ACCENT_HOVER
        push(q, {"x": act_x + btn_pad, "y": create_y, "w": btn_w, "h": btn_h, "color": c_bg})
        _push_border_quads(q, act_x + btn_pad, create_y, btn_w, btn_h, 1.0, color_with_alpha(ui_core.THEME_ACCENT, 0.5))
        if hovered_btn == "create":
            push(q, {"x": act_x + btn_pad, "y": create_y, "w": btn_w, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.10]})

        # Open button
        let o_bg = ui_core.THEME_BUTTON
        if hovered_btn == "open":
            o_bg = ui_core.THEME_BUTTON_HOVER
        push(q, {"x": act_x + btn_pad, "y": open_y, "w": btn_w, "h": btn_h, "color": o_bg})
        _push_border_quads(q, act_x + btn_pad, open_y, btn_w, btn_h, 1.0, ui_core.THEME_BORDER_LIGHT)
        if hovered_btn == "open":
            push(q, {"x": act_x + btn_pad, "y": open_y, "w": btn_w, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.06]})

        # Exit button
        let e_bg = rgba(0.42, 0.15, 0.15, 1.0)
        if hovered_btn == "exit":
            e_bg = rgba(0.55, 0.20, 0.20, 1.0)
        push(q, {"x": act_x + btn_pad, "y": exit_y, "w": btn_w, "h": btn_h, "color": e_bg})
        _push_border_quads(q, act_x + btn_pad, exit_y, btn_w, btn_h, 1.0, rgba(0.55, 0.20, 0.20, 0.4))

        # Bottom bar
        push(q, {"x": 0.0, "y": sh - 28.0, "w": sw, "h": 28.0, "color": [0.038, 0.038, 0.045, 0.85]})

        # ==================================================================
        # Render
        # ==================================================================
        let frame = begin_frame(r)
        if frame == nil:
            if gpu.window_should_close():
                result = {"action": "exit", "template": nil}
            continue
        let cmd = frame["cmd"]

        if len(q) > 0:
            let verts = build_quad_verts(q)
            gpu.buffer_upload(ui_r["vbuf"], verts)
            gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
            gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
            gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
            gpu.cmd_draw(cmd, len(q) * 6, 1, 0, 0)

        # Text
        begin_text(font_r)

        add_text(font_r, "ui", "FORGE ENGINE", cx + 20.0, cy_base + 14.0, 0.93, 0.94, 0.96, 1.0)
        add_text(font_r, "ui", "Project Browser", cx + 178.0, cy_base + 14.0, 0.48, 0.50, 0.54, 1.0)
        add_text(font_r, "ui", "Select a template and create a new project, or open an existing one.", cx + 20.0, cy_base + 42.0, 0.38, 0.40, 0.44, 1.0)

        add_text(font_r, "ui", "Templates", tpl_x + 14.0, tpl_y + 13.0, 0.78, 0.80, 0.83, 1.0)

        ti = 0
        while ti < len(templates):
            let tmpl = templates[ti]
            let card_y = tpl_y + 48.0 + card_pad + ti * (card_h + card_gap)
            let is_sel = ti == selected
            let tc = tmpl["color"]

            let bx = tpl_x + card_pad + 10.0
            let by = card_y + (card_h - 42.0) / 2.0
            add_text(font_r, "ui", tmpl["icon"], bx + 7.0, by + 13.0, tc[0], tc[1], tc[2], 1.0)

            let nc = ui_core.THEME_TEXT
            if is_sel:
                nc = ui_core.THEME_TEXT_BRIGHT
            add_text(font_r, "ui", tmpl["name"], tpl_x + card_pad + 66.0, card_y + 14.0, nc[0], nc[1], nc[2], 1.0)
            let dc = ui_core.THEME_TEXT_SECONDARY
            add_text(font_r, "ui", tmpl["desc"], tpl_x + card_pad + 66.0, card_y + 36.0, dc[0], dc[1], dc[2], 1.0)
            ti = ti + 1

        add_text(font_r, "ui", "Actions", act_x + 14.0, act_y + 13.0, 0.78, 0.80, 0.83, 1.0)

        add_text(font_r, "ui", "Create New Project", act_x + btn_pad + btn_w / 2.0 - 82.0, create_y + 14.0, 1.0, 1.0, 1.0, 1.0)
        add_text(font_r, "ui", "Open Existing Project", act_x + btn_pad + btn_w / 2.0 - 92.0, open_y + 14.0, 0.80, 0.82, 0.85, 1.0)
        add_text(font_r, "ui", "Exit", act_x + btn_pad + btn_w / 2.0 - 16.0, exit_y + 14.0, 0.82, 0.65, 0.65, 1.0)

        if pv_h > 80.0:
            let st = templates[selected]
            let tc = st["color"]
            add_text(font_r, "ui", st["name"], act_x + btn_pad + 12.0, pv_y + 16.0, tc[0], tc[1], tc[2], 1.0)
            add_text(font_r, "ui", st["desc"], act_x + btn_pad + 12.0, pv_y + 40.0, ui_core.THEME_TEXT_SECONDARY[0], ui_core.THEME_TEXT_SECONDARY[1], ui_core.THEME_TEXT_SECONDARY[2], 1.0)
            add_text(font_r, "ui", "Includes:", act_x + btn_pad + 12.0, pv_y + 70.0, 0.52, 0.54, 0.58, 1.0)
            let details = _template_details(st["id"])
            let di = 0
            while di < len(details):
                add_text(font_r, "ui", "- " + details[di], act_x + btn_pad + 12.0, pv_y + 94.0 + di * 22.0, 0.45, 0.47, 0.50, 1.0)
                di = di + 1

        add_text(font_r, "ui", "ENTER = Create  |  Up/Down = Navigate  |  ESC = Exit", cx + 16.0, sh - 20.0, 0.32, 0.34, 0.37, 1.0)
        add_text(font_r, "ui", engine_banner(), sw - 182.0, sh - 20.0, 0.28, 0.30, 0.33, 1.0)

        flush_text(font_r, cmd, sw, sh)

        end_frame(r, frame)

    r["clear_color"] = orig_clear
    return result
