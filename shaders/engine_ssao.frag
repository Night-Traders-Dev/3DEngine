#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D positionBuffer;
layout(set = 0, binding = 1) uniform sampler2D normalBuffer;
layout(set = 0, binding = 2) uniform sampler2D noiseTexture;

layout(push_constant) uniform SSAOPC {
    mat4 projection;
    vec4 params; // x=radius, y=bias, z=power, w=kernel_size
} pc;

// Pseudo-random kernel (embedded in shader for simplicity)
const vec3 kernel[16] = vec3[](
    vec3(0.04, 0.04, 0.04), vec3(-0.08, 0.03, 0.06), vec3(0.01, -0.09, 0.07), vec3(0.06, 0.07, -0.03),
    vec3(-0.04, -0.06, 0.09), vec3(0.08, -0.01, 0.05), vec3(-0.02, 0.08, 0.08), vec3(0.05, -0.07, 0.02),
    vec3(-0.09, 0.02, 0.01), vec3(0.03, 0.05, -0.08), vec3(0.07, -0.04, -0.06), vec3(-0.06, -0.03, 0.07),
    vec3(0.02, 0.09, 0.03), vec3(-0.05, -0.08, 0.04), vec3(0.09, 0.06, -0.02), vec3(-0.07, 0.04, 0.05)
);

void main() {
    vec3 fragPos = texture(positionBuffer, fragUV).xyz;
    vec3 normal = normalize(texture(normalBuffer, fragUV).xyz);
    vec3 randomVec = normalize(texture(noiseTexture, fragUV * vec2(textureSize(positionBuffer, 0)) / 4.0).xyz * 2.0 - 1.0);

    vec3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
    vec3 bitangent = cross(normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, normal);

    float occlusion = 0.0;
    int samples = int(min(pc.params.w, 16.0));

    for (int i = 0; i < samples; i++) {
        vec3 samplePos = fragPos + TBN * kernel[i] * pc.params.x;
        vec4 offset = pc.projection * vec4(samplePos, 1.0);
        offset.xyz /= offset.w;
        offset.xy = offset.xy * 0.5 + 0.5;

        float sampleDepth = texture(positionBuffer, offset.xy).z;
        float rangeCheck = smoothstep(0.0, 1.0, pc.params.x / abs(fragPos.z - sampleDepth));
        occlusion += (sampleDepth >= samplePos.z + pc.params.y ? 1.0 : 0.0) * rangeCheck;
    }

    occlusion = 1.0 - (occlusion / float(samples));
    occlusion = pow(occlusion, pc.params.z);
    outColor = vec4(vec3(occlusion), 1.0);
}
