#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D inputTexture;

layout(push_constant) uniform BloomBlurPC {
    vec4 params; // x=texel_x, y=texel_y, z=horizontal, w=radius
} pc;

const float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.0540540, 0.0162160);

void main() {
    vec2 texelSize = pc.params.xy * max(pc.params.w, 0.001);
    vec2 offset = pc.params.z > 0.5 ? vec2(texelSize.x, 0.0) : vec2(0.0, texelSize.y);
    vec3 result = texture(inputTexture, fragUV).rgb * weights[0];

    for (int i = 1; i < 5; i++) {
        vec2 delta = offset * float(i);
        result += texture(inputTexture, fragUV + delta).rgb * weights[i];
        result += texture(inputTexture, fragUV - delta).rgb * weights[i];
    }

    outColor = vec4(result, 1.0);
}
