# demo.sage - Forge Engine Phase 1 Demo
# Demonstrates: ECS, input system, fixed-timestep game loop, Vulkan rendering
#
# Run: ./run.sh examples/demo.sage
# Controls: WASD to move, mouse to look, ESC to toggle mouse capture, Q to quit

import gpu
from engine import create_engine, on_update, on_render, run, shutdown
from ecs import spawn, add_component, get_component, has_component, query, register_system, add_tag
from components import TransformComponent, VelocityComponent, NameComponent, CameraComponent, MeshRendererComponent
from input import action_held, action_just_pressed, axis_value, mouse_delta, bind_action
from engine_math import transform_to_matrix, clamp
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_cross, v3_length
from math3d import mat4_perspective, mat4_translate, mat4_mul, mat4_rotate_y, mat4_rotate_x
from math3d import mat4_identity, radians, pack_mvp
from mesh import cube_mesh, plane_mesh, sphere_mesh, upload_mesh, mesh_vertex_binding, mesh_vertex_attribs
import math

print "=== Forge Engine - Phase 1 Demo ==="

# ============================================================================
# Create engine
# ============================================================================
let eng = create_engine("Forge Engine Demo", 1280, 720)
if eng == nil:
    raise "Failed to create engine"

let world = eng["world"]
let inp = eng["input"]

# Bind quit action
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])

# ============================================================================
# Load shaders and create pipeline
# ============================================================================
let vert = gpu.load_shader("shaders/cube.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("shaders/cube.frag.spv", gpu.STAGE_FRAGMENT)
if vert < 0 or frag < 0:
    raise "Failed to load shaders"

let r = eng["renderer"]
let pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)

let cfg = {}
cfg["layout"] = pipe_layout
cfg["render_pass"] = r["render_pass"]
cfg["vertex_shader"] = vert
cfg["fragment_shader"] = frag
cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
cfg["cull_mode"] = gpu.CULL_BACK
cfg["front_face"] = gpu.FRONT_CCW
cfg["depth_test"] = true
cfg["depth_write"] = true
cfg["vertex_bindings"] = [mesh_vertex_binding()]
cfg["vertex_attribs"] = mesh_vertex_attribs()
let pipeline = gpu.create_graphics_pipeline(cfg)
if pipeline < 0:
    raise "Failed to create pipeline"

# ============================================================================
# Upload meshes
# ============================================================================
let cube = upload_mesh(cube_mesh())
let ground = upload_mesh(plane_mesh(20.0))
let sphere = upload_mesh(sphere_mesh(16, 16))

# ============================================================================
# Spawn entities
# ============================================================================

# Camera entity
let cam_ent = spawn(world)
add_component(world, cam_ent, "transform", TransformComponent(0.0, 2.0, 8.0))
add_component(world, cam_ent, "camera", CameraComponent(60.0, 0.1, 500.0))
add_component(world, cam_ent, "name", NameComponent("MainCamera"))
let cam_comp = get_component(world, cam_ent, "camera")
cam_comp["active"] = true

# Ground plane
let ground_ent = spawn(world)
add_component(world, ground_ent, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ground_ent, "mesh_renderer", MeshRendererComponent(ground, "default"))
add_component(world, ground_ent, "name", NameComponent("Ground"))

# Spinning cubes in a circle
let NUM_CUBES = 8
let cube_entities = []
let ci = 0
while ci < NUM_CUBES:
    let angle = (ci / NUM_CUBES) * 6.2831853
    let px = math.cos(angle) * 4.0
    let pz = math.sin(angle) * 4.0
    let e = spawn(world)
    add_component(world, e, "transform", TransformComponent(px, 1.0, pz))
    add_component(world, e, "velocity", VelocityComponent())
    add_component(world, e, "mesh_renderer", MeshRendererComponent(cube, "default"))
    add_component(world, e, "name", NameComponent("Cube_" + str(ci)))
    add_tag(world, e, "spinner")
    # Give each cube a different spin speed
    let vel = get_component(world, e, "velocity")
    vel["angular"] = vec3(0.5 + ci * 0.2, 1.0 + ci * 0.3, 0.0)
    push(cube_entities, e)
    ci = ci + 1

# Center sphere
let sphere_ent = spawn(world)
add_component(world, sphere_ent, "transform", TransformComponent(0.0, 2.0, 0.0))
add_component(world, sphere_ent, "velocity", VelocityComponent())
add_component(world, sphere_ent, "mesh_renderer", MeshRendererComponent(sphere, "default"))
add_component(world, sphere_ent, "name", NameComponent("Sphere"))
let sv = get_component(world, sphere_ent, "velocity")
sv["angular"] = vec3(0.0, 0.5, 0.0)

print "Spawned " + str(NUM_CUBES) + " cubes + ground + sphere + camera"

# ============================================================================
# Systems
# ============================================================================

# Spin system - rotates entities with velocity
proc spin_system(w, entities, dt):
    let i = 0
    while i < len(entities):
        let e = entities[i]
        let t = get_component(w, e, "transform")
        let v = get_component(w, e, "velocity")
        t["rotation"][0] = t["rotation"][0] + v["angular"][0] * dt
        t["rotation"][1] = t["rotation"][1] + v["angular"][1] * dt
        t["rotation"][2] = t["rotation"][2] + v["angular"][2] * dt
        t["dirty"] = true
        i = i + 1

register_system(world, "spin", ["transform", "velocity"], spin_system)

# ============================================================================
# Camera state
# ============================================================================
let cam_state = {}
cam_state["yaw"] = -1.5708
cam_state["pitch"] = 0.0
cam_state["captured"] = false
cam_state["speed"] = 5.0

# ============================================================================
# Update callback
# ============================================================================
proc game_update(e, dt):
    let w = e["world"]
    let i = e["input"]

    # Quit
    if action_just_pressed(i, "quit"):
        shutdown(e)
        return nil

    # Toggle mouse capture
    if action_just_pressed(i, "toggle_capture"):
        if cam_state["captured"]:
            cam_state["captured"] = false
            gpu.set_cursor_mode(gpu.CURSOR_NORMAL)
        else:
            cam_state["captured"] = true
            gpu.set_cursor_mode(gpu.CURSOR_DISABLED)

    # Camera movement
    let cam_t = get_component(w, cam_ent, "transform")

    if cam_state["captured"]:
        let md = mouse_delta(i)
        cam_state["yaw"] = cam_state["yaw"] + md[0] * 0.003
        cam_state["pitch"] = cam_state["pitch"] - md[1] * 0.003
        cam_state["pitch"] = clamp(cam_state["pitch"], -1.5, 1.5)

    # Compute forward/right vectors
    let cy = math.cos(cam_state["yaw"])
    let sy = math.sin(cam_state["yaw"])
    let cp = math.cos(cam_state["pitch"])
    let sp = math.sin(cam_state["pitch"])
    let front = vec3(cy * cp, sp, sy * cp)
    let right = v3_normalize(v3_cross(front, vec3(0.0, 1.0, 0.0)))

    let move_speed = cam_state["speed"] * dt
    if action_held(i, "move_forward"):
        cam_t["position"] = v3_add(cam_t["position"], v3_scale(front, move_speed))
    if action_held(i, "move_back"):
        cam_t["position"] = v3_add(cam_t["position"], v3_scale(front, 0.0 - move_speed))
    if action_held(i, "move_left"):
        cam_t["position"] = v3_add(cam_t["position"], v3_scale(right, 0.0 - move_speed))
    if action_held(i, "move_right"):
        cam_t["position"] = v3_add(cam_t["position"], v3_scale(right, move_speed))
    if action_held(i, "jump"):
        cam_t["position"][1] = cam_t["position"][1] + move_speed
    if action_held(i, "crouch"):
        cam_t["position"][1] = cam_t["position"][1] - move_speed

on_update(eng, game_update)

# ============================================================================
# Render callback
# ============================================================================
proc game_render(e, frame):
    let w = e["world"]
    let r_ctx = e["renderer"]
    let cmd = frame["cmd"]

    # Build view matrix from camera
    let cam_t = get_component(w, cam_ent, "transform")
    let pos = cam_t["position"]
    let cy = math.cos(cam_state["yaw"])
    let sy = math.sin(cam_state["yaw"])
    let cp = math.cos(cam_state["pitch"])
    let sp = math.sin(cam_state["pitch"])
    let front = vec3(cy * cp, sp, sy * cp)
    let target = v3_add(pos, front)
    let up = vec3(0.0, 1.0, 0.0)

    from math3d import mat4_look_at
    let view = mat4_look_at(pos, target, up)
    let aspect = r_ctx["width"] / r_ctx["height"]
    let proj = mat4_perspective(radians(60.0), aspect, 0.1, 500.0)

    # Bind pipeline once
    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)

    # Draw all mesh renderers
    let renderers = query(w, ["transform", "mesh_renderer"])
    let i = 0
    while i < len(renderers):
        let eid = renderers[i]
        let t = get_component(w, eid, "transform")
        let mr = get_component(w, eid, "mesh_renderer")
        if mr["visible"]:
            let model = transform_to_matrix(t)
            let mvp = pack_mvp(model, view, proj)
            gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX, mvp)
            let m = mr["mesh"]
            gpu.cmd_bind_vertex_buffer(cmd, m["vbuf"])
            gpu.cmd_bind_index_buffer(cmd, m["ibuf"])
            gpu.cmd_draw_indexed(cmd, m["index_count"], 1, 0, 0, 0)
        i = i + 1

on_render(eng, game_render)

# ============================================================================
# Run!
# ============================================================================
print "Controls: WASD move | Mouse look (ESC to capture/release) | Q to quit"
run(eng)
print "Demo complete!"
