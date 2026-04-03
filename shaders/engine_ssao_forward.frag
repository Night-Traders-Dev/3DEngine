#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D depthBuffer;
layout(set = 0, binding = 1) uniform sampler2D noiseTexture;

layout(push_constant) uniform SSAOPC {
    mat4 projection;
    mat4 invProjection;
    vec4 params; // x=radius, y=bias, z=power, w=kernel_size
    vec2 screenSize;
} pc;

// Pseudo-random kernel (embedded in shader for simplicity)
const vec3 kernel[32] = vec3[](
    vec3(0.04, 0.04, 0.04), vec3(-0.08, 0.03, 0.06), vec3(0.01, -0.09, 0.07), vec3(0.06, 0.07, -0.03),
    vec3(-0.04, -0.06, 0.09), vec3(0.08, -0.01, 0.05), vec3(-0.02, 0.08, 0.08), vec3(0.05, -0.07, 0.02),
    vec3(-0.09, 0.02, 0.01), vec3(0.03, 0.05, -0.08), vec3(0.07, -0.04, -0.06), vec3(-0.06, -0.03, 0.07),
    vec3(0.02, 0.09, 0.03), vec3(-0.05, -0.08, 0.04), vec3(0.09, 0.06, -0.02), vec3(-0.07, 0.04, 0.05),
    vec3(0.01, 0.02, 0.03), vec3(-0.03, 0.01, 0.04), vec3(0.02, -0.04, 0.05), vec3(0.04, 0.03, -0.02),
    vec3(-0.05, -0.02, 0.06), vec3(0.06, -0.01, 0.03), vec3(-0.01, 0.05, 0.04), vec3(0.03, -0.06, 0.02),
    vec3(-0.04, 0.02, 0.01), vec3(0.05, 0.04, -0.03), vec3(0.07, -0.03, -0.05), vec3(-0.02, -0.05, 0.06),
    vec3(0.03, 0.06, 0.02), vec3(-0.06, -0.04, 0.03), vec3(0.04, 0.05, -0.01), vec3(-0.03, 0.04, 0.05)
);

vec3 reconstructPosition(vec2 uv, float depth) {
    vec4 clipSpace = vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 viewSpace = pc.invProjection * clipSpace;
    return viewSpace.xyz / viewSpace.w;
}

vec3 reconstructNormal(vec3 pos) {
    // Approximate normal from depth gradients
    vec2 texelSize = 1.0 / pc.screenSize;
    float depth = texture(depthBuffer, fragUV).r;

    float depthLeft = texture(depthBuffer, fragUV + vec2(-texelSize.x, 0.0)).r;
    float depthRight = texture(depthBuffer, fragUV + vec2(texelSize.x, 0.0)).r;
    float depthUp = texture(depthBuffer, fragUV + vec2(0.0, texelSize.y)).r;
    float depthDown = texture(depthBuffer, fragUV + vec2(0.0, -texelSize.y)).r;

    vec3 posLeft = reconstructPosition(fragUV + vec2(-texelSize.x, 0.0), depthLeft);
    vec3 posRight = reconstructPosition(fragUV + vec2(texelSize.x, 0.0), depthRight);
    vec3 posUp = reconstructPosition(fragUV + vec2(0.0, texelSize.y), depthUp);
    vec3 posDown = reconstructPosition(fragUV + vec2(0.0, -texelSize.y), depthDown);

    vec3 dx = posRight - posLeft;
    vec3 dy = posUp - posDown;

    return normalize(cross(dx, dy));
}

void main() {
    float depth = texture(depthBuffer, fragUV).r;
    if (depth >= 1.0) {
        outColor = vec4(1.0);
        return;
    }

    vec3 fragPos = reconstructPosition(fragUV, depth);
    vec3 normal = reconstructNormal(fragPos);

    vec3 randomVec = normalize(texture(noiseTexture, fragUV * pc.screenSize / 4.0).xyz * 2.0 - 1.0);

    vec3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
    vec3 bitangent = cross(normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, normal);

    float occlusion = 0.0;
    int samples = int(min(pc.params.w, 32.0));

    for (int i = 0; i < samples; i++) {
        vec3 samplePos = fragPos + TBN * kernel[i] * pc.params.x;
        vec4 offset = pc.projection * vec4(samplePos, 1.0);
        offset.xyz /= offset.w;
        offset.xy = offset.xy * 0.5 + 0.5;

        if (offset.x < 0.0 || offset.x > 1.0 || offset.y < 0.0 || offset.y > 1.0) continue;

        float sampleDepth = texture(depthBuffer, offset.xy).r;
        vec3 samplePosView = reconstructPosition(offset.xy, sampleDepth);

        float rangeCheck = smoothstep(0.0, 1.0, pc.params.x / abs(fragPos.z - samplePosView.z));
        occlusion += (samplePosView.z >= samplePos.z + pc.params.y ? 1.0 : 0.0) * rangeCheck;
    }

    occlusion = 1.0 - (occlusion / float(samples));
    occlusion = pow(occlusion, pc.params.z);
    outColor = vec4(vec3(occlusion), 1.0);
}