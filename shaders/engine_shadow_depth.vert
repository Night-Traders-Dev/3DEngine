#version 450

const int MAX_SKIN_JOINTS = 128;

layout(push_constant) uniform PushConstants {
    mat4 lightMVP;
} pc;

layout(set = 0, binding = 0) uniform SkinningUBO {
    mat4 joints[MAX_SKIN_JOINTS];
} skin_data;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;
layout(location = 3) in vec4 inJoints;
layout(location = 4) in vec4 inWeights;

void main() {
    ivec4 joint_indices = clamp(ivec4(inJoints + vec4(0.5)), ivec4(0), ivec4(MAX_SKIN_JOINTS - 1));
    mat4 skin_matrix =
        skin_data.joints[joint_indices.x] * inWeights.x +
        skin_data.joints[joint_indices.y] * inWeights.y +
        skin_data.joints[joint_indices.z] * inWeights.z +
        skin_data.joints[joint_indices.w] * inWeights.w;
    gl_Position = pc.lightMVP * (skin_matrix * vec4(inPosition, 1.0));
}
