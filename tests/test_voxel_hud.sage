# test_voxel_hud.sage - Sanity checks for the voxel HUD helpers

from voxel_hud import create_voxel_hud, update_voxel_hud
from voxel_world import create_voxel_world, create_voxel_inventory
from voxel_world import voxel_inventory_add, default_voxel_recipes

let p = 0
let f = 0

proc check(name, condition):
    if condition:
        p = p + 1
    else:
        print "  FAIL: " + name
        f = f + 1

print "=== Voxel HUD Sanity Checks ==="

let voxel = create_voxel_world(32, 16, 32)
let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 10)
voxel_inventory_add(inventory, 2, 4)
voxel_inventory_add(inventory, 3, 1)
voxel_inventory_add(inventory, 4, 2)
let recipes = default_voxel_recipes()

let hud = create_voxel_hud()
check("voxel hud created", hud != nil)
check("hotbar has ten slots", len(hud["hotbar_slots"]) == 10)
check("inventory has ten rows", len(hud["inventory_rows"]) == 10)

update_voxel_hud(hud, voxel, inventory, 2, false, recipes, 1280.0, 720.0)
check("root width updated", hud["root"]["width"] == 1280.0 and hud["root"]["height"] == 720.0)
check("selected hotbar slot tracked", hud["hotbar_slots"][1]["selected"] == true and hud["hotbar_slots"][1]["block_id"] == 2)
check("selected hotbar border widened", hud["hotbar_slots"][1]["panel"]["border_width"] > hud["hotbar_slots"][0]["panel"]["border_width"])
check("extended hotbar shows later palette entries", hud["hotbar_slots"][8]["block_id"] == 9 and hud["hotbar_slots"][9]["block_id"] == 10)
check("inventory hidden when toggle off", hud["inventory_panel"]["visible"] == false)
check("craft recipe loaded", hud["craft_recipe"] != nil and hud["craft_input"]["block_id"] == 4 and hud["craft_output"]["block_id"] == 6)
check("craft recipe index defaults to first recipe", hud["craft_recipe_index"] == 0)
check("craft panel ready when wood count is enough", hud["craft_ready"] == true and hud["craft_fill"]["width"] > 0.0)
check("slot layout computed", hud["hotbar_slots"][0]["panel"]["computed_y"] > 0.0)

hud["craft_recipe_index"] = 1
update_voxel_hud(hud, voxel, inventory, 1, true, recipes, 1920.0, 1080.0)
check("craft recipe selection index updates recipe", hud["craft_recipe"]["name"] == recipes[1]["name"] and hud["craft_input"]["block_id"] == recipes[1]["input_block"] and hud["craft_output"]["block_id"] == recipes[1]["output_block"])
check("craft panel not ready when recipe input is insufficient", hud["craft_ready"] == false)

update_voxel_hud(hud, voxel, inventory, 1, true, recipes, 1920.0, 1080.0)
check("inventory shown when toggle on", hud["inventory_panel"]["visible"] == true)
check("inventory row mirrors selected block", hud["inventory_rows"][0]["block_id"] == 1 and hud["inventory_rows"][0]["panel"]["border_color"][2] > 0.7)
check("inventory row fill width tracks counts", hud["inventory_rows"][0]["fill"]["width"] > hud["inventory_rows"][2]["fill"]["width"])
check("layout recomputes for larger screen", hud["craft_panel"]["computed_x"] > hud["inventory_panel"]["computed_x"])
check("extended inventory rows remain visible", hud["inventory_rows"][8]["panel"]["visible"] == true and hud["inventory_rows"][9]["panel"]["visible"] == true)

let low_inventory = create_voxel_inventory()
voxel_inventory_add(low_inventory, 4, 0)
update_voxel_hud(hud, voxel, low_inventory, 4, true, recipes, 1280.0, 720.0)
check("craft panel not ready without materials", hud["craft_ready"] == false)
check("craft fill collapses without materials", hud["craft_fill"]["width"] == 0.0)
check("empty late-palette slot dims opacity", hud["hotbar_slots"][9]["panel"]["opacity"] < 1.0)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Voxel HUD sanity checks failed!"
else:
    print "All voxel HUD sanity checks passed!"
