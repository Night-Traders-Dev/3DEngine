gc_disable()
# -----------------------------------------
# math3d.sage - 3D Mathematics Library for SageLang
# Vectors, matrices, camera, and projection utilities
# All matrices are column-major flat arrays of 16 floats (matching GLSL/Vulkan)
# -----------------------------------------

import math

let PI = 3.14159265358979323846

proc radians(deg):
    return deg * PI / 180.0

proc degrees(rad):
    return rad * 180.0 / PI

# ============================================================================
# Vector constructors
# ============================================================================
proc vec2(x, y):
    return [x, y]

proc vec3(x, y, z):
    return [x, y, z]

proc vec4(x, y, z, w):
    return [x, y, z, w]

# ============================================================================
# Vec3 operations
# ============================================================================
proc v3_add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

proc v3_sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

proc v3_scale(v, s):
    return [v[0] * s, v[1] * s, v[2] * s]

proc v3_negate(v):
    return [0 - v[0], 0 - v[1], 0 - v[2]]

proc v3_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

proc v3_cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

proc v3_length(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

proc v3_normalize(v):
    let l = v3_length(v)
    if l < 0.000001:
        return [0.0, 0.0, 0.0]
    return [v[0] / l, v[1] / l, v[2] / l]

proc v3_lerp(a, b, t):
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]

proc v3_distance(a, b):
    return v3_length(v3_sub(b, a))

# ============================================================================
# Vec4 operations
# ============================================================================
proc v4_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]

# ============================================================================
# Mat4 constructors (column-major flat array)
# Index: col * 4 + row
# ============================================================================
proc mat4_zero():
    return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

proc mat4_identity():
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

# Access: m[col*4 + row]
proc mat4_get(m, row, col):
    return m[col * 4 + row]

proc mat4_set(m, row, col, val):
    m[col * 4 + row] = val

# ============================================================================
# Mat4 operations
# ============================================================================
proc mat4_mul(a, b):
    let r = mat4_zero()
    let i = 0
    while i < 4:
        let j = 0
        while j < 4:
            let sum = 0.0
            let k = 0
            while k < 4:
                sum = sum + a[k * 4 + i] * b[j * 4 + k]
                k = k + 1
            r[j * 4 + i] = sum
            j = j + 1
        i = i + 1
    return r

proc mat4_mul_vec4(m, v):
    let x = m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12] * v[3]
    let y = m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13] * v[3]
    let z = m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14] * v[3]
    let w = m[3] * v[0] + m[7] * v[1] + m[11] * v[2] + m[15] * v[3]
    return [x, y, z, w]

# ============================================================================
# Transform matrices
# ============================================================================
proc mat4_translate(tx, ty, tz):
    let m = mat4_identity()
    m[12] = tx
    m[13] = ty
    m[14] = tz
    return m

proc mat4_scale(sx, sy, sz):
    let m = mat4_zero()
    m[0] = sx
    m[5] = sy
    m[10] = sz
    m[15] = 1.0
    return m

proc mat4_rotate_x(angle):
    let c = math.cos(angle)
    let s = math.sin(angle)
    let m = mat4_identity()
    m[5] = c
    m[6] = s
    m[9] = 0.0 - s
    m[10] = c
    return m

proc mat4_rotate_y(angle):
    let c = math.cos(angle)
    let s = math.sin(angle)
    let m = mat4_identity()
    m[0] = c
    m[2] = 0.0 - s
    m[8] = s
    m[10] = c
    return m

proc mat4_rotate_z(angle):
    let c = math.cos(angle)
    let s = math.sin(angle)
    let m = mat4_identity()
    m[0] = c
    m[1] = s
    m[4] = 0.0 - s
    m[5] = c
    return m

# ============================================================================
# Projection matrices (Vulkan: Y-flip, depth 0-1)
# ============================================================================
proc mat4_perspective(fov_y, aspect, near, far):
    let f = 1.0 / math.tan(fov_y / 2.0)
    let m = mat4_zero()
    m[0] = f / aspect
    m[5] = 0.0 - f
    m[10] = far / (near - far)
    m[11] = -1.0
    m[14] = (near * far) / (near - far)
    return m

proc mat4_ortho(left, right, bottom, top, near, far):
    let m = mat4_zero()
    m[0] = 2.0 / (right - left)
    m[5] = 2.0 / (top - bottom)
    m[10] = -1.0 / (far - near)
    m[12] = 0.0 - (right + left) / (right - left)
    m[13] = 0.0 - (top + bottom) / (top - bottom)
    m[14] = 0.0 - near / (far - near)
    m[15] = 1.0
    return m

# ============================================================================
# View matrix
# ============================================================================
proc mat4_look_at(eye, center, up):
    let f = v3_normalize(v3_sub(center, eye))
    let s = v3_normalize(v3_cross(f, up))
    let u = v3_cross(s, f)

    let m = mat4_identity()
    m[0] = s[0]
    m[4] = s[1]
    m[8] = s[2]
    m[1] = u[0]
    m[5] = u[1]
    m[9] = u[2]
    m[2] = 0.0 - f[0]
    m[6] = 0.0 - f[1]
    m[10] = 0.0 - f[2]
    m[12] = 0.0 - v3_dot(s, eye)
    m[13] = 0.0 - v3_dot(u, eye)
    m[14] = v3_dot(f, eye)
    return m

# ============================================================================
# Camera helpers
# ============================================================================
proc camera_orbit(angle_x, angle_y, distance, target):
    let cx = math.cos(angle_x)
    let sx = math.sin(angle_x)
    let cy = math.cos(angle_y)
    let sy = math.sin(angle_y)
    let eye = vec3(target[0] + distance * cy * sx, target[1] + distance * sy, target[2] + distance * cy * cx)
    return mat4_look_at(eye, target, vec3(0.0, 1.0, 0.0))

proc camera_fps(pos, yaw, pitch):
    let cy = math.cos(yaw)
    let sy = math.sin(yaw)
    let cp = math.cos(pitch)
    let sp = math.sin(pitch)
    let front = vec3(cy * cp, sp, sy * cp)
    let center = v3_add(pos, front)
    return mat4_look_at(pos, center, vec3(0.0, 1.0, 0.0))

# ============================================================================
# Matrix transpose (for normal matrix)
# ============================================================================
proc mat4_transpose(m):
    let r = mat4_zero()
    let i = 0
    while i < 4:
        let j = 0
        while j < 4:
            r[j * 4 + i] = m[i * 4 + j]
            j = j + 1
        i = i + 1
    return r

# ============================================================================
# To float array (identity — already flat, but useful for documentation)
# ============================================================================
proc mat4_to_floats(m):
    return m

# Push constants helper: pack MVP as 64-byte float array
proc pack_mvp(model, view, proj):
    let mvp = mat4_mul(proj, mat4_mul(view, model))
    return mvp

# ============================================================================
# Matrix inverse (4x4, Cramer's rule)
# ============================================================================
proc mat4_inverse(m):
    let s0 = m[0]*m[5] - m[4]*m[1]
    let s1 = m[0]*m[9] - m[8]*m[1]
    let s2 = m[0]*m[13] - m[12]*m[1]
    let s3 = m[4]*m[9] - m[8]*m[5]
    let s4 = m[4]*m[13] - m[12]*m[5]
    let s5 = m[8]*m[13] - m[12]*m[9]
    let c5 = m[10]*m[15] - m[14]*m[11]
    let c4 = m[6]*m[15] - m[14]*m[7]
    let c3 = m[6]*m[11] - m[10]*m[7]
    let c2 = m[2]*m[15] - m[14]*m[3]
    let c1 = m[2]*m[11] - m[10]*m[3]
    let c0 = m[2]*m[7] - m[6]*m[3]
    let det = s0*c5 - s1*c4 + s2*c3 + s3*c2 - s4*c1 + s5*c0
    if math.abs(det) < 0.0000000001:
        return nil
    let inv_det = 1.0 / det
    let r = [0.0,0.0,0.0,0.0, 0.0,0.0,0.0,0.0, 0.0,0.0,0.0,0.0, 0.0,0.0,0.0,0.0]
    r[0]  = ( m[5]*c5 - m[9]*c4 + m[13]*c3) * inv_det
    r[1]  = (0.0 - m[1]*c5 + m[9]*c2 - m[13]*c1) * inv_det
    r[2]  = ( m[1]*c4 - m[5]*c2 + m[13]*c0) * inv_det
    r[3]  = (0.0 - m[1]*c3 + m[5]*c1 - m[9]*c0) * inv_det
    r[4]  = (0.0 - m[4]*c5 + m[8]*c4 - m[12]*c3) * inv_det
    r[5]  = ( m[0]*c5 - m[8]*c2 + m[12]*c1) * inv_det
    r[6]  = (0.0 - m[0]*c4 + m[4]*c2 - m[12]*c0) * inv_det
    r[7]  = ( m[0]*c3 - m[4]*c1 + m[8]*c0) * inv_det
    r[8]  = ( m[7]*s5 - m[11]*s4 + m[15]*s3) * inv_det
    r[9]  = (0.0 - m[3]*s5 + m[11]*s2 - m[15]*s1) * inv_det
    r[10] = ( m[3]*s4 - m[7]*s2 + m[15]*s0) * inv_det
    r[11] = (0.0 - m[3]*s3 + m[7]*s1 - m[11]*s0) * inv_det
    r[12] = (0.0 - m[6]*s5 + m[10]*s4 - m[14]*s3) * inv_det
    r[13] = ( m[2]*s5 - m[10]*s2 + m[14]*s1) * inv_det
    r[14] = (0.0 - m[2]*s4 + m[6]*s2 - m[14]*s0) * inv_det
    r[15] = ( m[2]*s3 - m[6]*s1 + m[10]*s0) * inv_det
    return r

proc mat4_inverse_safe(m):
    let r = mat4_inverse(m)
    if r == nil:
        return mat4_identity()
    return r

# ============================================================================
# Quaternion math — stored as [w, x, y, z]
# ============================================================================
proc quat(w, x, y, z):
    return [w, x, y, z]

proc quat_identity():
    return [1.0, 0.0, 0.0, 0.0]

proc quat_dot(a, b):
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]

proc quat_length(q):
    return math.sqrt(quat_dot(q, q))

proc quat_normalize(q):
    let l = quat_length(q)
    if l < 0.000001:
        return quat_identity()
    let inv = 1.0 / l
    return [q[0]*inv, q[1]*inv, q[2]*inv, q[3]*inv]

proc quat_conjugate(q):
    return [q[0], 0.0 - q[1], 0.0 - q[2], 0.0 - q[3]]

proc quat_inverse(q):
    let d = quat_dot(q, q)
    if d < 0.000001:
        return quat_identity()
    let inv = 1.0 / d
    return [q[0]*inv, (0.0 - q[1])*inv, (0.0 - q[2])*inv, (0.0 - q[3])*inv]

proc quat_mul(a, b):
    return [
        a[0]*b[0] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3],
        a[0]*b[1] + a[1]*b[0] + a[2]*b[3] - a[3]*b[2],
        a[0]*b[2] - a[1]*b[3] + a[2]*b[0] + a[3]*b[1],
        a[0]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[0]
    ]

proc quat_from_axis_angle(axis, angle):
    let half = angle * 0.5
    let s = math.sin(half)
    let na = v3_normalize(axis)
    return [math.cos(half), na[0]*s, na[1]*s, na[2]*s]

proc quat_from_euler(rx, ry, rz):
    let qx = quat_from_axis_angle(vec3(1.0, 0.0, 0.0), rx)
    let qy = quat_from_axis_angle(vec3(0.0, 1.0, 0.0), ry)
    let qz = quat_from_axis_angle(vec3(0.0, 0.0, 1.0), rz)
    return quat_mul(quat_mul(qy, qx), qz)

proc quat_to_euler(q):
    let sinr_cosp = 2.0 * (q[0]*q[1] + q[2]*q[3])
    let cosr_cosp = 1.0 - 2.0 * (q[1]*q[1] + q[2]*q[2])
    let rx = math.atan2(sinr_cosp, cosr_cosp)
    let sinp = 2.0 * (q[0]*q[2] - q[3]*q[1])
    let ry = 0.0
    if math.abs(sinp) >= 1.0:
        if sinp > 0.0:
            ry = 1.5707963
        else:
            ry = 0.0 - 1.5707963
    else:
        ry = math.asin(sinp)
    let siny_cosp = 2.0 * (q[0]*q[3] + q[1]*q[2])
    let cosy_cosp = 1.0 - 2.0 * (q[2]*q[2] + q[3]*q[3])
    let rz = math.atan2(siny_cosp, cosy_cosp)
    return [rx, ry, rz]

proc quat_to_matrix(q):
    let xx = q[1]*q[1]
    let yy = q[2]*q[2]
    let zz = q[3]*q[3]
    let xy = q[1]*q[2]
    let xz = q[1]*q[3]
    let yz = q[2]*q[3]
    let wx = q[0]*q[1]
    let wy = q[0]*q[2]
    let wz = q[0]*q[3]
    let m = mat4_identity()
    m[0] = 1.0 - 2.0*(yy + zz)
    m[1] = 2.0*(xy + wz)
    m[2] = 2.0*(xz - wy)
    m[4] = 2.0*(xy - wz)
    m[5] = 1.0 - 2.0*(xx + zz)
    m[6] = 2.0*(yz + wx)
    m[8] = 2.0*(xz + wy)
    m[9] = 2.0*(yz - wx)
    m[10] = 1.0 - 2.0*(xx + yy)
    return m

proc quat_rotate_vec3(q, v):
    let qv = [0.0, v[0], v[1], v[2]]
    let r = quat_mul(quat_mul(q, qv), quat_conjugate(q))
    return [r[1], r[2], r[3]]

proc quat_slerp(a, b, t):
    let d = quat_dot(a, b)
    let b2 = [b[0], b[1], b[2], b[3]]
    if d < 0.0:
        b2 = [0.0 - b[0], 0.0 - b[1], 0.0 - b[2], 0.0 - b[3]]
        d = 0.0 - d
    if d > 0.9995:
        let r = [a[0] + t*(b2[0] - a[0]), a[1] + t*(b2[1] - a[1]), a[2] + t*(b2[2] - a[2]), a[3] + t*(b2[3] - a[3])]
        return quat_normalize(r)
    let theta = math.acos(d)
    let sin_theta = math.sin(theta)
    let wa = math.sin((1.0 - t) * theta) / sin_theta
    let wb = math.sin(t * theta) / sin_theta
    return [wa*a[0] + wb*b2[0], wa*a[1] + wb*b2[1], wa*a[2] + wb*b2[2], wa*a[3] + wb*b2[3]]
