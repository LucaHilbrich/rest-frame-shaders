// Skybox analogue of "VR/RestFrame". An unlit URP skybox that cross-fades between two cubemap
// skies (Surface A and Surface B) using the global rest-frame anchored 4D noise field
// (RestFrameNoiseField.hlsl, the same field RestFrame and TerrainRestFrame use). Because a
// skybox has no surface position, the field is sampled along the per-pixel view ray via
// SampleNoiseFieldDirection() - the anchor's ORIENTATION rotates the reveal pattern, its
// translation is ignored (the sky is at infinity). Single unlit pass: no shadow / depth /
// gbuffer / meta passes, no lighting, no radius and no lightmap mask. Assign the material in
// Lighting > Environment > Skybox Material; put a RestFrameShaderFeed on the anchor object to
// drive _RestFrameAnchor (the same global the other two shaders read). See
// SkyboxRestFrameForwardPass.hlsl.
Shader "Skybox/RestFrame"
{
    Properties
    {
        // ---- Surface A / B: two complete cubemap skies the noise cross-fades between ----
        [NoScaleOffset] _CubemapA("Cubemap A", Cube) = "grey" {}
        [HDR] _TintA("Tint A", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _CubemapB("Cubemap B", Cube) = "grey" {}
        [HDR] _TintB("Tint B", Color) = (1, 1, 1, 1)
        _Exposure("Exposure", Float) = 1.0

        // ---- Noise Blend (same field as VR/RestFrame; sampled along the view ray) ----
        // _BaseFrequency is ANGULAR here (the ray is unit length), so it wants a higher value
        // than the metre-scale world shaders to show comparable detail.
        [KeywordEnum(Sine, Perlin, Simplex)] _NoiseType("Noise Type", Float) = 1
        _BaseFrequency("Base Frequency (angular scale)", Float) = 1.0
        _BaseAmplitude("Base Amplitude", Float) = 1.0
        _Octaves("Octaves", Range(1, 8)) = 4
        _Lacunarity("Lacunarity (frequency x per octave)", Range(1.0, 4.0)) = 2.0
        _Gain("Gain / Persistence (amplitude x per octave)", Range(0.0, 1.0)) = 0.5
        [Toggle(_DOMAINWARP)] _DomainWarpEnabled("Enable Warp", Float) = 1.0
        _WarpStrength("Warp Strength", Range(0.0, 4.0)) = 1.0
        _WarpFeedback("Warp Feedback (warp the warp)", Range(0.0, 4.0)) = 1.0

        // ---- Animation (xyz = flow across the sky, w = 4D morph / "boiling") ----
        _AnimationSpeed("Linear Speed (xyz = flow, w = morph)", Vector) = (0, 0, 0, 0.1)
        [ToggleUI] _OscTypeX("X - Oscillation Sine (off = Perlin)", Float) = 0.0
        [ToggleUI] _OscTypeY("Y - Oscillation Sine (off = Perlin)", Float) = 0.0
        [ToggleUI] _OscTypeZ("Z - Oscillation Sine (off = Perlin)", Float) = 0.0
        [ToggleUI] _OscTypeW("W (morph) - Oscillation Sine (off = Perlin)", Float) = 0.0
        _OscSpeed("Oscillatory Speed (Perlin: steps/s, Sine: cycles/s)", Vector) = (1, 1, 1, 1)
        _OscMagnitude("Oscillatory Magnitude (x, y, z, w)", Vector) = (0, 0, 0, 0)

        // ---- Coordinate Override ----
        [ToggleUI] _CoordConstX("X - Use Constant", Float) = 0.0
        [ToggleUI] _CoordConstY("Y - Use Constant", Float) = 0.0
        [ToggleUI] _CoordConstZ("Z - Use Constant", Float) = 0.0
        [ToggleUI] _CoordConstW("W - Use Constant", Float) = 0.0
        _CoordConstValues("Constant Values (x, y, z, w)", Vector) = (0, 0, 0, 0)

        // ---- Blend Shaping ----
        _NoiseBias("Blend Bias (toward A or B)", Range(-1.0, 1.0)) = 0.0
        _Contrast("Blend Contrast", Range(0.1, 8.0)) = 1.0
        _Saturation("Saturation (0 = smooth, 1 = binary 0 or 1)", Range(0.0, 1.0)) = 0.0
    }

    SubShader
    {
        // Background queue / skybox tags: drawn by URP's skybox pass after opaques. No LightMode
        // tag - like the built-in Skybox/* shaders, the dedicated skybox draw renders this pass
        // directly (it is not selected through the normal SRP LightMode loop).
        Tags
        {
            "Queue" = "Background"
            "RenderType" = "Background"
            "PreviewType" = "Skybox"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "SkyboxRestFrame"

            // Render State Commands: a skybox writes no depth and is not back-face culled.
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex SkyboxRestFrameVertex
            #pragma fragment SkyboxRestFrameFragment

            // -------------------------------------
            // Material Keywords
            // Noise primitive: Sine field / Classic Perlin 4D / Simplex 4D (RestFrameNoiseField.hlsl)
            #pragma shader_feature_local_fragment _ _NOISETYPE_SINE _NOISETYPE_PERLIN _NOISETYPE_SIMPLEX
            // Noise synthesizer: enables the domain-warp feedback stage
            #pragma shader_feature_local_fragment _DOMAINWARP

            //--------------------------------------
            // GPU Instancing / XR stereo
            #pragma multi_compile_instancing

            // -------------------------------------
            // Includes
            #include "SkyboxRestFrameForwardPass.hlsl"
            ENDHLSL
        }
    }

    // Clean, sectioned material inspector (Surface A / B cubemaps + the shared noise sections),
    // mirroring RestFrameShaderGUI. See Editor/SkyboxRestFrameShaderGUI.cs
    CustomEditor "SkyboxRestFrameShaderGUI"
}
