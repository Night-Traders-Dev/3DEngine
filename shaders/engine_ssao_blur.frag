#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D ssaoTexture;

void main() {
    vec2 texelSize = 1.0 / textureSize(ssaoTexture, 0);
    float result = 0.0;
    const int blurSize = 2;

    for (int x = -blurSize; x <= blurSize; x++) {
        for (int y = -blurSize; y <= blurSize; y++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            result += texture(ssaoTexture, fragUV + offset).r;
        }
    }

    result /= float((blurSize * 2 + 1) * (blurSize * 2 + 1));
    outColor = vec4(vec3(result), 1.0);
}