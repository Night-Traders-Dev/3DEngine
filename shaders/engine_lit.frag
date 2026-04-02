#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;

layout(location = 0) out vec4 outColor;

// Light types: 0 = point, 1 = directional, 2 = spot
struct Light {
    vec4 position;       // xyz = position/direction, w = type
    vec4 color;          // rgb = color, w = intensity
    vec4 params;         // x = radius/range, y = inner cone, z = outer cone, w = unused
};

layout(set = 0, binding = 0) uniform SceneUBO {
    Light lights[16];
    vec4 viewPos;        // xyz = camera pos, w = light count
    vec4 ambient;        // rgb = ambient color, w = ambient intensity
    vec4 fogParams;      // x = fog start, y = fog end, z = fog density, w = fog enable
    vec4 fogColor;       // rgb = fog color, w = unused
} scene;

layout(set = 2, binding = 0) uniform sampler2D shadowMap;

layout(set = 2, binding = 1) uniform ShadowUBO {
    mat4 lightVP;
    vec4 shadowParams;   // x=enabled, y=texel_size, z=bias, w=primary directional light index
} shadow_data;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    mat4 model;
    vec4 baseColor;
} pc;

float sample_shadow(vec3 normal, vec3 lightDir) {
    if (shadow_data.shadowParams.x < 0.5) {
        return 1.0;
    }

    vec4 lightClip = shadow_data.lightVP * vec4(fragWorldPos, 1.0);
    vec3 proj = lightClip.xyz / max(lightClip.w, 0.0001);
    vec2 uv = proj.xy * 0.5 + 0.5;
    float currentDepth = proj.z * 0.5 + 0.5;
    if (currentDepth <= 0.0 || currentDepth >= 1.0 ||
        uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0) {
        return 1.0;
    }

    float texel = shadow_data.shadowParams.y;
    float biasBase = shadow_data.shadowParams.z;
    float ndotl = max(dot(normal, lightDir), 0.0);
    float bias = max(biasBase * (1.0 - ndotl), biasBase * 0.25);

    float shadow = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float closestDepth = texture(shadowMap, uv + vec2(x, y) * texel).r;
            if (currentDepth - bias > closestDepth) {
                shadow += 1.0;
            }
        }
    }
    return 1.0 - shadow / 9.0;
}

void main() {
    vec3 baseColor = pc.baseColor.rgb;

    vec3 N = normalize(fragNormal);
    vec3 V = normalize(scene.viewPos.xyz - fragWorldPos);
    int lightCount = int(scene.viewPos.w);

    // Ambient
    vec3 result = scene.ambient.rgb * scene.ambient.w * baseColor;

    for (int i = 0; i < lightCount && i < 16; i++) {
        int lightType = int(scene.lights[i].position.w);
        vec3 lightColor = scene.lights[i].color.rgb;
        float intensity = scene.lights[i].color.w;
        float range = scene.lights[i].params.x;

        vec3 L;
        float atten = 1.0;

        if (lightType == 1) {
            // Directional light
            L = normalize(-scene.lights[i].position.xyz);
        } else {
            // Point or spot light
            vec3 lightPos = scene.lights[i].position.xyz;
            vec3 toLight = lightPos - fragWorldPos;
            float dist = length(toLight);
            L = toLight / max(dist, 0.001);

            // Attenuation
            float r2 = range * range;
            atten = max(1.0 - (dist * dist) / r2, 0.0);
            atten *= atten;

            if (lightType == 2) {
                // Spot light cone
                vec3 spotDir = normalize(-scene.lights[i].position.xyz);
                float theta = dot(L, spotDir);
                float inner = scene.lights[i].params.y;
                float outer = scene.lights[i].params.z;
                float epsilon = inner - outer;
                float spotFactor = clamp((theta - outer) / max(epsilon, 0.001), 0.0, 1.0);
                atten *= spotFactor;
            }
        }

        atten *= intensity;
        float visibility = 1.0;
        if (lightType == 1 && i == int(shadow_data.shadowParams.w + 0.5)) {
            visibility = sample_shadow(N, L);
        }

        // Diffuse
        float diff = max(dot(N, L), 0.0);

        // Specular (Blinn-Phong)
        vec3 H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), 64.0);

        result += baseColor * lightColor * diff * atten * visibility;
        result += lightColor * spec * atten * 0.3 * visibility;
    }

    // Fog
    if (scene.fogParams.w > 0.5) {
        float dist = length(scene.viewPos.xyz - fragWorldPos);
        float fogStart = scene.fogParams.x;
        float fogEnd = scene.fogParams.y;
        float fogFactor = clamp((dist - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
        result = mix(result, scene.fogColor.rgb, fogFactor);
    }

    // Gamma correction
    result = pow(result, vec3(1.0 / 2.2));
    outColor = vec4(result, pc.baseColor.a);
}
