#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in float fragDist;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform GridPC {
    mat4 viewProj;
    vec4 params;  // x=gridSize, y=fadeStart, z=fadeEnd, w=lineWidth
} pc;

float gridLine(float coord, float width) {
    float d = fract(coord);
    d = min(d, 1.0 - d);
    return 1.0 - smoothstep(0.0, width, d);
}

void main() {
    float gridSize = pc.params.x;
    float fadeStart = pc.params.y;
    float fadeEnd = pc.params.z;
    float lineWidth = pc.params.w;

    // Small grid
    float gx = gridLine(fragWorldPos.x / gridSize, lineWidth);
    float gz = gridLine(fragWorldPos.z / gridSize, lineWidth);
    float smallGrid = max(gx, gz);

    // Large grid (every 10 units)
    float bigSize = gridSize * 10.0;
    float bgx = gridLine(fragWorldPos.x / bigSize, lineWidth * 0.5);
    float bgz = gridLine(fragWorldPos.z / bigSize, lineWidth * 0.5);
    float bigGrid = max(bgx, bgz);

    // Axis highlights
    float axisWidth = lineWidth * 0.3;
    float xAxis = 1.0 - smoothstep(0.0, axisWidth * gridSize, abs(fragWorldPos.z));
    float zAxis = 1.0 - smoothstep(0.0, axisWidth * gridSize, abs(fragWorldPos.x));

    // Distance fade
    float fade = 1.0 - smoothstep(fadeStart, fadeEnd, fragDist);

    // Forge Engine viewport (neutral dark grey)
    vec3 bgColor = vec3(0.141, 0.141, 0.141);
    vec3 smallGridColor = vec3(0.19, 0.19, 0.19);
    vec3 bigGridColor = vec3(0.24, 0.24, 0.24);
    vec3 xAxisColor = vec3(0.90, 0.22, 0.22);  // Red
    vec3 zAxisColor = vec3(0.22, 0.40, 0.90);  // Blue

    vec3 color = bgColor;
    color = mix(color, smallGridColor, smallGrid * fade);
    color = mix(color, bigGridColor, bigGrid * fade);
    color = mix(color, xAxisColor, xAxis * fade);
    color = mix(color, zAxisColor, zAxis * fade);

    outColor = vec4(color, 1.0);
}
