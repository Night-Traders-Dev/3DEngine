#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D hdrTexture;
layout(set = 0, binding = 1) uniform sampler2D bloomTexture;

layout(push_constant) uniform TonemapPC {
    vec4 params0; // x=exposure, y=bloom_strength, z=tonemap_mode, w=gamma
    vec4 params1; // x=contrast, y=saturation, z=warmth, w=vignette_strength
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

vec3 apply_contrast(vec3 color, float contrast) {
    return clamp((color - vec3(0.5)) * contrast + vec3(0.5), 0.0, 1.0);
}

vec3 apply_saturation(vec3 color, float saturation) {
    float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(lum), color, saturation);
}

vec3 apply_warmth(vec3 color, float warmth) {
    vec3 warmTint = vec3(1.0 + warmth * 0.18, 1.0 + warmth * 0.05, 1.0 - warmth * 0.18);
    return clamp(color * warmTint, 0.0, 1.0);
}

void main() {
    vec3 hdr = texture(hdrTexture, fragUV).rgb;
    vec3 bloom = texture(bloomTexture, fragUV).rgb;

    // Composite bloom
    vec3 color = hdr + bloom * pc.params0.y;

    // Apply exposure
    color *= pc.params0.x;

    // Tone mapping
    int mode = int(pc.params0.z);
    if (mode == 0) {
        color = reinhardTonemap(color);
    } else if (mode == 1) {
        color = acesTonemap(color);
    } else {
        vec3 W = vec3(11.2);
        color = uncharted2Tonemap(color * 2.0) / uncharted2Tonemap(W);
    }

    color = apply_contrast(color, pc.params1.x);
    color = apply_saturation(color, pc.params1.y);
    color = apply_warmth(color, pc.params1.z);

    vec2 centered = fragUV * 2.0 - 1.0;
    float vignette = 1.0 - dot(centered, centered) * pc.params1.w;
    color *= clamp(vignette, 0.72, 1.0);

    // Gamma correction
    float gamma = pc.params0.w;
    color = pow(color, vec3(1.0 / gamma));

    outColor = vec4(color, 1.0);
}
