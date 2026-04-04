#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D ssaoTexture;

const float weights[5] = float[](0.06136, 0.24477, 0.38774, 0.24477, 0.06136);

void main() {
    vec2 texelSize = 1.0 / textureSize(ssaoTexture, 0);
    float result = 0.0;
    const int blurRadius = 2;

    for (int x = -blurRadius; x <= blurRadius; x++) {
        for (int y = -blurRadius; y <= blurRadius; y++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float weight = weights[abs(x)] * weights[abs(y)];
            result += texture(ssaoTexture, fragUV + offset).r * weight;
        }
    }

    outColor = vec4(vec3(result), 1.0);
}