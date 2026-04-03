#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;

layout(location = 0) out vec4 outColor;

struct Light {
    vec4 position;
    vec4 color;
    vec4 params;
};

layout(set = 0, binding = 0) uniform SceneUBO {
    Light lights[16];
    vec4 viewPos;
    vec4 ambient;
    vec4 fogParams;
    vec4 fogColor;
} scene;

layout(set = 2, binding = 0) uniform sampler2D shadowMap;

layout(set = 2, binding = 1) uniform ShadowUBO {
    mat4 lightVP;
    vec4 shadowParams;
} shadow_data;

layout(set = 3, binding = 0) uniform MaterialUBO {
    vec4 baseColor;
    vec4 surfaceControl; // x = receive shadows, y = voxel detail, z = block id, w = face id
} material_data;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    mat4 model;
} pc;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec3 saturate_color(vec3 color, float amount) {
    float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(lum), color, amount);
}

bool is_foliage_like(int blockId) {
    return blockId == 1 || blockId == 5 || blockId == 9 || blockId == 10;
}

vec3 voxel_palette_color(int blockId, int faceId, vec3 fallbackColor) {
    if (blockId == 1) {
        if (faceId == 0) return vec3(0.31, 0.63, 0.21);
        if (faceId == 2) return vec3(0.39, 0.25, 0.13);
        return vec3(0.46, 0.34, 0.16);
    }
    if (blockId == 2) return vec3(0.46, 0.28, 0.15);
    if (blockId == 3) return vec3(0.44, 0.48, 0.54);
    if (blockId == 4) {
        if (faceId == 1) return vec3(0.49, 0.32, 0.16);
        return vec3(0.69, 0.53, 0.26);
    }
    if (blockId == 5) return vec3(0.19, 0.43, 0.15);
    if (blockId == 6) return vec3(0.72, 0.54, 0.26);
    if (blockId == 7) return vec3(0.79, 0.72, 0.53);
    if (blockId == 8) return vec3(0.13, 0.30, 0.62);
    if (blockId == 9) return vec3(0.78, 0.29, 0.46);
    if (blockId == 10) return vec3(0.52, 0.82, 0.94);
    return fallbackColor;
}

vec3 voxel_detail_color(vec3 baseColor, float blockIdValue, float faceIdValue, vec2 uv) {
    int blockId = int(blockIdValue + 0.5);
    int faceId = int(faceIdValue + 0.5);
    vec2 tileUV = clamp(uv, vec2(0.0), vec2(0.999));
    vec2 texel = floor(tileUV * 16.0);
    float noiseA = hash21(texel + vec2(float(blockId) * 17.0, float(faceId) * 29.0));
    float noiseB = hash21(texel.yx + vec2(float(blockId) * 11.0 + 5.0, float(faceId) * 13.0 + 3.0));
    vec3 color = voxel_palette_color(blockId, faceId, baseColor) * mix(0.93, 1.09, noiseA);

    if (blockId == 1) {
        if (faceId == 0) {
            color *= mix(0.96, 1.22, noiseA);
            if (noiseB > 0.84) {
                color *= 1.08;
            }
        } else if (faceId == 1) {
            float grassBand = step(12.0, texel.y);
            vec3 dirt = vec3(0.49, 0.37, 0.16) * mix(0.90, 1.05, noiseA);
            vec3 grass = vec3(0.22, 0.68, 0.18) * mix(0.96, 1.20, noiseB);
            color = mix(dirt, grass, grassBand);
        } else {
            color *= mix(0.86, 1.02, noiseA);
        }
    } else if (blockId == 2) {
        color *= mix(0.90, 1.05, noiseA);
        if (noiseB > 0.82) {
            color *= 0.95;
        }
    } else if (blockId == 3) {
        float crack = step(0.86, hash21(texel * vec2(1.0, 2.0) + vec2(7.0, 3.0)));
        color *= mix(0.84, 1.07, noiseA);
        color -= crack * 0.06;
        color += vec3(0.01, 0.02, 0.04) * noiseB;
    } else if (blockId == 4) {
        if (faceId == 1) {
            float grain = sin((texel.x + noiseB * 3.0) * 0.9);
            color *= 0.96 + grain * 0.08;
        } else {
            vec2 centered = texel - vec2(7.5);
            float rings = sin(length(centered) * 1.65 + noiseA * 3.0);
            color *= 0.98 + rings * 0.06;
        }
    } else if (blockId == 5) {
        color *= mix(0.86, 1.22, noiseA);
        if (noiseB > 0.74) {
            color *= 1.10;
        }
        if (noiseA < 0.16) {
            color *= 0.84;
        }
    } else if (blockId == 6) {
        float plankLine = step(0.5, fract((texel.y + float(faceId) * 2.0) / 4.0));
        color *= mix(0.94, 1.10, noiseA);
        color *= mix(0.94, 1.08, plankLine);
    } else if (blockId == 7) {
        float dune = sin((texel.x + texel.y * 0.5) * 0.7 + noiseB * 3.0);
        color *= 0.97 + dune * 0.05;
        color += vec3(0.06, 0.04, 0.00) * noiseA;
    } else if (blockId == 8) {
        float ripple = sin((texel.x * 0.7 + texel.y * 0.4) + noiseA * 5.0);
        color *= 0.90 + ripple * 0.06;
        color += vec3(0.00, 0.08, 0.14) * noiseB;
    } else if (blockId == 9) {
        float petals = step(0.82, noiseB) + step(0.90, noiseA);
        color *= mix(0.90, 1.16, noiseA);
        color += vec3(0.12, 0.02, 0.10) * petals;
    } else if (blockId == 10) {
        float shard = step(0.74, abs(sin((texel.x - texel.y) * 0.85 + noiseA * 5.0)));
        color *= mix(0.92, 1.18, noiseB);
        color += vec3(0.08, 0.12, 0.18) * shard;
    }

    return clamp(color, 0.0, 1.0);
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
    vec3 baseColor = material_data.baseColor.rgb;
    float sceneTime = scene.fogColor.w;
    int voxelBlockId = int(material_data.surfaceControl.z + 0.5);
    int voxelFaceId = int(material_data.surfaceControl.w + 0.5);
    bool waterLike = voxelBlockId == 8;
    if (material_data.surfaceControl.y > 0.5) {
        baseColor = voxel_detail_color(baseColor, material_data.surfaceControl.z, material_data.surfaceControl.w, fragUV);
    }

    vec3 N = normalize(fragNormal);
    vec3 V = normalize(scene.viewPos.xyz - fragWorldPos);
    int lightCount = int(scene.viewPos.w);
    float upness = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    bool foliageLike = is_foliage_like(voxelBlockId);
    float outAlpha = material_data.baseColor.a;
    if (waterLike) {
        float wave0 = sin(fragWorldPos.x * 0.28 + fragWorldPos.z * 0.16 + sceneTime * 1.35);
        float wave1 = cos(fragWorldPos.z * 0.24 - fragWorldPos.x * 0.14 - sceneTime * 1.10);
        float wave2 = sin((fragWorldPos.x + fragWorldPos.z) * 0.18 + sceneTime * 0.72);
        vec3 rippleNormal = normalize(vec3((wave0 + wave2 * 0.45) * 0.18, 1.0, (wave1 - wave2 * 0.35) * 0.18));
        float rippleMix = voxelFaceId == 0 ? 0.72 : 0.26;
        N = normalize(mix(N, rippleNormal, rippleMix));
        upness = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    }

    vec3 result = scene.ambient.rgb * scene.ambient.w * baseColor;
    vec3 skyBounce = mix(vec3(0.05, 0.04, 0.04), vec3(0.18, 0.36, 0.76), upness);
    result += baseColor * skyBounce * mix(0.05, 0.13, upness);
    result += baseColor * vec3(0.08, 0.05, 0.03) * (1.0 - upness) * 0.08;
    if (waterLike) {
        vec3 reflectDir = reflect(-V, N);
        float skyMix = clamp(reflectDir.y * 0.5 + 0.5, 0.0, 1.0);
        vec3 reflectedSky = mix(vec3(0.96, 0.72, 0.58), vec3(0.16, 0.38, 0.86), pow(skyMix, 0.72));
        float baseFresnel = pow(1.0 - max(dot(N, V), 0.0), 4.0);
        float waterPulse = 0.5 + 0.5 * sin(sceneTime * 0.35 + fragWorldPos.x * 0.04 + fragWorldPos.z * 0.07);
        vec3 deepWater = vec3(0.05, 0.18, 0.33);
        vec3 shallowWater = vec3(0.12, 0.42, 0.58);
        result = mix(result * 0.68, reflectedSky, 0.18 + baseFresnel * 0.34);
        result = mix(result, mix(deepWater, shallowWater, waterPulse), 0.14 + upness * 0.08);
        outAlpha = clamp(max(outAlpha, 0.46 + baseFresnel * 0.24), 0.0, 0.84);
    }

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
            vec3 lightPos = scene.lights[i].position.xyz;
            vec3 toLight = lightPos - fragWorldPos;
            float dist = length(toLight);
            L = toLight / max(dist, 0.001);

            float r2 = range * range;
            atten = max(1.0 - (dist * dist) / r2, 0.0);
            atten *= atten;

            if (lightType == 2) {
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
        if (material_data.surfaceControl.x > 0.5 && lightType == 1 && i == int(shadow_data.shadowParams.w + 0.5)) {
            visibility = sample_shadow(N, L);
        }

        float ndotl = max(dot(N, L), 0.0);
        float wrappedDiffuse = clamp(dot(N, L) * 0.65 + 0.35, 0.0, 1.0);
        float diff = mix(ndotl, wrappedDiffuse, 0.18);
        vec3 H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), 40.0);
        float fresnel = pow(1.0 - max(dot(N, V), 0.0), 3.0);
        if (waterLike) {
            diff *= voxelFaceId == 0 ? 0.26 : 0.14;
            spec = pow(max(dot(N, H), 0.0), voxelFaceId == 0 ? 96.0 : 52.0);
            fresnel = pow(1.0 - max(dot(N, V), 0.0), 4.5);
        }

        vec3 sunTint = mix(lightColor, vec3(1.0, 0.78, 0.48), lightType == 1 ? 0.25 : 0.10);
        vec3 diffuseTerm = baseColor * sunTint * diff * atten * visibility;
        vec3 specularTerm = sunTint * spec * atten * (0.10 + fresnel * 0.06) * visibility;
        if (waterLike) {
            diffuseTerm *= 0.75;
            specularTerm *= voxelFaceId == 0 ? 1.95 : 1.20;
            specularTerm += sunTint * fresnel * atten * 0.05 * visibility;
            if (lightType == 1) {
                float sparkle = pow(max(dot(reflect(-L, N), V), 0.0), voxelFaceId == 0 ? 220.0 : 120.0);
                specularTerm += sunTint * sparkle * atten * (0.55 + fresnel * 0.60) * visibility;
            }
        }

        if (foliageLike && lightType == 1) {
            float trans = pow(clamp(1.0 - ndotl, 0.0, 1.0), 1.5) * (0.35 + 0.65 * max(dot(-L, V), 0.0));
            diffuseTerm += baseColor * vec3(1.0, 0.76, 0.44) * trans * atten * 0.10 * visibility;
        }

        result += diffuseTerm;
        result += specularTerm;
    }

    result *= mix(0.80, 1.00, upness);
    if (waterLike) {
        result = saturate_color(result, 1.18);
    } else {
        result = saturate_color(result, material_data.surfaceControl.y > 0.5 ? 1.18 : 1.05);
    }

    if (scene.fogParams.w > 0.5) {
        float dist = length(scene.viewPos.xyz - fragWorldPos);
        float fogStart = scene.fogParams.x;
        float fogEnd = scene.fogParams.y;
        float linearFog = clamp((dist - fogStart) / max(fogEnd - fogStart, 0.0001), 0.0, 1.0);
        float expFog = 1.0 - exp(-dist * scene.fogParams.z * 0.010);
        float fogFactor = clamp(mix(linearFog, expFog, 0.35), 0.0, 1.0);
        vec3 fogColor = scene.fogColor.rgb;
        float horizonGlow = pow(clamp(1.0 - upness, 0.0, 1.0), 1.5);
        fogColor = mix(fogColor, vec3(0.96, 0.78, 0.62), horizonGlow * 0.07);
        if (waterLike) {
            fogColor = mix(fogColor, vec3(0.30, 0.50, 0.78), 0.22);
            fogFactor *= 0.76;
        }
        result = mix(result, fogColor, fogFactor);
    }

    result = max(result - vec3(0.01), vec3(0.0));
    outColor = vec4(result, outAlpha);
}
