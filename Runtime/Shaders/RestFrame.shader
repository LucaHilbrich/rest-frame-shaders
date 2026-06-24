// Rest-frame-anchored Perlin noise synthesizer. Structurally a URP SimpleLit shader
// (same passes as URP's SimpleLit) whose ForwardLit pass blends between two
// complete surfaces (A and B) using a layered, domain-warped Perlin noise field.
// The field is evaluated in the space of the global _RestFrameAnchor matrix, fed
// each frame by RestFrameShaderFeed.cs, so it rigidly follows the anchor object;
// with an identity anchor (no feed active) it is plain world space. An optional
// radius (_RESTFRAMERADIUS) hard-limits the anchoring to a sphere around the
// anchor: outside it the field is world-anchored, with its own bias and
// frequency. See RestFrameForwardPass.hlsl.
Shader "VR/RestFrame"
{
    Properties
    {
        // Surface A reuses the standard SimpleLit inputs - these are also what the
        // shadow / depth / gbuffer / meta passes render with. [MainTexture]/[MainColor]
        // stay on these so Unity's material system still finds the main map/color.
        [MainTexture] _BaseMap("Base Map (RGB) Smoothness / Alpha (A)", 2D) = "white" {}
        [MainColor]   _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _SpecColor("Specular Color (A = Smoothness)", Color) = (0.5, 0.5, 0.5, 0.5)
        [NoScaleOffset] _SpecGlossMap("Specular Map", 2D) = "white" {}
        [NoScaleOffset] _BumpMap("Normal Map", 2D) = "bump" {}
        [HDR] _EmissionColor("Emission Color", Color) = (0,0,0)
        [NoScaleOffset]_EmissionMap("Emission Map", 2D) = "white" {}

        // Surface B is a second, complete surface; the noise mask blends A -> B.
        // Maps/colors are independent of A, but the feature toggles below are shared.
        _BaseMapB("Base Map (RGB) Smoothness / Alpha (A)", 2D) = "white" {}
        _BaseColorB("Base Color", Color) = (1, 1, 1, 1)
        _SpecColorB("Specular Color (A = Smoothness)", Color) = (0.5, 0.5, 0.5, 0.5)
        [NoScaleOffset] _SpecGlossMapB("Specular Map", 2D) = "white" {}
        [NoScaleOffset] _BumpMapB("Normal Map", 2D) = "bump" {}
        [HDR] _EmissionColorB("Emission Color", Color) = (0,0,0)
        [NoScaleOffset]_EmissionMapB("Emission Map", 2D) = "white" {}

        [KeywordEnum(Sine, Perlin, Simplex)] _NoiseType("Noise Type", Float) = 1
        _BaseFrequency("Base Frequency (world scale)", Float) = 0.1
        _BaseAmplitude("Base Amplitude", Float) = 1.0
        _Octaves("Octaves", Range(1, 8)) = 4
        _Lacunarity("Lacunarity (frequency x per octave)", Range(1.0, 4.0)) = 2.0
        _Gain("Gain / Persistence (amplitude x per octave)", Range(0.0, 1.0)) = 0.5
        [Toggle(_DOMAINWARP)] _DomainWarpEnabled("Enable Warp", Float) = 1.0
        _WarpStrength("Warp Strength", Range(0.0, 4.0)) = 1.0
        _WarpFeedback("Warp Feedback (warp the warp)", Range(0.0, 4.0)) = 1.0

        // Per coordinate (xyz = flow along the rest-frame anchor's axes; w = 4D morph,
        // which evolves the pattern in place / "boiling" instead of sliding it past).
        // Total per-axis offset is additive - a steady drift plus an oscillation:
        //   offset = Linear Speed * time + Oscillatory Magnitude * osc(Oscillatory Speed * time)
        // where osc(.) is per-axis 1D Perlin (organic wander) or Sine (regular), set below.
        _AnimationSpeed("Linear Speed (xyz = flow, w = morph)", Vector) = (0, 0, 0, 0.1)
        // Oscillation shape per axis: off = 1D Perlin (organic wander), on = Sine (regular).
        [ToggleUI] _OscTypeX("X - Oscillation Sine (off = Perlin)", Float) = 0.0
        [ToggleUI] _OscTypeY("Y - Oscillation Sine (off = Perlin)", Float) = 0.0
        [ToggleUI] _OscTypeZ("Z - Oscillation Sine (off = Perlin)", Float) = 0.0
        [ToggleUI] _OscTypeW("W (morph) - Oscillation Sine (off = Perlin)", Float) = 0.0
        // Oscillation rate per axis (Perlin: lattice steps / sec; Sine: cycles / sec).
        _OscSpeed("Oscillatory Speed (Perlin: steps/s, Sine: cycles/s)", Vector) = (1, 1, 1, 1)
        // Oscillation amplitude per axis, in noise-domain units (peak +/- offset added).
        _OscMagnitude("Oscillatory Magnitude (x, y, z, w)", Vector) = (0, 0, 0, 0)

        // Per axis: feed the synthesizer a constant instead of the actual coordinate,
        // removing all variation along that axis (a pinned spatial axis extrudes the
        // pattern; a pinned w freezes the morph at that phase). Values are in noise-
        // domain units - they replace (position x frequency + animation) on that axis.
        [ToggleUI] _CoordConstX("X - Use Constant", Float) = 0.0
        [ToggleUI] _CoordConstY("Y - Use Constant", Float) = 0.0
        [ToggleUI] _CoordConstZ("Z - Use Constant", Float) = 0.0
        [ToggleUI] _CoordConstW("W - Use Constant", Float) = 0.0
        _CoordConstValues("Constant Values (x, y, z, w)", Vector) = (0, 0, 0, 0)

        _NoiseBias("Blend Bias (toward A or B)", Range(-1.0, 1.0)) = 0.0
        _Contrast("Blend Contrast", Range(0.1, 8.0)) = 1.0
        _Saturation("Saturation (0 = smooth, 1 = binary 0 or 1)", Range(0.0, 1.0)) = 0.0

        // Inside the radius the field is anchored to _RestFrameAnchor as usual; outside
        // it is anchored to world space (does not move with the anchor), with its own
        // blend bias and frequency. Hard cutoff at the radius, no transition area;
        // one noise lookup total.
        [Toggle(_RESTFRAMERADIUS)] _RestFrameRadiusEnabled("Enable Radius (world-anchored outside)", Float) = 0.0
        _RestFrameRadius("Radius (m, hard cutoff)", Float) = 5.0
        _OutsideNoiseBias("Outside - Blend Bias", Range(-1.0, 1.0)) = 0.0
        _OutsideFrequencyScale("Outside - Frequency Scale (LOD)", Range(0.1, 8.0)) = 1.0
        // Per axis: freeze the animation in the world-anchored outside region - out
        // there the field holds its resting (t = 0) state on that axis while the
        // inside keeps animating. Linear or Perlin per the Animation toggles above.
        [ToggleUI] _OutsideAnimFreezeX("Outside - Freeze X Animation", Float) = 0.0
        [ToggleUI] _OutsideAnimFreezeY("Outside - Freeze Y Animation", Float) = 0.0
        [ToggleUI] _OutsideAnimFreezeZ("Outside - Freeze Z Animation", Float) = 0.0
        [ToggleUI] _OutsideAnimFreezeW("Outside - Freeze W (morph) Animation", Float) = 0.0

        // Forces the noise toward Surface A where the baked lightmap is bright.
        // Only affects lightmapped (static, baked) objects; dynamic objects are unaffected.
        [Toggle(_LIGHTMAPMASK)] _LightmapMaskEnabled("Use Baked Lightmap as Mask", Float) = 0.0
        _LightmapMaskLow("Lit Threshold - Start (noise fades out)", Range(0.0, 4.0)) = 0.1
        _LightmapMaskHigh("Lit Threshold - Full (pure Surface A)", Range(0.0, 4.0)) = 0.5
        [ToggleUI] _LightmapMaskInvert("Invert (noise only in lit areas)", Float) = 0.0

        // These feature toggles apply to BOTH surfaces (the keywords are shared).
        // Smoothness for each surface is the ALPHA of its Specular Color.
        [Toggle(_NORMALMAP)] _NormalMapEnabled("Use Normal Maps", Float) = 0.0
        [Toggle(_SPECULAR_COLOR)] _SpecularColorEnabled("Use Specular Highlights", Float) = 0.0
        [Toggle(_EMISSION)] _EmissionEnabled("Use Emission", Float) = 0.0
        _Cutoff("Alpha Clipping Threshold", Range(0.0, 1.0)) = 0.5
        [HideInInspector] _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        [HideInInspector] _SmoothnessSource("Smoothness Source", Float) = 0.0
        [HideInInspector] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [HideInInspector] _BumpScale("Scale", Float) = 1.0

        // Blending state
        _Surface("__surface", Float) = 0.0
        _Blend("__blend", Float) = 0.0
        _Cull("__cull", Float) = 2.0
        [ToggleUI] _AlphaClip("__clip", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _SrcBlendAlpha("__srcA", Float) = 1.0
        [HideInInspector] _DstBlendAlpha("__dstA", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _BlendModePreserveSpecular("_BlendModePreserveSpecular", Float) = 1.0
        [HideInInspector] _AlphaToMask("__alphaToMask", Float) = 0.0
        [HideInInspector] _AddPrecomputedVelocity("_AddPrecomputedVelocity", Float) = 0.0

        [ToggleUI] _ReceiveShadows("Receive Shadows", Float) = 1.0
        // Editmode props
        _QueueOffset("Queue offset", Float) = 0.0

        // ObsoleteProperties
        [HideInInspector] _MainTex("BaseMap", 2D) = "white" {}
        [HideInInspector] _Color("Base Color", Color) = (1, 1, 1, 1)
        [HideInInspector] _Shininess("Smoothness", Float) = 0.0
        [HideInInspector] _GlossinessSource("GlossinessSource", Float) = 0.0
        [HideInInspector] _SpecSource("SpecularHighlights", Float) = 0.0

        [HideInInspector][NoScaleOffset]unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset]unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset]unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "SimpleLit"
            "IgnoreProjector" = "True"
        }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            // -------------------------------------
            // Render State Commands
            // Use same blending / depth states as Standard shader
            Blend[_SrcBlend][_DstBlend], [_SrcBlendAlpha][_DstBlendAlpha]
            ZWrite[_ZWrite]
            Cull[_Cull]
            AlphaToMask[_AlphaToMask]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex LitPassVertexSimple
            #pragma fragment LitPassFragmentSimple

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            #pragma shader_feature_local_fragment _SURFACE_TYPE_TRANSPARENT
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ _ALPHAPREMULTIPLY_ON _ALPHAMODULATE_ON
            #pragma shader_feature_local_fragment _ _SPECGLOSSMAP _SPECULAR_COLOR
            #pragma shader_feature_local_fragment _GLOSSINESS_FROM_BASE_ALPHA

            // Noise synthesizer: enables the domain-warp feedback stage
            #pragma shader_feature_local_fragment _DOMAINWARP
            // Baked-lightmap brightness masking (forces Surface A in lit areas)
            #pragma shader_feature_local_fragment _LIGHTMAPMASK
            // Noise primitive: Sine field / Classic Perlin 4D / Simplex 4D (see RestFrameNoiseField.hlsl)
            #pragma shader_feature_local_fragment _ _NOISETYPE_SINE _NOISETYPE_PERLIN _NOISETYPE_SIMPLEX
            // Hard radius around the rest-frame anchor; outside it the field is world-anchored
            #pragma shader_feature_local_fragment _RESTFRAMERADIUS

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #include_with_pragmas "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRenderingKeywords.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ProbeVolumeVariants.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile _ USE_LEGACY_LIGHTMAPS
            #pragma multi_compile_fog
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            //--------------------------------------
            // Defines
            #define BUMP_SCALE_NOT_SUPPORTED 1

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include "RestFrameForwardPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _GLOSSINESS_FROM_BASE_ALPHA

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // This is used during shadow map generation to differentiate between directional and punctual light shadows, as they use different formulas to apply Normal Bias
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "GBuffer"
            Tags
            {
                "LightMode" = "UniversalGBuffer"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite[_ZWrite]
            ZTest LEqual
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 4.5

            // Deferred Rendering Path does not support the OpenGL-based graphics API:
            // Desktop OpenGL, OpenGL ES 3.0, WebGL 2.0.
            #pragma exclude_renderers gles3 glcore

            // -------------------------------------
            // Shader Stages
            #pragma vertex LitPassVertexSimple
            #pragma fragment LitPassFragmentSimple

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            //#pragma shader_feature _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local_fragment _ _SPECGLOSSMAP _SPECULAR_COLOR
            #pragma shader_feature_local_fragment _GLOSSINESS_FROM_BASE_ALPHA
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            //#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            //#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ProbeVolumeVariants.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile _ USE_LEGACY_LIGHTMAPS
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile_fragment _ _RENDER_PASS_ENABLED
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            //--------------------------------------
            // Defines
            #define BUMP_SCALE_NOT_SUPPORTED 1

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitGBufferPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            ColorMask R
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _GLOSSINESS_FROM_BASE_ALPHA

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // This pass is used when drawing to a _CameraNormalsTexture texture
        Pass
        {
            Name "DepthNormals"
            Tags
            {
                "LightMode" = "DepthNormals"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _GLOSSINESS_FROM_BASE_ALPHA

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            // Universal Pipeline keywords
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitDepthNormalsPass.hlsl"
            ENDHLSL
        }

        // This pass it not used during regular rendering, only for lightmap baking.
        Pass
        {
            Name "Meta"
            Tags
            {
                "LightMode" = "Meta"
            }

            // -------------------------------------
            // Render State Commands
            Cull Off

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex UniversalVertexMeta
            #pragma fragment UniversalFragmentMetaSimple

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _SPECGLOSSMAP
            #pragma shader_feature EDITOR_VISUALIZATION

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitMetaPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "Universal2D"
            Tags
            {
                "LightMode" = "Universal2D"
                "RenderType" = "Transparent"
                "Queue" = "Transparent"
            }

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex vert
            #pragma fragment frag

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/Utils/Universal2D.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "MotionVectors"
            Tags { "LightMode" = "MotionVectors" }
            ColorMask RG

            HLSLPROGRAM
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma shader_feature_local_vertex _ADD_PRECOMPUTED_VELOCITY

            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ObjectMotionVectors.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "XRMotionVectors"
            Tags { "LightMode" = "XRMotionVectors" }
            ColorMask RGBA

            // Stencil write for obj motion pixels
            Stencil
            {
                WriteMask 1
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma shader_feature_local_vertex _ADD_PRECOMPUTED_VELOCITY
            #define APLICATION_SPACE_WARP_MOTION 1
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ObjectMotionVectors.hlsl"
            ENDHLSL
        }
    }

    // Clean, sectioned material inspector with per-coordinate X/Y/Z/W rows.
    // See Editor/RestFrameShaderGUI.cs
    CustomEditor "RestFrameShaderGUI"

    Fallback  "Hidden/Universal Render Pipeline/FallbackError"
}
