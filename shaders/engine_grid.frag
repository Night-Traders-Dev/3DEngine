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

    // Colors (Unreal-style dark gray)
    vec3 bgColor = vec3(0.16, 0.16, 0.18);
    vec3 smallGridColor = vec3(0.22, 0.22, 0.24);
    vec3 bigGridColor = vec3(0.28, 0.28, 0.30);
    vec3 xAxisColor = vec3(0.7, 0.15, 0.15);  // Red for X
    vec3 zAxisColor = vec3(0.15, 0.15, 0.7);   // Blue for Z

    vec3 color = bgColor;
    color = mix(color, smallGridColor, smallGrid * 0.6 * fade);
    color = mix(color, bigGridColor, bigGrid * 0.8 * fade);
    color = mix(color, xAxisColor, xAxis * fade);
    color = mix(color, zAxisColor, zAxis * fade);

    float alpha = max(smallGrid * 0.4, bigGrid * 0.6);
    alpha = max(alpha, max(xAxis, zAxis));
    alpha *= fade;

    // Background always visible, grid fades
    float bgAlpha = fade * 0.95 + 0.05;
    color = mix(vec3(0.14, 0.14, 0.16), color, bgAlpha);

    outColor = vec4(color, 1.0);
}
