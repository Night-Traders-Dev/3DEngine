gc_disable()
# -----------------------------------------
# voxel_hud.sage - Shared HUD helpers for the Forge voxel template
# Minecraft-style hotbar, inventory overlay, and crafting card built from
# engine UI quads so the voxel sandbox can use real HUD structure.
# -----------------------------------------

import ui_core
from ui_core import create_widget, create_panel, create_rect, add_child
from ui_core import rgba, color_with_alpha, color_brighten
from ui_core import compute_layout
from voxel_world import voxel_palette_ids, voxel_block_surface
from voxel_world import voxel_inventory_count, voxel_block_name

let ANCHOR_BOTTOM_LEFT = ui_core.ANCHOR_BOTTOM_LEFT
let ANCHOR_BOTTOM_CENTER = ui_core.ANCHOR_BOTTOM_CENTER
let ANCHOR_BOTTOM_RIGHT = ui_core.ANCHOR_BOTTOM_RIGHT

let VOXEL_HUD_PANEL = rgba(0.05, 0.055, 0.07, 0.82)
let VOXEL_HUD_PANEL_BORDER = color_with_alpha(ui_core.THEME_BORDER_LIGHT, 0.45)
let VOXEL_SLOT_BG = rgba(0.12, 0.13, 0.16, 0.92)
let VOXEL_SLOT_EMPTY = rgba(0.16, 0.17, 0.20, 0.55)
let VOXEL_SLOT_SHADE = rgba(0.0, 0.0, 0.0, 0.18)
let VOXEL_SLOT_BORDER = color_with_alpha(ui_core.THEME_BORDER_LIGHT, 0.30)
let VOXEL_SLOT_SELECTED = color_with_alpha(ui_core.THEME_ACCENT, 0.95)
let VOXEL_SLOT_READY = color_with_alpha(ui_core.THEME_SUCCESS, 0.80)
let VOXEL_SLOT_DIM = color_with_alpha(ui_core.THEME_TEXT_DIM, 0.35)
let VOXEL_TRACK = rgba(0.10, 0.10, 0.12, 0.85)
let VOXEL_HOTBAR_SLOT_COUNT = 10
let VOXEL_INVENTORY_ROW_COUNT = 10

proc _set_widget_color(widget, color):
    widget["color"] = color
    widget["bg_color"] = color

proc _create_voxel_slot(x, y, size):
    let slot = {}
    slot["panel"] = create_panel(x, y, size, size, VOXEL_SLOT_BG)
    slot["panel"]["border_color"] = VOXEL_SLOT_BORDER
    slot["panel"]["border_width"] = ui_core.BORDER_THIN
    slot["panel"]["opacity"] = 1.0
    slot["swatch"] = create_rect(7.0, 7.0, size - 14.0, size - 18.0, VOXEL_SLOT_EMPTY)
    slot["swatch"]["border_color"] = color_with_alpha(ui_core.THEME_HIGHLIGHT, 0.12)
    slot["swatch"]["border_width"] = ui_core.BORDER_THIN
    slot["shade"] = create_rect(7.0, size - 18.0, size - 14.0, 6.0, VOXEL_SLOT_SHADE)
    add_child(slot["panel"], slot["swatch"])
    add_child(slot["panel"], slot["shade"])
    slot["block_id"] = 0
    slot["count"] = 0
    slot["label"] = ""
    slot["selected"] = false
    return slot

proc _create_inventory_row(x, y, w, h):
    let row = {}
    row["panel"] = create_panel(x, y, w, h, VOXEL_SLOT_BG)
    row["panel"]["border_color"] = VOXEL_SLOT_BORDER
    row["panel"]["border_width"] = ui_core.BORDER_THIN
    row["swatch"] = create_rect(6.0, 6.0, 24.0, 24.0, VOXEL_SLOT_EMPTY)
    row["swatch"]["border_color"] = color_with_alpha(ui_core.THEME_HIGHLIGHT, 0.10)
    row["swatch"]["border_width"] = ui_core.BORDER_THIN
    row["track"] = create_rect(40.0, h - 10.0, w - 48.0, 4.0, VOXEL_TRACK)
    row["fill"] = create_rect(40.0, h - 10.0, 0.0, 4.0, VOXEL_SLOT_DIM)
    add_child(row["panel"], row["track"])
    add_child(row["panel"], row["fill"])
    add_child(row["panel"], row["swatch"])
    row["block_id"] = 0
    row["count"] = 0
    row["label"] = ""
    return row

proc create_voxel_hud():
    let hud = {}
    hud["root"] = create_widget("root")
    hud["root"]["width"] = 1280.0
    hud["root"]["height"] = 720.0
    hud["root"]["visible"] = true

    let hotbar_w = 26.0 + VOXEL_HOTBAR_SLOT_COUNT * 60.0
    hud["hotbar_panel"] = create_panel(0.0, -18.0, hotbar_w, 78.0, VOXEL_HUD_PANEL)
    hud["hotbar_panel"]["anchor"] = ANCHOR_BOTTOM_CENTER
    hud["hotbar_panel"]["border_color"] = VOXEL_HUD_PANEL_BORDER
    hud["hotbar_panel"]["border_width"] = ui_core.BORDER_NORMAL
    add_child(hud["root"], hud["hotbar_panel"])

    hud["hotbar_slots"] = []
    let hi = 0
    while hi < VOXEL_HOTBAR_SLOT_COUNT:
        let slot = _create_voxel_slot(14.0 + hi * 60.0, 12.0, 50.0)
        add_child(hud["hotbar_panel"], slot["panel"])
        push(hud["hotbar_slots"], slot)
        hi = hi + 1

    let inventory_h = 38.0 + VOXEL_INVENTORY_ROW_COUNT * 31.0
    hud["inventory_panel"] = create_panel(18.0, 0.0 - (30.0 + inventory_h), 252.0, inventory_h, VOXEL_HUD_PANEL)
    hud["inventory_panel"]["anchor"] = ANCHOR_BOTTOM_LEFT
    hud["inventory_panel"]["border_color"] = VOXEL_HUD_PANEL_BORDER
    hud["inventory_panel"]["border_width"] = ui_core.BORDER_NORMAL
    hud["inventory_panel"]["visible"] = false
    add_child(hud["root"], hud["inventory_panel"])

    hud["inventory_rows"] = []
    let ri = 0
    while ri < VOXEL_INVENTORY_ROW_COUNT:
        let row = _create_inventory_row(12.0, 32.0 + ri * 31.0, 228.0, 30.0)
        add_child(hud["inventory_panel"], row["panel"])
        push(hud["inventory_rows"], row)
        ri = ri + 1

    hud["craft_panel"] = create_panel(-18.0, -170.0, 252.0, 140.0, VOXEL_HUD_PANEL)
    hud["craft_panel"]["anchor"] = ANCHOR_BOTTOM_RIGHT
    hud["craft_panel"]["border_color"] = color_with_alpha(ui_core.THEME_WARNING, 0.45)
    hud["craft_panel"]["border_width"] = ui_core.BORDER_NORMAL
    add_child(hud["root"], hud["craft_panel"])

    hud["craft_input"] = _create_voxel_slot(14.0, 34.0, 48.0)
    hud["craft_output"] = _create_voxel_slot(190.0, 34.0, 48.0)
    add_child(hud["craft_panel"], hud["craft_input"]["panel"])
    add_child(hud["craft_panel"], hud["craft_output"]["panel"])
    hud["craft_track"] = create_rect(74.0, 96.0, 102.0, 8.0, VOXEL_TRACK)
    hud["craft_fill"] = create_rect(74.0, 96.0, 0.0, 8.0, color_with_alpha(ui_core.THEME_WARNING, 0.75))
    hud["craft_fill_max_w"] = 102.0
    add_child(hud["craft_panel"], hud["craft_track"])
    add_child(hud["craft_panel"], hud["craft_fill"])
    hud["craft_recipe"] = nil
    hud["craft_ready"] = false

    return hud

proc update_voxel_hud(hud, voxel, inventory, selected_block, inventory_open, recipes, screen_w, screen_h):
    if hud == nil:
        return nil
    hud["root"]["width"] = screen_w
    hud["root"]["height"] = screen_h

    let palette_ids = voxel_palette_ids(voxel)
    let max_count = 1
    let mi = 0
    while mi < len(palette_ids):
        let count = voxel_inventory_count(inventory, palette_ids[mi])
        if count > max_count:
            max_count = count
        mi = mi + 1

    let hi = 0
    while hi < len(hud["hotbar_slots"]):
        let slot = hud["hotbar_slots"][hi]
        if hi < len(palette_ids):
            let block_id = palette_ids[hi]
            let count = voxel_inventory_count(inventory, block_id)
            let surface = voxel_block_surface(voxel, block_id)
            let color = [surface["albedo"][0], surface["albedo"][1], surface["albedo"][2], 1.0]
            slot["panel"]["visible"] = true
            slot["block_id"] = block_id
            slot["count"] = count
            slot["label"] = voxel_block_name(voxel, block_id)
            slot["selected"] = block_id == selected_block
            _set_widget_color(slot["swatch"], color)
            let bg = VOXEL_SLOT_BG
            let border = VOXEL_SLOT_BORDER
            let border_w = ui_core.BORDER_THIN
            let panel_opacity = 0.88
            if count <= 0:
                panel_opacity = 0.58
                border = VOXEL_SLOT_DIM
                _set_widget_color(slot["shade"], color_with_alpha(ui_core.THEME_BG, 0.42))
            else:
                _set_widget_color(slot["shade"], color_with_alpha(ui_core.THEME_HIGHLIGHT, 0.12))
            if slot["selected"]:
                bg = color_with_alpha(ui_core.THEME_ACCENT, 0.18)
                border = VOXEL_SLOT_SELECTED
                border_w = ui_core.BORDER_NORMAL
                panel_opacity = 1.0
                _set_widget_color(slot["swatch"], color_brighten(color, 1.08))
            slot["panel"]["bg_color"] = bg
            slot["panel"]["border_color"] = border
            slot["panel"]["border_width"] = border_w
            slot["panel"]["opacity"] = panel_opacity
        else:
            slot["panel"]["visible"] = false
            slot["block_id"] = 0
            slot["count"] = 0
            slot["label"] = ""
            slot["selected"] = false
        hi = hi + 1

    hud["inventory_panel"]["visible"] = inventory_open
    let ri = 0
    while ri < len(hud["inventory_rows"]):
        let row = hud["inventory_rows"][ri]
        if ri < len(palette_ids):
            let block_id = palette_ids[ri]
            let count = voxel_inventory_count(inventory, block_id)
            let surface = voxel_block_surface(voxel, block_id)
            let color = [surface["albedo"][0], surface["albedo"][1], surface["albedo"][2], 1.0]
            row["panel"]["visible"] = true
            row["block_id"] = block_id
            row["count"] = count
            row["label"] = voxel_block_name(voxel, block_id)
            _set_widget_color(row["swatch"], color)
            let fill_ratio = count / (max_count + 0.0)
            row["fill"]["width"] = (row["track"]["width"] * fill_ratio)
            let fill_color = VOXEL_SLOT_DIM
            if count > 0:
                fill_color = color_with_alpha(color_brighten(color, 1.05), 0.92)
            _set_widget_color(row["fill"], fill_color)
            if block_id == selected_block:
                row["panel"]["border_color"] = VOXEL_SLOT_SELECTED
                row["panel"]["bg_color"] = color_with_alpha(ui_core.THEME_ACCENT, 0.16)
            else:
                if count >= 4:
                    row["panel"]["border_color"] = VOXEL_SLOT_READY
                else:
                    row["panel"]["border_color"] = VOXEL_SLOT_BORDER
                row["panel"]["bg_color"] = VOXEL_SLOT_BG
        else:
            row["panel"]["visible"] = false
            row["block_id"] = 0
            row["count"] = 0
            row["label"] = ""
        ri = ri + 1

    let recipe = nil
    if recipes != nil and len(recipes) > 0:
        recipe = recipes[0]
    hud["craft_recipe"] = recipe
    hud["craft_ready"] = false
    if recipe != nil:
        let input_surface = voxel_block_surface(voxel, recipe["input_block"])
        let output_surface = voxel_block_surface(voxel, recipe["output_block"])
        _set_widget_color(hud["craft_input"]["swatch"], [input_surface["albedo"][0], input_surface["albedo"][1], input_surface["albedo"][2], 1.0])
        _set_widget_color(hud["craft_output"]["swatch"], [output_surface["albedo"][0], output_surface["albedo"][1], output_surface["albedo"][2], 1.0])
        hud["craft_input"]["block_id"] = recipe["input_block"]
        hud["craft_output"]["block_id"] = recipe["output_block"]
        hud["craft_input"]["count"] = voxel_inventory_count(inventory, recipe["input_block"])
        hud["craft_output"]["count"] = voxel_inventory_count(inventory, recipe["output_block"])
        let craft_ratio = hud["craft_input"]["count"] / (recipe["input_count"] + 0.0)
        if craft_ratio > 1.0:
            craft_ratio = 1.0
        hud["craft_fill"]["width"] = hud["craft_fill_max_w"] * craft_ratio
        if hud["craft_input"]["count"] >= recipe["input_count"]:
            hud["craft_ready"] = true
            _set_widget_color(hud["craft_fill"], color_with_alpha(ui_core.THEME_SUCCESS, 0.85))
            hud["craft_panel"]["border_color"] = color_with_alpha(ui_core.THEME_SUCCESS, 0.65)
        else:
            _set_widget_color(hud["craft_fill"], color_with_alpha(ui_core.THEME_WARNING, 0.78))
            hud["craft_panel"]["border_color"] = color_with_alpha(ui_core.THEME_WARNING, 0.45)
    else:
        hud["craft_fill"]["width"] = 0.0
        hud["craft_panel"]["border_color"] = color_with_alpha(ui_core.THEME_BORDER_LIGHT, 0.45)

    compute_layout(hud["root"], 0.0, 0.0, screen_w, screen_h)
    return hud
