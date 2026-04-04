gc_disable()
# Simple debug renderer - renders a fullscreen triangle to test rendering pipeline

import gpu

proc create_debug_renderer():
    let dr = {}
    dr["pipeline"] = nil
    dr["pipe_layout"] = nil
    dr["vertex_buffer"] = nil
    dr["vertex_count"] = 0
    return dr

proc destroy_debug_renderer(dr):
    if dr == nil:
        return
    # Cleanup handled by gpu shutdown

proc render_debug_triangle(cmd, dr):
    if cmd == nil:
        return
    
    # Draw a simple fullscreen triangle using basic geometry
    # This is a placeholder - in reality we'd bind pipeline and buffers
    # For now, just verify the frame is being submitted
    # (The renderer is already clearing the framebuffer with sky color)

# Minimal test - just verify drawing infrastructure works
proc debug_render_voxel_world(cmd, voxel_world, camera_pos, camera_view, camera_proj):
    if cmd == nil or voxel_world == nil:
        return
    
    # Placeholder - actual voxel rendering would:
    # 1. Bind voxel rendering pipeline
    # 2. Set up camera UBO with view/proj matrices
    # 3. For each visible chunk:
    #    - Bind chunk mesh
    #    - Call gpu.cmd_draw_indexed() for each block type
    # 4. Handle LOD and frustum culling
    
    # For now, the clear color is enough to show the renderer is working
