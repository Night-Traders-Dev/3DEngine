#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D hdrTexture;
layout(set = 0, binding = 1) uniform sampler2D bloomTexture;

layout(push_constant) uniform TonemapPC {
    vec4 params; // x=exposure, y=bloom_strength, z=tonemap_mode (0=reinhard,1=aces,2=uncharted), w=gamma
} pc;

vec3 reinhardTonemap(vec3 color) {
    return color / (color + vec3(1.0));
}

vec3 acesTonemap(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 uncharted2Tonemap(vec3 x) {
    float A = 0.15, B = 0.50, C = 0.10, D = 0.20, E = 0.02, F = 0.30;
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

void main() {
    vec3 hdr = texture(hdrTexture, fragUV).rgb;
    vec3 bloom = texture(bloomTexture, fragUV).rgb;

    // Composite bloom
    vec3 color = hdr + bloom * pc.params.y;

    // Apply exposure
    color *= pc.params.x;

    // Tone mapping
    int mode = int(pc.params.z);
    if (mode == 0) {
        color = reinhardTonemap(color);
    } else if (mode == 1) {
        color = acesTonemap(color);
    } else {
        vec3 W = vec3(11.2);
        color = uncharted2Tonemap(color * 2.0) / uncharted2Tonemap(W);
    }

    // Gamma correction
    float gamma = pc.params.w;
    color = pow(color, vec3(1.0 / gamma));

    outColor = vec4(color, 1.0);
}
