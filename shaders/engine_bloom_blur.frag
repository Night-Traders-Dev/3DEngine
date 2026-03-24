#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D sourceTexture;

layout(push_constant) uniform BlurPC {
    vec4 params; // xy=texel_size (1/width, 1/height), z=horizontal (1=h, 0=v), w=unused
} pc;

void main() {
    float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec2 texOffset = pc.params.z > 0.5 ? vec2(pc.params.x, 0.0) : vec2(0.0, pc.params.y);

    vec3 result = texture(sourceTexture, fragUV).rgb * weights[0];
    for (int i = 1; i < 5; i++) {
        result += texture(sourceTexture, fragUV + texOffset * float(i)).rgb * weights[i];
        result += texture(sourceTexture, fragUV - texOffset * float(i)).rgb * weights[i];
    }
    outColor = vec4(result, 1.0);
}
