#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D fontAtlas;

void main() {
    float alpha = texture(fontAtlas, fragUV).a;
    // Slight sharpening for small text
    alpha = smoothstep(0.1, 0.6, alpha);
    outColor = vec4(fragColor.rgb, fragColor.a * alpha);
}
