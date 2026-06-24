#ifndef SKYBOX_REST_FRAME_FORWARD_PASS_INCLUDED
#define SKYBOX_REST_FRAME_FORWARD_PASS_INCLUDED

// Forward pass for "Skybox/RestFrame": an unlit URP skybox that cross-fades between two cubemap
// skies (Surface A and Surface B) using the shared rest-frame anchored noise field. Unlike
// RestFrame / TerrainRestFrame this samples the field along the per-pixel VIEW RAY (the sky has
// no surface position) via SampleNoiseFieldDirection() - an orientation-only anchor (w = 0, no
// translation), with no radius and no lightmap mask. Direction handling mirrors the in-repo
// Horizontal Skybox (the world-space ray arrives in the skybox mesh's TEXCOORD0, exactly as the
// built-in Skybox/* shaders), ported to URP HLSL.
//
// Only the noise MASK is rest-frame-anchored; the two cubemaps are sampled with the plain
// world-space ray direction, so the sky imagery stays a normal fixed sky while the reveal
// pattern lives in the rest frame (mirrors RestFrame, where only the mask is anchored, not UVs).

// Core.hlsl brings everything the shared field needs: _Time and TWO_PI (via core Common.hlsl),
// the TEXTURECUBE / SAMPLE_TEXTURECUBE macros, TransformObjectToHClip and the XR stereo macros.
// (The field's RestFrameApplyLightmapMask takes a pre-computed luminance, so no Color.hlsl needed.)
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

// The shared rest-frame noise field: SampleNoiseFieldDirection(dirWS) -> [0,1] A<->B mask, built
// from the same FBM / domain-warp / per-axis animation core the other two shaders use.
#include "RestFrameNoiseField.hlsl"

// ---- Surface A / B: two complete cubemap skies the noise cross-fades between ----
TEXTURECUBE(_CubemapA);     SAMPLER(sampler_CubemapA);
TEXTURECUBE(_CubemapB);     SAMPLER(sampler_CubemapB);

half4 _TintA;       // HDR tint / color multiplier for Surface A
half4 _TintB;       // HDR tint / color multiplier for Surface B
half  _Exposure;    // overall brightness multiplier on the blended result

struct Attributes
{
    float4 positionOS : POSITION;
    float3 texcoord   : TEXCOORD0;   // world-space ray direction supplied by the skybox mesh
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float3 dirWS      : TEXCOORD0;    // interpolated view ray (normalized in the fragment)
    UNITY_VERTEX_OUTPUT_STEREO
};

Varyings SkyboxRestFrameVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.dirWS      = input.texcoord;
    return output;
}

half4 SkyboxRestFrameFragment(Varyings input) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    // Per-pixel normalize: the interpolated ray is not unit length, and the noise's angular
    // frequency depends on |dir|, so this keeps features an even size across the sky.
    float3 dir = normalize(input.dirWS);

    // Surface A / B: two complete cubemap skies, sampled with the un-anchored world ray so the
    // imagery itself stays a normal fixed sky.
    half3 colA = SAMPLE_TEXTURECUBE(_CubemapA, sampler_CubemapA, dir).rgb * _TintA.rgb;
    half3 colB = SAMPLE_TEXTURECUBE(_CubemapB, sampler_CubemapB, dir).rgb * _TintB.rgb;

    // Rest-frame anchored reveal mask (orientation-only): 0 = Surface A, 1 = Surface B.
    half mask = SampleNoiseFieldDirection(dir);

    half3 col = lerp(colA, colB, mask) * _Exposure;
    return half4(col, 1.0h);
}

#endif
