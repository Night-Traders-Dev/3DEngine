gc_disable()
# -----------------------------------------
# components.sage - Built-in component types for Sage Engine
# Standard components that most games need
# -----------------------------------------

from math3d import vec3, mat4_identity
from engine_math import transform_identity

# ============================================================================
# Transform Component - position, rotation, scale in world space
# ============================================================================
proc TransformComponent(px, py, pz):
    let c = {}
    c["position"] = vec3(px, py, pz)
    c["rotation"] = vec3(0.0, 0.0, 0.0)
    c["scale"] = vec3(1.0, 1.0, 1.0)
    c["matrix"] = mat4_identity()
    c["dirty"] = true
    return c

proc TransformComponentFull(pos, rot, scl):
    let c = {}
    c["position"] = pos
    c["rotation"] = rot
    c["scale"] = scl
    c["matrix"] = mat4_identity()
    c["dirty"] = true
    return c

# ============================================================================
# Mesh Renderer Component - links entity to a GPU mesh + material
# ============================================================================
proc MeshRendererComponent(mesh_handle, material_id):
    let c = {}
    c["mesh"] = mesh_handle
    c["material"] = material_id
    c["visible"] = true
    c["cast_shadows"] = true
    c["receive_shadows"] = true
    return c

# ============================================================================
# Velocity Component - linear and angular velocity
# ============================================================================
proc VelocityComponent():
    let c = {}
    c["linear"] = vec3(0.0, 0.0, 0.0)
    c["angular"] = vec3(0.0, 0.0, 0.0)
    c["damping"] = 0.98
    return c

# ============================================================================
# Camera Component
# ============================================================================
proc CameraComponent(fov, near, far):
    let c = {}
    c["fov"] = fov
    c["near"] = near
    c["far"] = far
    c["active"] = false
    c["yaw"] = -1.5708
    c["pitch"] = 0.0
    c["sensitivity"] = 0.003
    return c

# ============================================================================
# Light Component
# ============================================================================
proc PointLightComponent(r, g, b, intensity, radius):
    let c = {}
    c["type"] = "point"
    c["color"] = vec3(r, g, b)
    c["intensity"] = intensity
    c["radius"] = radius
    return c

proc DirectionalLightComponent(r, g, b, intensity):
    let c = {}
    c["type"] = "directional"
    c["color"] = vec3(r, g, b)
    c["intensity"] = intensity
    c["cast_shadows"] = true
    return c

# ============================================================================
# Name Component - human-readable name for debugging
# ============================================================================
proc NameComponent(name):
    let c = {}
    c["name"] = name
    return c

# ============================================================================
# Parent Component - scene hierarchy
# ============================================================================
proc ParentComponent(parent_entity):
    let c = {}
    c["parent"] = parent_entity
    c["children"] = []
    return c
