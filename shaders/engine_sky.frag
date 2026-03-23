#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform SkyPC {
    vec4 sunDir;         // xyz = normalized sun direction, w = sun intensity
    vec4 skyColorTop;    // rgb = zenith color, w = unused
    vec4 skyColorHoriz;  // rgb = horizon color, w = unused
    vec4 groundColor;    // rgb = ground color, w = unused
    vec4 params;         // x = aspect, y = fov, z = time, w = sun size
    mat4 invViewRot;     // inverse view rotation (no translation)
} sky;

const float PI = 3.14159265;

void main() {
    // Reconstruct view ray
    vec2 uv = fragUV * 2.0 - 1.0;
    uv.x *= sky.params.x;  // aspect ratio
    float fovScale = tan(sky.params.y * 0.5);
    vec3 rd = normalize(vec3(uv.x * fovScale, -uv.y * fovScale, -1.0));

    // Apply camera rotation
    rd = (sky.invViewRot * vec4(rd, 0.0)).xyz;
    rd = normalize(rd);

    // Sky gradient based on vertical angle
    float horizon = rd.y;

    // Sky color
    vec3 skyCol;
    if (horizon >= 0.0) {
        // Above horizon: gradient from horizon to zenith
        float t = pow(horizon, 0.4);
        skyCol = mix(sky.skyColorHoriz.rgb, sky.skyColorTop.rgb, t);
    } else {
        // Below horizon: ground fade
        float t = pow(clamp(-horizon * 3.0, 0.0, 1.0), 0.5);
        skyCol = mix(sky.skyColorHoriz.rgb, sky.groundColor.rgb, t);
    }

    // Sun disc
    vec3 sunDir = normalize(sky.sunDir.xyz);
    float sunDot = max(dot(rd, sunDir), 0.0);
    float sunSize = sky.params.w;
    float sunDisc = smoothstep(1.0 - sunSize * 0.01, 1.0 - sunSize * 0.001, sunDot);
    vec3 sunColor = vec3(1.0, 0.95, 0.8) * sky.sunDir.w;
    skyCol += sunColor * sunDisc;

    // Sun glow
    float sunGlow = pow(sunDot, 8.0) * 0.3 * sky.sunDir.w;
    skyCol += vec3(1.0, 0.7, 0.4) * sunGlow;

    // Horizon haze
    float haze = exp(-abs(horizon) * 4.0) * 0.15;
    skyCol += vec3(1.0, 0.9, 0.8) * haze;

    // Gamma
    skyCol = pow(skyCol, vec3(1.0 / 2.2));
    outColor = vec4(skyCol, 1.0);
}
