#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform SkyPC {
    vec4 sunDir;
    vec4 skyColorTop;
    vec4 skyColorHoriz;
    vec4 groundColor;
    vec4 params;     // x = aspect, y = fov, z = time, w = sun size
    mat4 invViewRot;
} sky;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += noise2(p) * amp;
        p = p * 2.03 + vec2(17.0, 11.0);
        amp *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = fragUV * 2.0 - 1.0;
    uv.x *= sky.params.x;
    float fovScale = tan(sky.params.y * 0.5);
    vec3 rd = normalize(vec3(uv.x * fovScale, -uv.y * fovScale, -1.0));
    rd = normalize((sky.invViewRot * vec4(rd, 0.0)).xyz);

    float horizon = rd.y;
    vec3 sunDir = normalize(sky.sunDir.xyz);
    float sunDot = max(dot(rd, sunDir), 0.0);
    float sunHeight = clamp(sunDir.y * 0.5 + 0.5, 0.0, 1.0);
    float sunScatter = pow(max(dot(normalize(vec3(rd.x, max(rd.y, -0.06), rd.z)), sunDir), 0.0), 6.0);

    vec3 zenith = mix(sky.skyColorTop.rgb * 0.62 + vec3(0.02, 0.03, 0.06), sky.skyColorTop.rgb, sunHeight);
    vec3 horizonBase = mix(sky.skyColorHoriz.rgb * vec3(0.95, 0.98, 1.03), sky.skyColorHoriz.rgb, sunHeight);
    vec3 warmHorizon = mix(horizonBase, vec3(1.00, 0.74, 0.50), clamp((1.0 - sunHeight) * 0.08 + sunScatter * 0.24, 0.0, 1.0));

    vec3 skyCol;
    if (horizon >= 0.0) {
        float t = pow(clamp(horizon, 0.0, 1.0), 0.42);
        skyCol = mix(warmHorizon, zenith, t);
    } else {
        float t = pow(clamp(-horizon * 3.0, 0.0, 1.0), 0.55);
        skyCol = mix(warmHorizon, sky.groundColor.rgb, t);
    }

    float haze = exp(-abs(horizon) * 5.8);
    skyCol += vec3(0.56, 0.66, 0.88) * haze * 0.020;

    if (horizon > -0.02) {
        vec2 cloudUv = rd.xz / max(rd.y + 0.24, 0.18);
        cloudUv = cloudUv * 0.18 + vec2(sky.params.z * 0.005, sky.params.z * 0.003);
        float cloudField = fbm(cloudUv);
        float cloudMask = smoothstep(0.58, 0.78, cloudField) * smoothstep(-0.02, 0.12, horizon);
        vec3 cloudColor = mix(vec3(0.90, 0.94, 1.00), vec3(1.00, 0.80, 0.62), pow(sunDot, 8.0));
        skyCol = mix(skyCol, cloudColor, cloudMask * 0.20);
    }

    float sunDisc = smoothstep(1.0 - sky.params.w * 0.010, 1.0 - sky.params.w * 0.0012, sunDot);
    float sunGlow = pow(sunDot, 10.0) * 0.46 * sky.sunDir.w;
    float wideGlow = pow(sunDot, 2.4) * 0.16 * sky.sunDir.w;
    vec3 sunColor = mix(vec3(1.00, 0.78, 0.54), vec3(1.00, 0.95, 0.84), sunHeight);
    skyCol += sunColor * sunDisc * (1.6 + sky.sunDir.w);
    skyCol += sunColor * sunGlow * 0.8;
    skyCol += vec3(1.00, 0.72, 0.48) * wideGlow * 0.62;

    outColor = vec4(skyCol, 1.0);
}
