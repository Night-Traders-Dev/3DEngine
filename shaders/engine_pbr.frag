#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

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

void main() {
    vec4 albedoSample = texture(albedoMap, fragUV);
    vec3 albedo = pow(albedoSample.rgb, vec3(2.2)); // sRGB to linear
    vec2 mr = texture(metallicRoughnessMap, fragUV).bg; // glTF convention: B=metallic, G=roughness
    float metallic = mr.x;
    float roughness = max(mr.y, 0.04);

    vec3 N = getNormalFromMap();
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

        vec3 H = normalize(V + L);
        float NDF = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);
        vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

        vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
        vec3 specular = (NDF * G * F) / (4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001);
        float NdotL = max(dot(N, L), 0.0);
        Lo += (kD * albedo / PI + specular) * lightColor * atten * NdotL;
    }

    vec3 ambientColor = scene.ambient.rgb * scene.ambient.w * albedo;
    vec3 color = ambientColor + Lo;

    // Fog
    if (scene.fogParams.w > 0.5) {
        float dist = length(scene.viewPos.xyz - fragWorldPos);
        float fogFactor = clamp((dist - scene.fogParams.x) / (scene.fogParams.y - scene.fogParams.x), 0.0, 1.0);
        color = mix(color, scene.fogColor.rgb, fogFactor);
    }

    // Reinhard tone mapping + gamma
    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));
    outColor = vec4(color, albedoSample.a);
}
