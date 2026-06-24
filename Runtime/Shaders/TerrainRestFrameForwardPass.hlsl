#ifndef TERRAIN_REST_FRAME_FORWARD_PASS_INCLUDED
#define TERRAIN_REST_FRAME_FORWARD_PASS_INCLUDED

// Forward pass for "VR/TerrainRestFrame": standard URP terrain (Surface A = the painted
// splat layers) with the rest-frame anchored noise field revealing a second, complete
// PBR surface (Surface B) over it. Structurally this is the stock URP TerrainLit forward
// pass (splat assembly identical to the stock TerrainLit passes); the only additions are
// Surface B and the A->B blend by SampleNoiseField(). Only the ForwardLit pass uses this
// file - all other terrain passes (shadow / depth / gbuffer / meta) use stock URP terrain
// includes, exactly like RestFrame customizes only its ForwardLit pass.

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DBuffer.hlsl"

// Shared rest-frame noise field (the same code RestFrame.shader's field is built from):
// SampleNoiseField(positionWS) -> [0,1] A<->B mask, RestFrameApplyLightmapMask() helper.
#include "RestFrameNoiseField.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 texcoord : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 uvMainAndLM              : TEXCOORD0; // xy: control, zw: lightmap
    #ifndef TERRAIN_SPLAT_BASEPASS
        float4 uvSplat01                : TEXCOORD1; // xy: splat0, zw: splat1
        float4 uvSplat23                : TEXCOORD2; // xy: splat2, zw: splat3
    #endif

    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half4 normal                    : TEXCOORD3;    // xyz: normal, w: viewDir.x
        half4 tangent                   : TEXCOORD4;    // xyz: tangent, w: viewDir.y
        half4 bitangent                 : TEXCOORD5;    // xyz: bitangent, w: viewDir.z
    #else
        half3 normal                    : TEXCOORD3;
        half3 vertexSH                  : TEXCOORD4; // SH
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        half4 fogFactorAndVertexLight   : TEXCOORD6; // x: fogFactor, yzw: vertex light
    #else
        half  fogFactor                 : TEXCOORD6;
    #endif

    float3 positionWS               : TEXCOORD7;

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        float4 shadowCoord              : TEXCOORD8;
    #endif

#if defined(DYNAMICLIGHTMAP_ON)
    float2 dynamicLightmapUV        : TEXCOORD9;
#endif

#ifdef USE_APV_PROBE_OCCLUSION
    float4 probeOcclusion           : TEXCOORD10;
#endif

    float4 clipPos                  : SV_POSITION;
    UNITY_VERTEX_OUTPUT_STEREO
};

void InitializeInputData(Varyings IN, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;

    inputData.positionWS = IN.positionWS;
    inputData.positionCS = IN.clipPos;

    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half3 viewDirWS = half3(IN.normal.w, IN.tangent.w, IN.bitangent.w);
        inputData.tangentToWorld = half3x3(-IN.tangent.xyz, IN.bitangent.xyz, IN.normal.xyz);
        inputData.normalWS = TransformTangentToWorld(normalTS, inputData.tangentToWorld);
        half3 SH = 0;
    #elif defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
        float2 sampleCoords = (IN.uvMainAndLM.xy / _TerrainHeightmapRecipSize.zw + 0.5f) * _TerrainHeightmapRecipSize.xy;
        half3 normalWS = TransformObjectToWorldNormal(normalize(SAMPLE_TEXTURE2D(_TerrainNormalmapTexture, sampler_TerrainNormalmapTexture, sampleCoords).rgb * 2 - 1));
        half3 tangentWS = cross(GetObjectToWorldMatrix()._13_23_33, normalWS);
        inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(-tangentWS, cross(normalWS, tangentWS), normalWS));
        half3 SH = IN.vertexSH;
    #else
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
        inputData.normalWS = IN.normal;
        half3 SH = IN.vertexSH;
    #endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        inputData.shadowCoord = IN.shadowCoord;
    #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
    #else
        inputData.shadowCoord = float4(0, 0, 0, 0);
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.fogCoord = InitializeInputDataFog(float4(IN.positionWS, 1.0), IN.fogFactorAndVertexLight.x);
        inputData.vertexLighting = IN.fogFactorAndVertexLight.yzw;
    #else
    inputData.fogCoord = InitializeInputDataFog(float4(IN.positionWS, 1.0), IN.fogFactor);
    #endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.clipPos);

    #if defined(DEBUG_DISPLAY)
    #if defined(DYNAMICLIGHTMAP_ON)
    inputData.dynamicLightmapUV = IN.dynamicLightmapUV;
    #endif
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = IN.uvMainAndLM.zw;
    #else
    inputData.vertexSH = SH;
    #endif
    #if defined(USE_APV_PROBE_OCCLUSION)
    inputData.probeOcclusion = IN.probeOcclusion;
    #endif
    #endif
}

void InitializeBakedGIData(Varyings IN, inout InputData inputData)
{
    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
    half3 SH = 0;
    #else
    half3 SH = IN.vertexSH;
    #endif

#if defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(IN.uvMainAndLM.zw, IN.dynamicLightmapUV, SH, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(IN.uvMainAndLM.zw);
#elif !defined(LIGHTMAP_ON) && (defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2))
    inputData.bakedGI = SAMPLE_GI(SH,
        GetAbsolutePositionWS(inputData.positionWS),
        inputData.normalWS,
        inputData.viewDirectionWS,
        inputData.positionCS.xy,
        IN.probeOcclusion,
        inputData.shadowMask);
#else
    inputData.bakedGI = SAMPLE_GI(IN.uvMainAndLM.zw, SH, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(IN.uvMainAndLM.zw);
#endif
}

#ifndef TERRAIN_SPLAT_BASEPASS

void NormalMapMix(float4 uvSplat01, float4 uvSplat23, inout half4 splatControl, inout half3 mixedNormal)
{
    #if defined(_NORMALMAP)
        half3 nrm = half(0.0);
        nrm += splatControl.r * UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal0, sampler_Normal0, uvSplat01.xy), _NormalScale0);
        nrm += splatControl.g * UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal1, sampler_Normal0, uvSplat01.zw), _NormalScale1);
        nrm += splatControl.b * UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal2, sampler_Normal0, uvSplat23.xy), _NormalScale2);
        nrm += splatControl.a * UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal3, sampler_Normal0, uvSplat23.zw), _NormalScale3);

        // avoid risk of NaN when normalizing.
        #if !HALF_IS_FLOAT
            nrm.z += half(0.01);
        #else
            nrm.z += 1e-5f;
        #endif

        mixedNormal = normalize(nrm.xyz);
    #endif
}

void SplatmapMix(float4 uvMainAndLM, float4 uvSplat01, float4 uvSplat23, inout half4 splatControl, out half weight, out half4 mixedDiffuse, out half4 defaultSmoothness, inout half3 mixedNormal)
{
    half4 diffAlbedo[4];

    diffAlbedo[0] = SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0, uvSplat01.xy);
    diffAlbedo[1] = SAMPLE_TEXTURE2D(_Splat1, sampler_Splat0, uvSplat01.zw);
    diffAlbedo[2] = SAMPLE_TEXTURE2D(_Splat2, sampler_Splat0, uvSplat23.xy);
    diffAlbedo[3] = SAMPLE_TEXTURE2D(_Splat3, sampler_Splat0, uvSplat23.zw);

    // This might be a bit of a gamble -- the assumption here is that if the diffuseMap has no
    // alpha channel, then diffAlbedo[n].a = 1.0 (and _DiffuseHasAlphaN = 0.0)
    // Prior to coming in, _SmoothnessN is actually set to max(_DiffuseHasAlphaN, _SmoothnessN)
    // This means that if we have an alpha channel, _SmoothnessN is locked to 1.0 and
    // otherwise, the true slider value is passed down and diffAlbedo[n].a == 1.0.
    defaultSmoothness = half4(diffAlbedo[0].a, diffAlbedo[1].a, diffAlbedo[2].a, diffAlbedo[3].a);
    defaultSmoothness *= half4(_Smoothness0, _Smoothness1, _Smoothness2, _Smoothness3);

#ifndef _TERRAIN_BLEND_HEIGHT // density blending
    if(_NumLayersCount <= 4)
    {
        // 20.0 is the number of steps in inputAlphaMask (Density mask. We decided 20 empirically)
        half4 opacityAsDensity = saturate((half4(diffAlbedo[0].a, diffAlbedo[1].a, diffAlbedo[2].a, diffAlbedo[3].a) - (1 - splatControl)) * 20.0);
        opacityAsDensity += 0.001h * splatControl;      // if all weights are zero, default to what the blend mask says
        half4 useOpacityAsDensityParam = { _DiffuseRemapScale0.w, _DiffuseRemapScale1.w, _DiffuseRemapScale2.w, _DiffuseRemapScale3.w }; // 1 is off
        splatControl = lerp(opacityAsDensity, splatControl, useOpacityAsDensityParam);
    }
#endif

    // Now that splatControl has changed, we can compute the final weight and normalize
    weight = dot(splatControl, 1.0h);

#ifdef TERRAIN_SPLAT_ADDPASS
    clip(weight <= 0.005h ? -1.0h : 1.0h);
#endif

#ifndef _TERRAIN_BASEMAP_GEN
    // Normalize weights before lighting and restore weights in final modifier functions so that the overal
    // lighting result can be correctly weighted.
    splatControl /= (weight + HALF_MIN);
#endif

    mixedDiffuse = 0.0h;
    mixedDiffuse += diffAlbedo[0] * half4(_DiffuseRemapScale0.rgb * splatControl.rrr, 1.0h);
    mixedDiffuse += diffAlbedo[1] * half4(_DiffuseRemapScale1.rgb * splatControl.ggg, 1.0h);
    mixedDiffuse += diffAlbedo[2] * half4(_DiffuseRemapScale2.rgb * splatControl.bbb, 1.0h);
    mixedDiffuse += diffAlbedo[3] * half4(_DiffuseRemapScale3.rgb * splatControl.aaa, 1.0h);

    NormalMapMix(uvSplat01, uvSplat23, splatControl, mixedNormal);
}

#endif

#ifdef _TERRAIN_BLEND_HEIGHT
void HeightBasedSplatModify(inout half4 splatControl, in half4 masks[4])
{
    // heights are in mask blue channel, we multiply by the splat Control weights to get combined height
    half4 splatHeight = half4(masks[0].b, masks[1].b, masks[2].b, masks[3].b) * splatControl.rgba;
    half maxHeight = max(splatHeight.r, max(splatHeight.g, max(splatHeight.b, splatHeight.a)));

    // Ensure that the transition height is not zero.
    half transition = max(_HeightTransition, 1e-5);

    // This sets the highest splat to "transition", and everything else to a lower value relative to that, clamping to zero
    // Then we clamp this to zero and normalize everything
    half4 weightedHeights = splatHeight + transition - maxHeight.xxxx;
    weightedHeights = max(0, weightedHeights);

    // We need to add an epsilon here for active layers (hence the blendMask again)
    // so that at least a layer shows up if everything's too low.
    weightedHeights = (weightedHeights + 1e-6) * splatControl;

    // Normalize (and clamp to epsilon to keep from dividing by zero)
    half sumHeight = max(dot(weightedHeights, half4(1, 1, 1, 1)), 1e-6);
    splatControl = weightedHeights / sumHeight.xxxx;
}
#endif

void SplatmapFinalColor(inout half4 color, half fogCoord)
{
    color.rgb *= color.a;

    #ifdef TERRAIN_SPLAT_ADDPASS
        color.rgb = MixFogColor(color.rgb, half3(0,0,0), fogCoord);
    #else
        color.rgb = MixFog(color.rgb, fogCoord);
    #endif
}

void SetupTerrainDebugTextureData(inout InputData inputData, float2 uv)
{
    #if defined(DEBUG_DISPLAY)
        #if defined(TERRAIN_SPLAT_ADDPASS)
            if (_DebugMipInfoMode != DEBUGMIPINFOMODE_NONE)
            {
                discard; // Layer 4 & beyond are done additively, doesn't make sense for the mipmap streaming debug views -> stop.
            }
        #endif

        switch (_DebugMipMapTerrainTextureMode)
        {
            case DEBUGMIPMAPMODETERRAINTEXTURE_CONTROL:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Control), _Control);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER0:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat0), _Splat0);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER1:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat1), _Splat1);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER2:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat2), _Splat2);
                break;
            case DEBUGMIPMAPMODETERRAINTEXTURE_LAYER3:
                SETUP_DEBUG_TEXTURE_DATA_FOR_TEX(inputData, TRANSFORM_TEX(uv, _Splat3), _Splat3);
                break;
            default:
                break;
        }

        // TERRAIN_STREAM_INFO: no streamInfo will have been set (no MeshRenderer); set status to "6" to reflect in the debug status that this is a terrain
        // also, set the per-material status to "4" to indicate warnings
        inputData.streamInfo = TERRAIN_STREAM_INFO;
    #endif
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

Varyings SplatmapVert(Attributes v)
{
    Varyings o = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    TerrainInstancing(v.positionOS, v.normalOS, v.texcoord);

    VertexPositionInputs Attributes = GetVertexPositionInputs(v.positionOS.xyz);

    o.uvMainAndLM.xy = v.texcoord;
    o.uvMainAndLM.zw = v.texcoord * unity_LightmapST.xy + unity_LightmapST.zw;

    #ifndef TERRAIN_SPLAT_BASEPASS
        o.uvSplat01.xy = TRANSFORM_TEX(v.texcoord, _Splat0);
        o.uvSplat01.zw = TRANSFORM_TEX(v.texcoord, _Splat1);
        o.uvSplat23.xy = TRANSFORM_TEX(v.texcoord, _Splat2);
        o.uvSplat23.zw = TRANSFORM_TEX(v.texcoord, _Splat3);
    #endif

#if defined(DYNAMICLIGHTMAP_ON)
    o.dynamicLightmapUV = v.texcoord * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
#endif

    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(Attributes.positionWS);
        float4 vertexTangent = float4(cross(float3(0, 0, 1), v.normalOS), 1.0);
        VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, vertexTangent);

        o.normal = half4(normalInput.normalWS, viewDirWS.x);
        o.tangent = half4(normalInput.tangentWS, viewDirWS.y);
        o.bitangent = half4(normalInput.bitangentWS, viewDirWS.z);
    #else
        o.normal = TransformObjectToWorldNormal(v.normalOS);
        OUTPUT_SH4(Attributes.positionWS, o.normal.xyz, GetWorldSpaceNormalizeViewDir(Attributes.positionWS), o.vertexSH, o.probeOcclusion);
    #endif

    half fogFactor = 0;
    #if !defined(_FOG_FRAGMENT)
        fogFactor = ComputeFogFactor(Attributes.positionCS.z);
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        o.fogFactorAndVertexLight.x = fogFactor;
        o.fogFactorAndVertexLight.yzw = VertexLighting(Attributes.positionWS, o.normal.xyz);
    #else
        o.fogFactor = fogFactor;
    #endif

    o.positionWS = Attributes.positionWS;
    o.clipPos = Attributes.positionCS;

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        o.shadowCoord = GetShadowCoord(Attributes);
    #endif

    return o;
}

void ComputeMasks(out half4 masks[4], half4 hasMask, Varyings IN)
{
    masks[0] = 0.5h;
    masks[1] = 0.5h;
    masks[2] = 0.5h;
    masks[3] = 0.5h;

#ifdef _MASKMAP
    masks[0] = lerp(masks[0], SAMPLE_TEXTURE2D(_Mask0, sampler_Mask0, IN.uvSplat01.xy), hasMask.x);
    masks[1] = lerp(masks[1], SAMPLE_TEXTURE2D(_Mask1, sampler_Mask0, IN.uvSplat01.zw), hasMask.y);
    masks[2] = lerp(masks[2], SAMPLE_TEXTURE2D(_Mask2, sampler_Mask0, IN.uvSplat23.xy), hasMask.z);
    masks[3] = lerp(masks[3], SAMPLE_TEXTURE2D(_Mask3, sampler_Mask0, IN.uvSplat23.zw), hasMask.w);
#endif

    masks[0] *= _MaskMapRemapScale0.rgba;
    masks[0] += _MaskMapRemapOffset0.rgba;
    masks[1] *= _MaskMapRemapScale1.rgba;
    masks[1] += _MaskMapRemapOffset1.rgba;
    masks[2] *= _MaskMapRemapScale2.rgba;
    masks[2] += _MaskMapRemapOffset2.rgba;
    masks[3] *= _MaskMapRemapScale3.rgba;
    masks[3] += _MaskMapRemapOffset3.rgba;
}

///////////////////////////////////////////////////////////////////////////////
//                  Surface B (revealed by the rest-frame noise)             //
///////////////////////////////////////////////////////////////////////////////
//
// A second, complete metallic-workflow surface. Where the noise mask -> 1 the terrain
// (Surface A) is replaced by this. UV is the terrain control UV scaled by _BaseMapB_ST.
// B's normal is only sampled when the terrain has a tangent frame (_NORMALMAP) or
// per-pixel normals, since otherwise the lighting ignores tangent-space normals anyway.

TEXTURE2D(_BaseMapB);       SAMPLER(sampler_BaseMapB);
TEXTURE2D(_BumpMapB);
TEXTURE2D(_EmissionMapB);

float4 _BaseMapB_ST;
half4  _BaseColorB;
half4  _EmissionColorB;
half   _BumpScaleB;
half   _MetallicB;
half   _SmoothnessB;
half   _OcclusionB;

struct SurfaceB
{
    half3 albedo;
    half3 normalTS;
    half  metallic;
    half  smoothness;
    half  occlusion;
    half3 emission;
};

SurfaceB SampleSurfaceB(float2 uvControl)
{
    float2 uv = uvControl * _BaseMapB_ST.xy + _BaseMapB_ST.zw;

    SurfaceB s;
    half4 baseB  = SAMPLE_TEXTURE2D(_BaseMapB, sampler_BaseMapB, uv) * _BaseColorB;
    s.albedo     = baseB.rgb;
    s.metallic   = _MetallicB;
    s.smoothness = _SmoothnessB;
    s.occlusion  = _OcclusionB;

    s.normalTS = half3(0.0h, 0.0h, 1.0h);
#if defined(_NORMALMAP) || defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
    s.normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMapB, sampler_BaseMapB, uv), _BumpScaleB);
#endif

    s.emission = half3(0.0h, 0.0h, 0.0h);
#if defined(_EMISSIONB)
    s.emission = SAMPLE_TEXTURE2D(_EmissionMapB, sampler_BaseMapB, uv).rgb * _EmissionColorB.rgb;
#endif
    return s;
}

// Forward (UniversalForward) fragment: build the terrain surface, then blend A -> B by
// the rest-frame noise mask. Only this pass is customized; GBuffer / deferred uses the
// stock terrain pass, so (like RestFrame) Surface B shows in forward rendering.
void SplatmapFragment(
    Varyings IN
    , out half4 outColor : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
    )
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);
#ifdef _ALPHATEST_ON
    ClipHoles(IN.uvMainAndLM.xy);
#endif

    // ---- Surface A: the painted terrain (stock splat assembly) ----
    half3 normalTS = half3(0.0h, 0.0h, 1.0h);
#ifdef TERRAIN_SPLAT_BASEPASS
    half3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uvMainAndLM.xy).rgb;
    half smoothness = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uvMainAndLM.xy).a;
    half metallic = SAMPLE_TEXTURE2D(_MetallicTex, sampler_MetallicTex, IN.uvMainAndLM.xy).r;
    half alpha = 1;
    half occlusion = 1;
#else

    half4 hasMask = half4(_LayerHasMask0, _LayerHasMask1, _LayerHasMask2, _LayerHasMask3);
    half4 masks[4];
    ComputeMasks(masks, hasMask, IN);

    float2 splatUV = (IN.uvMainAndLM.xy * (_Control_TexelSize.zw - 1.0f) + 0.5f) * _Control_TexelSize.xy;
    half4 splatControl = SAMPLE_TEXTURE2D(_Control, sampler_Control, splatUV);

    half alpha = dot(splatControl, 1.0h);
#ifdef _TERRAIN_BLEND_HEIGHT
    // disable Height Based blend when there are more than 4 layers (multi-pass breaks the normalization)
    if (_NumLayersCount <= 4)
        HeightBasedSplatModify(splatControl, masks);
#endif

    half weight;
    half4 mixedDiffuse;
    half4 defaultSmoothness;
    SplatmapMix(IN.uvMainAndLM, IN.uvSplat01, IN.uvSplat23, splatControl, weight, mixedDiffuse, defaultSmoothness, normalTS);
    half3 albedo = mixedDiffuse.rgb;

    half4 defaultMetallic = half4(_Metallic0, _Metallic1, _Metallic2, _Metallic3);
    half4 defaultOcclusion = half4(_MaskMapRemapScale0.g, _MaskMapRemapScale1.g, _MaskMapRemapScale2.g, _MaskMapRemapScale3.g) +
                            half4(_MaskMapRemapOffset0.g, _MaskMapRemapOffset1.g, _MaskMapRemapOffset2.g, _MaskMapRemapOffset3.g);

    half4 maskSmoothness = half4(masks[0].a, masks[1].a, masks[2].a, masks[3].a);
    defaultSmoothness = lerp(defaultSmoothness, maskSmoothness, hasMask);
    half smoothness = dot(splatControl, defaultSmoothness);

    half4 maskMetallic = half4(masks[0].r, masks[1].r, masks[2].r, masks[3].r);
    defaultMetallic = lerp(defaultMetallic, maskMetallic, hasMask);
    half metallic = dot(splatControl, defaultMetallic);

    half4 maskOcclusion = half4(masks[0].g, masks[1].g, masks[2].g, masks[3].g);
    defaultOcclusion = lerp(defaultOcclusion, maskOcclusion, hasMask);
    half occlusion = dot(splatControl, defaultOcclusion);
#endif

    // ---- Surface B + rest-frame noise blend (A -> B where the mask -> 1) ----
    SurfaceB sb = SampleSurfaceB(IN.uvMainAndLM.xy);
    half mask  = SampleNoiseField(IN.positionWS);

    // Baked-lightmap mask: drive the mask toward 0 (Surface A) where the lightmap is
    // bright. A geometric world normal is available pre-InitializeInputData in every
    // normal variant (IN.normal is the WS vertex normal except in the tangent-frame case).
#if defined(_LIGHTMAPMASK) && defined(LIGHTMAP_ON)
    #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
        half3 geomNormalWS = IN.normal.xyz;
    #else
        half3 geomNormalWS = IN.normal;
    #endif
    mask = RestFrameApplyLightmapMask(mask, Luminance(SampleLightmap(IN.uvMainAndLM.zw, geomNormalWS)));
#endif

    albedo     = lerp(albedo, sb.albedo, mask);
    metallic   = lerp(metallic, sb.metallic, mask);
    smoothness = lerp(smoothness, sb.smoothness, mask);
    occlusion  = lerp(occlusion, sb.occlusion, mask);
    normalTS   = normalize(lerp(normalTS, sb.normalTS, mask));
    half3 emission = sb.emission * mask;

    InputData inputData;
    InitializeInputData(IN, normalTS, inputData);
    SetupTerrainDebugTextureData(inputData, IN.uvMainAndLM.xy);

#if defined(_DBUFFER)
    half3 specular = half3(0.0h, 0.0h, 0.0h);
    ApplyDecal(IN.clipPos,
        albedo,
        specular,
        inputData.normalWS,
        metallic,
        occlusion,
        smoothness);
#endif

    InitializeBakedGIData(IN, inputData);

    half4 color = UniversalFragmentPBR(inputData, albedo, metallic, /* specular */ half3(0.0h, 0.0h, 0.0h), smoothness, occlusion, emission, alpha);

    SplatmapFinalColor(color, inputData.fogCoord);

    outColor = half4(color.rgb, 1.0h);

#ifdef _WRITE_RENDERING_LAYERS
    uint renderingLayers = GetMeshRenderingLayer();
    outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
#endif
}

#endif
