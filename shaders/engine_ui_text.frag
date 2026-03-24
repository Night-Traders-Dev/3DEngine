#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D fontAtlas;

void main() {
    // Font atlas stores glyph intensity in RGB (sRGB texture)
    float glyph = texture(fontAtlas, fragUV).r;
    float alpha = smoothstep(0.02, 0.5, glyph);
    outColor = vec4(fragColor.rgb, fragColor.a * alpha);
}
