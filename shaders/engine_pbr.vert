#version 450

const int MAX_SKIN_JOINTS = 128;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    mat4 model;
    vec4 baseColor;
    vec4 materialParams;
    vec4 textureFlags;
    vec4 shadowControl;
} pc;

layout(set = 2, binding = 0) uniform SkinningUBO {
    mat4 joints[MAX_SKIN_JOINTS];
} skin_data;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;
layout(location = 3) in vec4 inJoints;
layout(location = 4) in vec4 inWeights;

layout(location = 0) out vec3 fragWorldPos;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec2 fragUV;

void main() {
    ivec4 joint_indices = clamp(ivec4(inJoints + vec4(0.5)), ivec4(0), ivec4(MAX_SKIN_JOINTS - 1));
    mat4 skin_matrix =
        skin_data.joints[joint_indices.x] * inWeights.x +
        skin_data.joints[joint_indices.y] * inWeights.y +
        skin_data.joints[joint_indices.z] * inWeights.z +
        skin_data.joints[joint_indices.w] * inWeights.w;
    vec4 localPos = skin_matrix * vec4(inPosition, 1.0);
    vec3 localNormal = mat3(skin_matrix) * inNormal;
    vec4 worldPos = pc.model * localPos;
    gl_Position = pc.mvp * localPos;
    fragWorldPos = worldPos.xyz;
    fragNormal = normalize(mat3(pc.model) * localNormal);
    fragUV = inUV;
}
