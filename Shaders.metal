#include <metal_stdlib>
using namespace metal;

// ============================================================================
// VERTEX STRUCTURES
// ============================================================================

struct VertexIn {
    float2 position  [[attribute(0)]];
    float2 texCoord  [[attribute(1)]];
    float4 color     [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float2 screenPos;    // Original screen position for consistent gradient
    float4 color;
    float4 glowColor;
    float4 outlineColor;
};

struct Uniforms {
    float4x4 projectionMatrix;
    float4 glowColor;
    float4 outlineColor;
    float time;
    float glowIntensity;
    float glowRadius;
    float outlineWidth;
    float softness;
    float2 resolution;
    float lightIntensity;  // 0.0 = dark/unlit, 1.0 = fully lit (LOTR sunrise effect)
    float padding[1];
};

// ============================================================================
// VERTEX SHADER
// ============================================================================

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                               constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.projectionMatrix * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    // Pass normalized screen position (0-1) for consistent gradient across all text
    out.screenPos = in.position / uniforms.resolution;
    out.color = in.color;
    out.glowColor = uniforms.glowColor;
    out.outlineColor = uniforms.outlineColor;
    return out;
}

// ============================================================================
// FRAGMENT SHADER - CINEMATIC SDF TEXT
// ============================================================================

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                texture2d<float> sdfTexture [[texture(0)]],
                                sampler textureSampler [[sampler(0)]],
                                constant Uniforms& uniforms [[buffer(1)]]) {

    // Sample the SDF texture
    float4 sdfSample = sdfTexture.sample(textureSampler, in.texCoord);
    float distance = sdfSample.r;

    // Screen-space derivative for anti-aliasing
    float2 dxdy = fwidth(in.texCoord);
    float texelSize = length(dxdy) * 32.0;

    // Tight edge for sharp text (reduced softness to minimize halo)
    float edgeCenter = 0.5;
    float edgeWidth = uniforms.softness * texelSize * 0.5;  // Tighter edge

    // Core text alpha (sharp edge)
    float textAlpha = smoothstep(edgeCenter - edgeWidth, edgeCenter + edgeWidth, distance);
    
    // ========================================================================
    // UNIFORM METALLIC BRONZE - NO GLOW, NO OUTLINE
    // ========================================================================

    // Deep metallic bronze - rich antique bronze with reddish-brown tones
    float3 metallicBronze = float3(0.72, 0.45, 0.20);  // Dark metallic bronze
    
    // Subtle shimmer
    float shimmer = sin(uniforms.time * 0.5 + in.texCoord.x * 3.0) * 0.02;
    shimmer += sin(uniforms.time * 0.7 + in.texCoord.y * 2.0) * 0.015;
    metallicBronze *= (1.0 + shimmer);

    // ========================================================================
    // LOTR-STYLE SUNRISE/SUNSET - PITCH BLACK TO BRONZE
    // ========================================================================
    
    float light = uniforms.lightIntensity;
    float lightCurve = pow(light, 1.2);
    
    // Final alpha: text alpha scaled by light
    float finalAlpha = textAlpha * lightCurve;
    
    // Hard cutoff - anything below threshold is completely invisible
    if (finalAlpha < 0.05) {
        discard_fragment();  // Completely discard, not even black
    }
    
    // Color scaled by light
    float3 finalColor = metallicBronze * lightCurve;
    
    return float4(finalColor, finalAlpha);
}

// ============================================================================
// ALTERNATIVE: NEON/CYBERPUNK STYLE SHADER
// ============================================================================

fragment float4 fragmentShaderNeon(VertexOut in [[stage_in]],
                                    texture2d<float> sdfTexture [[texture(0)]],
                                    sampler textureSampler [[sampler(0)]],
                                    constant Uniforms& uniforms [[buffer(1)]]) {
    
    float4 sdfSample = sdfTexture.sample(textureSampler, in.texCoord);
    float distance = sdfSample.r;
    
    float2 dxdy = fwidth(in.texCoord);
    float texelSize = length(dxdy) * 32.0;
    
    float edgeCenter = 0.5;
    float edgeWidth = uniforms.softness * texelSize;
    
    // Core neon line (thin glowing stroke)
    float innerEdge = edgeCenter + 0.02;
    float textAlpha = smoothstep(edgeCenter - edgeWidth, edgeCenter + edgeWidth, distance)
                    - smoothstep(innerEdge - edgeWidth, innerEdge + edgeWidth, distance);
    
    // Multi-layer glow for that neon tube look
    float glow1 = smoothstep(edgeCenter - 0.3, edgeCenter, distance);
    float glow2 = smoothstep(edgeCenter - 0.5, edgeCenter, distance);
    float glow3 = smoothstep(edgeCenter - 0.8, edgeCenter, distance);
    
    glow1 = pow(glow1, 3.0) * 0.8;
    glow2 = pow(glow2, 4.0) * 0.4;
    glow3 = pow(glow3, 5.0) * 0.2;
    
    float totalGlow = glow1 + glow2 + glow3;
    
    // Flicker effect
    float flicker = 0.95 + 0.05 * sin(uniforms.time * 30.0 + in.texCoord.x * 10.0);
    totalGlow *= flicker;
    
    // Hot white core + colored glow
    float3 coreColor = float3(1.0, 1.0, 1.0);
    float3 glowColor = in.glowColor.rgb;
    
    float4 result;
    result.rgb = coreColor * textAlpha + glowColor * totalGlow * uniforms.glowIntensity;
    result.a = max(textAlpha, totalGlow * uniforms.glowIntensity) * in.color.a;  // Apply input alpha for fading
    result.rgb *= in.color.a;  // Pre-multiply for correct blending
    
    return result;
}

// ============================================================================
// ALTERNATIVE: CINEMATIC TITLE CARD STYLE
// ============================================================================

fragment float4 fragmentShaderTitle(VertexOut in [[stage_in]],
                                     texture2d<float> sdfTexture [[texture(0)]],
                                     sampler textureSampler [[sampler(0)]],
                                     constant Uniforms& uniforms [[buffer(1)]]) {
    
    float4 sdfSample = sdfTexture.sample(textureSampler, in.texCoord);
    float distance = sdfSample.r;
    
    float2 dxdy = fwidth(in.texCoord);
    float texelSize = length(dxdy) * 32.0;
    
    float edgeCenter = 0.5;
    float edgeWidth = uniforms.softness * texelSize;
    
    // Sharp text with subtle gradient
    float textAlpha = smoothstep(edgeCenter - edgeWidth, edgeCenter + edgeWidth, distance);
    
    // Subtle inner shadow (for depth)
    float innerShadow = smoothstep(edgeCenter + 0.1, edgeCenter + 0.02, distance);
    innerShadow *= 0.3;
    
    // Elegant thin outline
    float outlineOuter = edgeCenter - 0.015;
    float outlineInner = edgeCenter - 0.005;
    float outlineAlpha = smoothstep(outlineOuter - edgeWidth, outlineOuter + edgeWidth, distance)
                       - smoothstep(outlineInner - edgeWidth, outlineInner + edgeWidth, distance);
    
    // Very subtle outer glow (atmospheric)
    float atmosphereGlow = smoothstep(edgeCenter - 0.15, edgeCenter, distance);
    atmosphereGlow = pow(atmosphereGlow, 4.0) * 0.15 * uniforms.glowIntensity;
    
    // Compose with subtle gradient on text
    float3 textColor = mix(in.color.rgb * 0.85, in.color.rgb, in.texCoord.y);
    textColor = textColor * (1.0 - innerShadow); // Apply inner shadow
    
    float4 result;
    result.rgb = in.glowColor.rgb * atmosphereGlow 
               + in.outlineColor.rgb * outlineAlpha 
               + textColor * textAlpha;
    result.a = max(max(atmosphereGlow, outlineAlpha * 0.8), textAlpha) * in.color.a;  // Apply input alpha for fading
    result.rgb *= in.color.a;  // Pre-multiply for correct blending
    
    return result;
}
