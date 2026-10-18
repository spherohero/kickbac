#include <metal_stdlib>
using namespace metal;

// Broad, frosted folds echo the breath star's six arms. The fine grain is
// stationary, so the slowly moving light doesn't shimmer behind small text.
[[ stitchable ]] half4 kickBACLight(float2 position, half4 color, float2 size,
                                  float time, float strength) {
    float2 origin = float2(0.5, 0.48);
    float2 p = (position - size * origin) / max(size.x, 1.0);
    float t = time * 0.12;
    float2 warped = p + 0.075 * float2(sin(p.y * 3.1 + t), cos(p.x * 3.4 - t * 0.8));
    float radius = length(warped);
    float angle = atan2(warped.y, warped.x);

    float starEdge = 0.63 + 0.12 * cos(angle * 6.0 - t * 0.35);
    float fold = radius - starEdge;
    float satin = exp(-abs(fold) * 9.0);
    float glint = exp(-abs(fold - 0.025) * 65.0);
    float wave = 0.5 + 0.5 * sin(warped.x * 5.0 + warped.y * 2.8
                                + sin(warped.y * 3.0 - t) + t * 0.6);
    float ribbon = wave * wave * wave * wave;
    float halo = exp(-radius * radius * 1.7);

    // Keep the readings in the quiet center of the light.
    float quietCenter = mix(0.15, 1.0, smoothstep(0.18, 0.65, radius));
    float light = (0.56 * satin + 0.13 * glint + 0.31 * ribbon) * quietCenter;
    float3 cool = float3(0.73, 0.83, 1.0);
    float3 warm = float3(1.0, 0.88, 0.79);
    float3 tint = mix(cool, warm, 0.5 + 0.5 * sin(angle * 2.0 + t * 0.3));
    float grain = fract(sin(dot(floor(position), float2(12.9898, 78.233))) * 43758.5453) - 0.5;

    float3 charcoal = float3(0.105, 0.107, 0.115) + halo * 0.025;
    charcoal += strength * (tint * light * 0.19 + grain * 0.006);

    return half4(half3(charcoal) * color.a, color.a);
}

// The welcome material stays inside the existing star's alpha silhouette.
// It shares Home's warm/cool palette, with broader pearl folds for the smaller object.
[[ stitchable ]] half4 kickBACWelcomeStar(float2 position, half4 color, float2 size,
                                        float time, float progress) {
    float2 p = (position - size * 0.5) / max(size.x, 1.0);
    float t = time * 0.18;
    float2 warped = p + 0.035 * float2(sin(p.y * 5.0 + t), cos(p.x * 4.0 - t));
    float angle = atan2(warped.y, warped.x);
    float radius = length(warped);
    float fold = sin(warped.x * 8.0 + warped.y * 5.0 + sin(angle * 3.0) * radius * 2.0 - t);
    float satin = smoothstep(-0.75, 0.85, fold);
    float seam = exp(-abs(fold - 0.45) * 16.0);
    float3 cool = float3(0.73, 0.83, 1.0);
    float3 warm = float3(1.0, 0.88, 0.79);
    float3 tint = mix(cool, warm, 0.5 + 0.5 * sin(angle * 2.0 + t * 0.3));
    float grain = fract(sin(dot(floor(position), float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    float3 pearl = mix(float3(0.87, 0.88, 0.91), tint, 0.28);
    pearl *= 0.64 + 0.34 * satin;
    pearl += seam * 0.07 + grain * 0.008;
    pearl = mix(pearl, float3(1.0), clamp(progress, 0.0, 1.0) * 0.72);
    return half4(half3(clamp(pearl, 0.0, 1.0)) * color.a, color.a);
}
