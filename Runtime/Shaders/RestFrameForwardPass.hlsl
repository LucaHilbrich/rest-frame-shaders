#ifndef REST_FRAME_FORWARD_PASS_INCLUDED
#define REST_FRAME_FORWARD_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#if defined(LOD_FADE_CROSSFADE)
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
#endif
// The noise field (layered FBM, domain warp, per-axis animation, rest-frame radius and
// the lightmap-mask helper) plus all its tunables live in this shared include, so the
// terrain variant (TerrainRestFrame) samples a pixel-identical field. It also pulls in
// the noise primitive selected by the _NOISETYPE_* keyword (Sine / Classic Perlin / Simplex).
#include "RestFrameNoiseField.hlsl"

///////////////////////////////////////////////////////////////////////////////
//                  Surface B inputs                                         //
///////////////////////////////////////////////////////////////////////////////
//
// Surface A reuses the standard SimpleLit material inputs (_BaseMap, _BaseColor,
// _SpecGlossMap, _SpecColor, _BumpMap, _EmissionMap, _EmissionColor, _Cutoff)
// that SimpleLitInput.hlsl already declares - that is also what every other pass
// (shadow / depth / gbuffer / meta) renders with.
//
// Surface B is a second, complete set of the same inputs with a "B" suffix.
// InitializeSurfaceDataB() mirrors InitializeSimpleLitSurfaceData() exactly, just
// reading the B textures/colors. The two surfaces share the feature keywords
// (_NORMALMAP, _EMISSION, _SPECGLOSSMAP/_SPECULAR_COLOR, _GLOSSINESS_FROM_BASE_ALPHA,
// _ALPHATEST_ON) so the variant count is unchanged; only the maps/colors differ.

TEXTURE2D(_BaseMapB);       SAMPLER(sampler_BaseMapB);
TEXTURE2D(_BumpMapB);       SAMPLER(sampler_BumpMapB);
TEXTURE2D(_EmissionMapB);   SAMPLER(sampler_EmissionMapB);
TEXTURE2D(_SpecGlossMapB);  SAMPLER(sampler_SpecGlossMapB);

float4 _BaseMapB_ST;        // tiling/offset for Surface B's base map
half4  _BaseColorB;
half4  _SpecColorB;
half4  _EmissionColorB;

// Clone of InitializeSimpleLitSurfaceData (SimpleLitInput.hlsl) for Surface B.
inline void InitializeSurfaceDataB(float2 uv, out SurfaceData outSurfaceData)
{
    outSurfaceData = (SurfaceData)0;

    half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMapB, sampler_BaseMapB));
    outSurfaceData.alpha = albedoAlpha.a * _BaseColorB.a;
    outSurfaceData.alpha = AlphaDiscard(outSurfaceData.alpha, _Cutoff);

    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColorB.rgb;
    outSurfaceData.albedo = AlphaModulate(outSurfaceData.albedo, outSurfaceData.alpha);

    half4 specularSmoothness = SampleSpecularSmoothness(uv, outSurfaceData.alpha, _SpecColorB, TEXTURE2D_ARGS(_SpecGlossMapB, sampler_SpecGlossMapB));
    outSurfaceData.metallic = 0.0; // unused
    outSurfaceData.specular = specularSmoothness.rgb;
    outSurfaceData.smoothness = specularSmoothness.a;
    outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMapB, sampler_BumpMapB));
    outSurfaceData.occlusion = 1.0;
    outSurfaceData.emission = SampleEmission(uv, _EmissionColorB.rgb, TEXTURE2D_ARGS(_EmissionMapB, sampler_EmissionMapB));
}

// Blend two complete surfaces. `t` (the noise mask, 0..1) picks A at 0 and B at 1.
// normalTS is lerped here and re-normalized later in InitializeInputData.
SurfaceData BlendSurfaceData(SurfaceData a, SurfaceData b, half t)
{
    SurfaceData s;
    s.albedo             = lerp(a.albedo,             b.albedo,             t);
    s.specular           = lerp(a.specular,           b.specular,           t);
    s.metallic           = lerp(a.metallic,           b.metallic,           t);
    s.smoothness         = lerp(a.smoothness,         b.smoothness,         t);
    s.normalTS           = lerp(a.normalTS,           b.normalTS,           t);
    s.emission           = lerp(a.emission,           b.emission,           t);
    s.occlusion          = lerp(a.occlusion,          b.occlusion,          t);
    s.alpha              = lerp(a.alpha,              b.alpha,              t);
    s.clearCoatMask      = lerp(a.clearCoatMask,      b.clearCoatMask,      t);
    s.clearCoatSmoothness = lerp(a.clearCoatSmoothness, b.clearCoatSmoothness, t);
    return s;
}

struct Attributes
{
    float4 positionOS    : POSITION;
    float3 normalOS      : NORMAL;
    float4 tangentOS     : TANGENT;
    float2 texcoord      : TEXCOORD0;
    float2 staticLightmapUV    : TEXCOORD1;
    float2 dynamicLightmapUV    : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 uv                       : TEXCOORD0;    // xy: Surface A uv, zw: Surface B uv

    float3 positionWS                  : TEXCOORD1;    // xyz: posWS

    #ifdef _NORMALMAP
        half4 normalWS                 : TEXCOORD2;    // xyz: normal, w: viewDir.x
        half4 tangentWS                : TEXCOORD3;    // xyz: tangent, w: viewDir.y
        half4 bitangentWS              : TEXCOORD4;    // xyz: bitangent, w: viewDir.z
    #else
        half3  normalWS                : TEXCOORD2;
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        half4 fogFactorAndVertexLight  : TEXCOORD5; // x: fogFactor, yzw: vertex light
    #else
        half  fogFactor                 : TEXCOORD5;
    #endif

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        float4 shadowCoord             : TEXCOORD6;
    #endif

    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);

#ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV : TEXCOORD8; // Dynamic lightmap UVs
#endif

#ifdef USE_APV_PROBE_OCCLUSION
    float4 probeOcclusion : TEXCOORD9;
#endif

    float4 positionCS                  : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;

    inputData.positionWS = input.positionWS;
#if defined(DEBUG_DISPLAY)
    inputData.positionCS = input.positionCS;
#endif

    #ifdef _NORMALMAP
        half3 viewDirWS = half3(input.normalWS.w, input.tangentWS.w, input.bitangentWS.w);
        inputData.tangentToWorld = half3x3(input.tangentWS.xyz, input.bitangentWS.xyz, input.normalWS.xyz);
        inputData.normalWS = TransformTangentToWorld(normalTS, inputData.tangentToWorld);
    #else
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(inputData.positionWS);
        inputData.normalWS = input.normalWS;
    #endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    viewDirWS = SafeNormalize(viewDirWS);

    inputData.viewDirectionWS = viewDirWS;

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        inputData.shadowCoord = input.shadowCoord;
    #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
    #else
        inputData.shadowCoord = float4(0, 0, 0, 0);
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.fogCoord = InitializeInputDataFog(float4(inputData.positionWS, 1.0), input.fogFactorAndVertexLight.x);
        inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
    #else
        inputData.fogCoord = InitializeInputDataFog(float4(inputData.positionWS, 1.0), input.fogFactor);
        inputData.vertexLighting = half3(0, 0, 0);
    #endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

    #if defined(DEBUG_DISPLAY)
    #if defined(DYNAMICLIGHTMAP_ON)
    inputData.dynamicLightmapUV = input.dynamicLightmapUV.xy;
    #endif
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = input.staticLightmapUV;
    #else
    inputData.vertexSH = input.vertexSH;
    #endif
    #if defined(USE_APV_PROBE_OCCLUSION)
    inputData.probeOcclusion = input.probeOcclusion;
    #endif
    #endif
}

void InitializeBakedGIData(Varyings input, inout InputData inputData)
{
#if defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV, input.vertexSH, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
#elif !defined(LIGHTMAP_ON) && (defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2))
    inputData.bakedGI = SAMPLE_GI(input.vertexSH,
        GetAbsolutePositionWS(inputData.positionWS),
        inputData.normalWS,
        inputData.viewDirectionWS,
        input.positionCS.xy,
        input.probeOcclusion,
        inputData.shadowMask);
#else
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
#endif
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard (Simple Lighting) shader
Varyings LitPassVertexSimple(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

#if defined(_FOG_FRAGMENT)
        half fogFactor = 0;
#else
        half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
#endif

    output.uv.xy = TRANSFORM_TEX(input.texcoord, _BaseMap);    // Surface A
    output.uv.zw = TRANSFORM_TEX(input.texcoord, _BaseMapB);   // Surface B
    output.positionWS.xyz = vertexInput.positionWS;
    output.positionCS = vertexInput.positionCS;

#ifdef _NORMALMAP
    half3 viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
    output.normalWS = half4(normalInput.normalWS, viewDirWS.x);
    output.tangentWS = half4(normalInput.tangentWS, viewDirWS.y);
    output.bitangentWS = half4(normalInput.bitangentWS, viewDirWS.z);
#else
    output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
#endif

    OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
#ifdef DYNAMICLIGHTMAP_ON
    output.dynamicLightmapUV = input.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
#endif
    OUTPUT_SH4(vertexInput.positionWS, output.normalWS.xyz, GetWorldSpaceNormalizeViewDir(vertexInput.positionWS), output.vertexSH, output.probeOcclusion);

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
        output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
    #else
        output.fogFactor = fogFactor;
    #endif

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        output.shadowCoord = GetShadowCoord(vertexInput);
    #endif

    return output;
}

// The noise field - all of its tunables plus the FBM / domain-warp / per-axis animation
// pipeline and SampleNoiseField() - now lives in the shared RestFrameNoiseField.hlsl
// (included above), so RestFrame and TerrainRestFrame sample one identical field.

// Baked lightmap luminance for masking. Returns 0 on objects with no baked
// lightmap (e.g. dynamic objects), so the noise is left untouched there.
half SampleBakedLightmapLuminance(Varyings input)
{
#if defined(LIGHTMAP_ON)
    return Luminance(SampleLightmap(input.staticLightmapUV, input.normalWS.xyz));
#else
    return 0.0h;
#endif
}

// Used for StandardSimpleLighting shader
void LitPassFragmentSimple(
    Varyings input
    , out half4 outColor : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
)
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    // Build both complete surfaces from their own maps/colors...
    SurfaceData surfaceDataA;
    InitializeSimpleLitSurfaceData(input.uv.xy, surfaceDataA);

    SurfaceData surfaceDataB;
    InitializeSurfaceDataB(input.uv.zw, surfaceDataB);

    // ...then blend them with the world-space Perlin noise mask. This happens
    // before InitializeInputData so the blended normalTS drives the world normal.
    half noiseMask = SampleNoiseField(input.positionWS);

    // Baked-lightmap mask: where the lightmap is bright, drive the mask toward 0
    // (Surface A). Dark / baked-shadow areas keep the full noise (Surface B).
#if defined(_LIGHTMAPMASK)
    noiseMask = RestFrameApplyLightmapMask(noiseMask, SampleBakedLightmapLuminance(input));
#endif

    SurfaceData surfaceData = BlendSurfaceData(surfaceDataA, surfaceDataB, noiseMask);

#ifdef LOD_FADE_CROSSFADE
    LODFadeCrossFade(input.positionCS);
#endif

    InputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);
    SETUP_DEBUG_TEXTURE_DATA(inputData, UNDO_TRANSFORM_TEX(input.uv.xy, _BaseMap));

#if defined(_DBUFFER)
    ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData);
#endif

    InitializeBakedGIData(input, inputData);

    half4 color = UniversalFragmentBlinnPhong(inputData, surfaceData);

    color.rgb = MixFog(color.rgb, inputData.fogCoord);
    color.a = OutputAlpha(color.a, IsSurfaceTypeTransparent(_Surface));

    outColor = color;

#ifdef _WRITE_RENDERING_LAYERS
    uint renderingLayers = GetMeshRenderingLayer();
    outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
#endif
}

#endif
