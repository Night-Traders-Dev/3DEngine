#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    mat4 model;
    vec4 baseColor;
    vec4 materialParams; // metallic, roughness, unused, unused
    vec4 textureFlags;   // useAlbedo, useNormal, useMR, unused
    vec4 shadowControl;
} pc;

struct Light {
    vec4 position;   // xyz + type (0=point,1=dir,2=spot)
    vec4 color;      // rgb + intensity
    vec4 params;     // radius, inner, outer, unused
};

layout(set = 0, binding = 0) uniform SceneUBO {
    Light lights[16];
    vec4 viewPos;       // xyz + light count
    vec4 ambient;       // rgb + intensity
    vec4 fogParams;     // start, end, density, enable
    vec4 fogColor;
} scene;

layout(set = 1, binding = 0) uniform sampler2D albedoMap;
layout(set = 1, binding = 1) uniform sampler2D normalMap;
layout(set = 1, binding = 2) uniform sampler2D metallicRoughnessMap;

layout(set = 3, binding = 0) uniform sampler2D shadowMap;

layout(set = 3, binding = 1) uniform ShadowUBO {
    mat4 lightVP;
    vec4 shadowParams;   // x=enabled, y=texel_size, z=bias, w=primary directional light index
} shadow_data;

const float PI = 3.14159265359;

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float d = (NdotH * NdotH * (a2 - 1.0) + 1.0);
    return a2 / (PI * d * d);
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    return GeometrySchlickGGX(max(dot(N, V), 0.0), roughness) *
           GeometrySchlickGGX(max(dot(N, L), 0.0), roughness);
}

vec3 FresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

vec3 getNormalFromMap() {
    vec3 tangentNormal = texture(normalMap, fragUV).xyz * 2.0 - 1.0;
    vec3 Q1 = dFdx(fragWorldPos);
    vec3 Q2 = dFdy(fragWorldPos);
    vec2 st1 = dFdx(fragUV);
    vec2 st2 = dFdy(fragUV);
    vec3 N = normalize(fragNormal);
    vec3 T = normalize(Q1 * st2.t - Q2 * st1.t);
    vec3 B = -normalize(cross(N, T));
    mat3 TBN = mat3(T, B, N);
    return normalize(TBN * tangentNormal);
}

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
    vec4 albedoSample = vec4(1.0);
    if (pc.textureFlags.x > 0.5) {
        albedoSample = texture(albedoMap, fragUV);
    }
    vec3 albedo = pow(albedoSample.rgb * pc.baseColor.rgb, vec3(2.2));
    float metallic = pc.materialParams.x;
    float roughness = max(pc.materialParams.y, 0.04);
    if (pc.textureFlags.z > 0.5) {
        vec2 mr = texture(metallicRoughnessMap, fragUV).bg; // glTF convention: B=metallic, G=roughness
        metallic *= mr.x;
        roughness = max(mr.y * max(pc.materialParams.y, 0.04), 0.04);
    }

    vec3 N = normalize(fragNormal);
    if (pc.textureFlags.y > 0.5) {
        N = getNormalFromMap();
    }
    vec3 V = normalize(scene.viewPos.xyz - fragWorldPos);
    vec3 F0 = mix(vec3(0.04), albedo, metallic);

    int lightCount = int(scene.viewPos.w);
    vec3 Lo = vec3(0.0);

    for (int i = 0; i < lightCount && i < 16; i++) {
        int lightType = int(scene.lights[i].position.w);
        vec3 lightColor = scene.lights[i].color.rgb;
        float intensity = scene.lights[i].color.w;
        float range = scene.lights[i].params.x;

        vec3 L;
        float atten = 1.0;

        if (lightType == 1) {
            L = normalize(-scene.lights[i].position.xyz);
        } else {
            vec3 lp = scene.lights[i].position.xyz;
            vec3 toLight = lp - fragWorldPos;
            float dist = length(toLight);
            L = toLight / max(dist, 0.001);
            float r2 = range * range;
            atten = max(1.0 - (dist * dist) / r2, 0.0);
            atten *= atten;
        }
        atten *= intensity;
        float visibility = 1.0;
        if (pc.shadowControl.x > 0.5 && lightType == 1 && i == int(shadow_data.shadowParams.w + 0.5)) {
            visibility = sample_shadow(N, L);
        }

        vec3 H = normalize(V + L);
        float NDF = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);
        vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

        vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
        vec3 specular = (NDF * G * F) / (4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001);
        float NdotL = max(dot(N, L), 0.0);
        Lo += (kD * albedo / PI + specular) * lightColor * atten * NdotL * visibility;
    }

    vec3 ambientColor = scene.ambient.rgb * scene.ambient.w * albedo;
    vec3 color = ambientColor + Lo;

    // Fog
    if (scene.fogParams.w > 0.5) {
        float dist = length(scene.viewPos.xyz - fragWorldPos);
        float fogFactor = clamp((dist - scene.fogParams.x) / (scene.fogParams.y - scene.fogParams.x), 0.0, 1.0);
        color = mix(color, scene.fogColor.rgb, fogFactor);
    }

    outColor = vec4(color, albedoSample.a * pc.baseColor.a);
}
