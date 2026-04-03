#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D inputTexture;

layout(push_constant) uniform BloomExtractPC {
    vec4 params; // x=threshold, y=soft_knee, z=unused, w=highlight_saturation
} pc;

vec3 saturate_color(vec3 color, float amount) {
    float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(lum), color, amount);
}

void main() {
    vec3 color = texture(inputTexture, fragUV).rgb;
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float brightness = max(luminance, max(max(color.r, color.g), color.b) * 0.92);

    float knee = max(pc.params.y, 0.0001);
    float soft = brightness - pc.params.x + knee;
    soft = clamp(soft, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 0.00001);
    float contribution = max(soft, brightness - pc.params.x) / max(brightness, 0.00001);

    vec3 bloom = saturate_color(color, pc.params.w);
    bloom *= mix(vec3(1.0), vec3(1.03, 1.00, 0.96), smoothstep(0.65, 1.55, brightness));
    outColor = vec4(bloom * contribution, 1.0);
}
