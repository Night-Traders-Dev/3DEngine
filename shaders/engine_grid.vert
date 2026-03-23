#version 450

layout(push_constant) uniform GridPC {
    mat4 viewProj;
    vec4 params;  // x=gridSize, y=fadeStart, z=fadeEnd, w=lineWidth
} pc;

layout(location = 0) out vec3 fragWorldPos;
layout(location = 1) out float fragDist;

// Fullscreen quad covering a large ground plane
const vec3 positions[6] = vec3[](
    vec3(-1, 0, -1), vec3( 1, 0, -1), vec3( 1, 0,  1),
    vec3(-1, 0, -1), vec3( 1, 0,  1), vec3(-1, 0,  1)
);

void main() {
    float extent = 500.0;
    vec3 pos = positions[gl_VertexIndex] * extent;
    fragWorldPos = pos;
    vec4 clip = pc.viewProj * vec4(pos, 1.0);
    fragDist = length(pos.xz);
    gl_Position = clip;
}
