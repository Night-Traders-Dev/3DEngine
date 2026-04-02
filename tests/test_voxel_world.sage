# test_voxel_world.sage - Sanity checks for the voxel template world helpers

from voxel_world import create_voxel_world, voxel_palette_ids, voxel_palette_entry
from voxel_world import voxel_block_name, voxel_block_surface, voxel_is_surface_block
from voxel_world import get_voxel, set_voxel, fill_voxel_box, build_voxel_meshes, generate_voxel_template_world
from voxel_world import voxel_top_solid_y, sample_voxel_ground, sample_voxel_ground_radius
from voxel_world import raycast_voxel_world, voxel_collides_player, resolve_player_voxel_collision
from voxel_world import create_voxel_inventory, voxel_inventory_add, voxel_inventory_remove
from voxel_world import voxel_inventory_count, voxel_inventory_to_sage, voxel_inventory_from_sage
from voxel_world import voxel_world_to_sage, voxel_world_from_sage, serialize_voxel_world
from voxel_world import deserialize_voxel_world, save_voxel_world, load_voxel_world
from voxel_world import default_voxel_recipes, try_craft_voxel_recipe
from voxel_world import voxel_chunk_count_x, voxel_chunk_count_y, voxel_chunk_count_z
from voxel_world import voxel_chunk_bounds, build_voxel_chunk_meshes, voxel_visible_draws
from voxel_world import save_voxel_world_chunks, load_voxel_world_chunks
from voxel_world import ensure_voxel_generated_radius, voxel_generated_chunk_count
from math3d import vec3

import math
import io

let p = 0
let f = 0

proc check(name, condition):
    if condition:
        p = p + 1
    else:
        print "  FAIL: " + name
        f = f + 1

print "=== Voxel World Sanity Checks ==="

let vw = create_voxel_world(8, 8, 8)
check("voxel world created", vw != nil)
check("palette has six block types", len(voxel_palette_ids(vw)) == 6)
check("grass palette entry exists", voxel_palette_entry(vw, 1) != nil)
check("plank palette entry exists", voxel_palette_entry(vw, 6) != nil)
check("air name fallback", voxel_block_name(vw, 0) == "Air")

set_voxel(vw, 1, 1, 1, 1)
check("set/get voxel block", get_voxel(vw, 1, 1, 1) == 1)
check("surface block detected", voxel_is_surface_block(vw, 1, 1, 1) == true)
let grass_surface = voxel_block_surface(vw, 1)
check("surface color exported", grass_surface["albedo"][1] > 0.7)

let single_meshes = build_voxel_meshes(vw)
check("single grass mesh emitted", dict_has(single_meshes, "1"))
check("single cube uses six faces", single_meshes["1"]["face_count"] == 6)
check("single cube has 36 indices", single_meshes["1"]["index_count"] == 36)

let adjacent = create_voxel_world(8, 8, 8)
set_voxel(adjacent, 1, 1, 1, 3)
set_voxel(adjacent, 2, 1, 1, 3)
let adjacent_meshes = build_voxel_meshes(adjacent)
check("adjacent cubes share one material bucket", dict_has(adjacent_meshes, "3"))
check("internal face culled", adjacent_meshes["3"]["face_count"] == 10)
check("culled mesh index count", adjacent_meshes["3"]["index_count"] == 60)

let enclosed = create_voxel_world(4, 4, 4)
fill_voxel_box(enclosed, 0, 0, 0, 4, 4, 4, 3)
set_voxel(enclosed, 1, 1, 1, 2)
let enclosed_meshes = build_voxel_meshes(enclosed)
check("zero-face material buckets are omitted", dict_has(enclosed_meshes, "2") == false)

let ray_world = create_voxel_world(8, 8, 8)
set_voxel(ray_world, 4, 1, 4, 2)
let hit = raycast_voxel_world(ray_world, vec3(0.5, 1.5, 2.5), vec3(0.0, 0.0, -1.0), 8.0)
check("raycast hits placed block", hit != nil and hit["block_id"] == 2)
check("raycast returns placement cell", hit != nil and hit["place_z"] == 5)

set_voxel(ray_world, 4, 0, 4, 3)
check("top solid y found", voxel_top_solid_y(ray_world, 4, 4) == 1)
check("sample voxel ground returns top+1", math.abs(sample_voxel_ground(ray_world, 0.2, 0.2) - 2.0) < 0.001)
check("sample voxel ground radius considers corners", math.abs(sample_voxel_ground_radius(ray_world, 0.2, 0.2, 0.2) - 2.0) < 0.001)

let collide_pos = vec3(0.5, 1.0, 0.5)
check("player collision detects occupied block", voxel_collides_player(ray_world, collide_pos, 0.3, 1.8) == true)
let resolved = resolve_player_voxel_collision(ray_world, vec3(-0.4, 1.0, 0.5), collide_pos, 0.3, 1.8)
check("collision resolution backs player out", resolved[0] < 0.0)

let generated = create_voxel_world(16, 12, 16)
generate_voxel_template_world(generated, 5.0)
check("generated world has blocks", generated["solid_count"] > 0)
check("generated terrain exposes surfaces", voxel_is_surface_block(generated, 8, voxel_top_solid_y(generated, 8, 8), 8) == true)

let lazy_generated = create_voxel_world(48, 18, 48)
check("lazy world starts with no generated chunks", voxel_generated_chunk_count(lazy_generated) == 0)
let lazy_added = ensure_voxel_generated_radius(lazy_generated, 0.0, 0.0, 0.0, 0, 7.0)
check("lazy generation adds initial chunk", lazy_added == 1 and voxel_generated_chunk_count(lazy_generated) == 1)
let lazy_repeat = ensure_voxel_generated_radius(lazy_generated, 0.0, 0.0, 0.0, 0, 7.0)
check("lazy generation does not regenerate existing chunk", lazy_repeat == 0 and voxel_generated_chunk_count(lazy_generated) == 1)
check("lazy generation fills terrain blocks", lazy_generated["solid_count"] > 0)
let lazy_more = ensure_voxel_generated_radius(lazy_generated, 20.0, 0.0, 20.0, 0, 7.0)
check("lazy generation expands to newly visited chunk", lazy_more > 0 and voxel_generated_chunk_count(lazy_generated) > 1)

let save_world = create_voxel_world(6, 6, 6)
set_voxel(save_world, 2, 1, 2, 4)
set_voxel(save_world, 2, 2, 2, 5)
let world_data = voxel_world_to_sage(save_world)
let world_copy = voxel_world_from_sage(world_data)
check("voxel world roundtrip preserves dimensions", world_copy != nil and world_copy["size_x"] == 6 and world_copy["size_y"] == 6 and world_copy["size_z"] == 6)
check("voxel world roundtrip preserves blocks", world_copy != nil and get_voxel(world_copy, 2, 1, 2) == 4 and get_voxel(world_copy, 2, 2, 2) == 5)
let world_json = serialize_voxel_world(save_world)
let world_loaded = deserialize_voxel_world(world_json)
check("serialized voxel world loads", world_loaded != nil and world_loaded["solid_count"] == 2)

let voxel_save_path = "/tmp/forge_test_voxel_world.json"
save_voxel_world(save_world, voxel_save_path)
check("voxel world file saved", io.exists(voxel_save_path))
let world_file = load_voxel_world(voxel_save_path)
check("voxel world file load preserves data", world_file != nil and get_voxel(world_file, 2, 1, 2) == 4 and get_voxel(world_file, 2, 2, 2) == 5)

let chunk_world = create_voxel_world(17, 9, 17)
check("chunk counts derived from default chunk size", voxel_chunk_count_x(chunk_world) == 2 and voxel_chunk_count_y(chunk_world) == 1 and voxel_chunk_count_z(chunk_world) == 2)
let chunk_bounds = voxel_chunk_bounds(chunk_world, 1, 0, 1)
check("chunk bounds clamp to world edge", chunk_bounds["x0"] == 16 and chunk_bounds["x1"] == 17 and chunk_bounds["y0"] == 0 and chunk_bounds["y1"] == 9 and chunk_bounds["z0"] == 16 and chunk_bounds["z1"] == 17)
set_voxel(chunk_world, 15, 1, 1, 3)
set_voxel(chunk_world, 16, 1, 1, 3)
let chunk_mesh_left = build_voxel_chunk_meshes(chunk_world, 0, 0, 0)
let chunk_mesh_right = build_voxel_chunk_meshes(chunk_world, 1, 0, 0)
check("chunk mesh culls faces across chunk boundaries", chunk_mesh_left["3"]["face_count"] == 5 and chunk_mesh_right["3"]["face_count"] == 5)
chunk_world["max_stream_chunk_refresh"] = 8
let all_chunk_draws = voxel_visible_draws(chunk_world, -7.0, 1.0, -7.0, 8)
let local_chunk_draws = voxel_visible_draws(chunk_world, -7.0, 1.0, -7.0, 0)
check("visible draws filter chunk meshes by radius", len(all_chunk_draws) == 2 and len(local_chunk_draws) == 1)
let chunk_manifest_path = "/tmp/forge_test_voxel_chunks.json"
save_voxel_world_chunks(chunk_world, chunk_manifest_path)
check("chunk manifest saved", io.exists(chunk_manifest_path))
check("chunk payload saved", io.exists(chunk_manifest_path + ".chunk_0_0_0.json") and io.exists(chunk_manifest_path + ".chunk_1_0_0.json"))
let chunk_loaded = load_voxel_world_chunks(chunk_manifest_path)
check("chunk manifest load preserves data", chunk_loaded != nil and get_voxel(chunk_loaded, 15, 1, 1) == 3 and get_voxel(chunk_loaded, 16, 1, 1) == 3)

let lazy_manifest_path = "/tmp/forge_test_voxel_lazy_chunks.json"
save_voxel_world_chunks(lazy_generated, lazy_manifest_path)
let lazy_loaded = load_voxel_world_chunks(lazy_manifest_path)
check("lazy chunk manifest load preserves generated chunk count", lazy_loaded != nil and voxel_generated_chunk_count(lazy_loaded) == voxel_generated_chunk_count(lazy_generated))

let inventory = create_voxel_inventory()
check("inventory starts empty", voxel_inventory_count(inventory, 3) == 0)
voxel_inventory_add(inventory, 3, 8)
voxel_inventory_add(inventory, 4, 2)
check("inventory add tracks block counts", voxel_inventory_count(inventory, 3) == 8 and voxel_inventory_count(inventory, 4) == 2)
check("inventory remove succeeds with stock", voxel_inventory_remove(inventory, 3, 5) == true and voxel_inventory_count(inventory, 3) == 3)
check("inventory remove rejects insufficient stock", voxel_inventory_remove(inventory, 4, 3) == false and voxel_inventory_count(inventory, 4) == 2)
let inv_copy = voxel_inventory_from_sage(voxel_inventory_to_sage(inventory))
check("inventory roundtrip preserves counts", voxel_inventory_count(inv_copy, 3) == 3 and voxel_inventory_count(inv_copy, 4) == 2)
let recipes = default_voxel_recipes()
check("default voxel recipe exists", len(recipes) == 1 and recipes[0]["output_block"] == 6)
check("crafting consumes inputs and creates planks", try_craft_voxel_recipe(inv_copy, recipes[0]) == true and voxel_inventory_count(inv_copy, 4) == 1 and voxel_inventory_count(inv_copy, 6) == 4)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Voxel world sanity checks failed!"
else:
    print "All voxel world sanity checks passed!"
