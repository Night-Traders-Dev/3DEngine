#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D sourceTexture;

layout(push_constant) uniform BloomPC {
    vec4 params; // x=threshold, y=soft_threshold, z=intensity, w=unused
} pc;

void main() {
    vec3 color = texture(sourceTexture, fragUV).rgb;
    float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float soft = brightness - pc.params.x + pc.params.y;
    soft = clamp(soft, 0.0, 2.0 * pc.params.y);
    soft = soft * soft / (4.0 * pc.params.y + 0.00001);
    float contribution = max(soft, brightness - pc.params.x) / max(brightness, 0.00001);
    outColor = vec4(color * contribution * pc.params.z, 1.0);
}
