#ifndef REST_FRAME_NOISE_FIELD_INCLUDED
#define REST_FRAME_NOISE_FIELD_INCLUDED

// Rest-frame-anchored, layered, domain-warped 4D noise field - the shared core of the
// "VR/RestFrame" effect, factored out so more than one shader can sample the identical
// field. SampleNoiseField(positionWS) returns the [0,1] A<->B blend mask. Everything
// here is surface-agnostic (it never touches material / SurfaceData), so the SimpleLit
// RestFrame pass and the terrain TerrainRestFrame pass produce a pixel-identical field.
//
// Requires URP Common / Lighting (for _Time, TWO_PI, Luminance, ...) to be included
// first; both including passes do that before this file.
//
// Included by RestFrameForwardPass.hlsl (VR/RestFrame) and TerrainRestFrameForwardPass
// .hlsl (VR/TerrainRestFrame) - the single source of the field for both.

// 4D noise primitives for the animated/morphing field. The _NOISETYPE_* keyword selects
// which one the synthesizer samples (see NoisePrimitive): Simplex and Perlin are lattice
// primitives in their own files; Sine is computed inline (SineField) and needs no lattice
// file. These live in the project because the bundled jp.keijiro.noiseshader ships only
// 2D/3D noise.
#if defined(_NOISETYPE_SIMPLEX)
    #include "SimplexNoise4D.hlsl"   // float SimplexNoise(float4 p) -> ~[-1, 1]
#elif defined(_NOISETYPE_SINE)
    // Sine needs no lattice primitive, but AnimNoise1D below still uses the wglnoise
    // permutation helpers - pull them in directly (Classic/Simplex include this too).
    #include "Packages/jp.keijiro.noiseshader/Shader/Common.hlsl"
#else // _NOISETYPE_PERLIN (default / fallback)
    #include "ClassicNoise4D.hlsl"   // float ClassicNoise(float4 p) -> ~[-1, 1]
#endif

// Highest octave count the loop is compiled for. _Octaves clamps the active
// count at runtime; this constant only bounds the unrolled loop.
#define NOISE_MAX_OCTAVES 8

float  _BaseFrequency;   // world-space scale: smaller = larger, smoother features
float  _BaseAmplitude;   // overall output gain before the [0,1] remap
float  _Octaves;         // active octave count (1 .. NOISE_MAX_OCTAVES)
float  _Lacunarity;      // frequency multiplier per octave (~2.0)
float  _Gain;            // amplitude multiplier per octave / persistence (~0.5)

float  _WarpStrength;    // how far warped noise pushes the final sample position
float  _WarpFeedback;    // how strongly an inner noise warps the warp field itself

float4 _AnimationSpeed;   // per-axis LINEAR drift speed (xyz flow, w morph) = "Linear Speed"

// Per-axis oscillation, added on top of the linear drift (see SampleNoiseField).
// _OscType* selects the shape: 0 = 1D-Perlin wander (organic), 1 = Sine (regular);
// fractional values blend the two. _OscSpeed is the per-axis rate and _OscMagnitude
// the per-axis amplitude - both independent of the linear speed and of each other.
float4 _OscSpeed;         // per-axis oscillation rate (Perlin: steps/s, Sine: cycles/s)
float4 _OscMagnitude;     // per-axis oscillation amplitude (noise-domain units)
float  _OscTypeX;         // 0 = Perlin wander, 1 = Sine
float  _OscTypeY;
float  _OscTypeZ;
float  _OscTypeW;

// Per-axis constant override of the FINAL noise input coordinate (applied after
// anchoring, radius selection and animation): 1 = feed _CoordConstValues for that
// axis instead, removing all variation along it. Values are in noise-domain units.
float  _CoordConstX;
float  _CoordConstY;
float  _CoordConstZ;
float  _CoordConstW;
float4 _CoordConstValues;

// World -> rest-frame matrix (rigid: rotation + translation, no scale). Set as a shader
// GLOBAL each frame by RestFrameShaderFeed.cs on the anchor object, so the whole field
// rigidly follows that object; identity = plain world space. One shared value for both
// XR eyes (per-eye built-ins would make each eye sample a slightly different field).
float4x4 _RestFrameAnchor;

// Rest-frame radius (_RESTFRAMERADIUS): inside this distance from the anchor the field
// is anchored as usual; outside it is world-anchored, with its own bias and frequency.
float  _RestFrameRadius;        // anchored sphere radius around the anchor (m)
float  _OutsideNoiseBias;       // blend bias for the world-anchored outside
float  _OutsideFrequencyScale;  // frequency (LOD) multiplier for the outside
float  _OutsideAnimFreezeX;     // per axis: 1 = no animation outside the radius
float  _OutsideAnimFreezeY;
float  _OutsideAnimFreezeZ;
float  _OutsideAnimFreezeW;

float  _NoiseBias;       // added to the blend mask after the [-1,1] -> [0,1] remap
float  _Contrast;        // power curve shaping the A<->B transition
float  _Saturation;      // 0 = smooth gradient, 1 = hard binary 0/1 cut

float  _LightmapMaskLow;    // baked-light luminance where masking begins
float  _LightmapMaskHigh;   // baked-light luminance that fully forces Surface A
float  _LightmapMaskInvert; // 0: hide noise in lit areas, 1: noise only in lit areas

// Separable 4D sine field: one sine per axis, summed and normalized to exactly [-1, 1].
// On its own a regular lattice of bumps; the fBm octaves and domain warp layer it into a
// marbled/woven field, exactly as for the Perlin/Simplex primitives.
float SineField(float4 p)
{
    return (sin(p.x) + sin(p.y) + sin(p.z) + sin(p.w)) * 0.25;
}

// Selected noise primitive, keyword-switched. All map a 4D point to ~[-1, 1].
float NoisePrimitive(float4 p)
{
#if defined(_NOISETYPE_SIMPLEX)
    return SimplexNoise(p);
#elif defined(_NOISETYPE_SINE)
    return SineField(p);
#else // _NOISETYPE_PERLIN (default / fallback)
    return ClassicNoise(p);
#endif
}

// Fractal Brownian Motion: sum of noise octaves, normalized to ~[-1, 1] so the
// output range stays stable no matter how many octaves are active.
float Fbm(float4 p)
{
    float sum  = 0.0;
    float amp  = 1.0;
    float freq = 1.0;
    float norm = 0.0;

    [unroll]
    for (int i = 0; i < NOISE_MAX_OCTAVES; i++)
    {
        if (i >= _Octaves)
            break;

        sum  += amp * NoisePrimitive(p * freq);
        norm += amp;
        freq *= _Lacunarity;
        amp  *= _Gain;
    }

    return sum / max(norm, 1e-5);
}

// Three decorrelated fBm samples packed into a vector, used as a displacement
// field for domain warping (applied to xyz only - see SynthesizeNoise).
float3 FbmVec(float4 p)
{
    return float3(
        Fbm(p),
        Fbm(p + float4(5.2, 1.3, 2.7, 1.4)),
        Fbm(p + float4(2.8, 7.4, 1.9, 3.1)));
}

// Combine the octaves, optionally feeding noise back into the sample position.
//   _DOMAINWARP off : plain fBm.
//   _DOMAINWARP on  : two-level feedback domain warp.
float SynthesizeNoise(float4 p)
{
#if defined(_DOMAINWARP)
    // Warp only the spatial axes (xyz); leave w (time / morph) a clean linear axis.
    float3 q = FbmVec(p);
    float3 r = FbmVec(p + float4(_WarpFeedback * q, 0.0));
    return Fbm(p + float4(_WarpStrength * r, 0.0));
#else
    return Fbm(p);
#endif
}

// Four decorrelated channels of 1D gradient ("Perlin") noise, one per coordinate,
// each evaluated at its own phase t (so every axis can wander at its own rate). Built
// on the same wglnoise mod-289 permutation as the 4D primitives (float-only math, safe
// for SM 2.0). Returns ~[-1, 1] per channel, zero at every integer lattice point.
float4 AnimNoise1D(float4 t)
{
    float4 i = floor(t);
    float4 f = t - i;
    // Per-channel seed offsets decorrelate the four axes on the permutation ring.
    float4 seeds = float4(0.0, 91.0, 173.0, 251.0);
    float4 h0 = wglnoise_permute(wglnoise_mod289(i + seeds));
    float4 h1 = wglnoise_permute(wglnoise_mod289(i + 1.0 + seeds));
    float4 g0 = h0 * (1.0 / 144.5) - 1.0;  // lattice gradients, uniform in [-1, 1)
    float4 g1 = h1 * (1.0 / 144.5) - 1.0;
    float4 u  = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);  // quintic fade
    return 2.0 * lerp(g0 * f, g1 * (f - 1.0), u);
}

// Per-axis animation offset, shared by every sampling entry point: a steady linear drift plus
// an additive oscillation. The oscillation has its own per-axis rate (_OscSpeed), amplitude
// (_OscMagnitude) and shape (_OscType*: 1D-Perlin wander or Sine). Time-only, so it is uniform
// across the frame and identical for both XR eyes.
float4 RestFrameAnimOffset()
{
    float4 oscPhase   = _Time.y * _OscSpeed;
    float4 oscType    = saturate(float4(_OscTypeX, _OscTypeY, _OscTypeZ, _OscTypeW));
    float4 oscPerlin  = AnimNoise1D(oscPhase);        // ~[-1, 1], organic wander
    float4 oscSine    = sin(oscPhase * TWO_PI);       // [-1, 1], regular (cycles / sec)
    float4 osc        = lerp(oscPerlin, oscSine, oscType);
    return _AnimationSpeed * _Time.y + _OscMagnitude * osc;
}

// Shared tail of the field: take an assembled 4D sample point plus the blend bias, apply the
// per-axis constant override, synthesize the (warped) fBm and map it into the stable [0, 1]
// A <-> B mask (amplitude, [-1,1] -> [0,1] remap + bias, contrast, then saturation). Factored
// out so the position- and direction-anchored entry points share one identical shaping pipeline.
float RestFrameShapeMask(float4 p, float bias)
{
    // Per-axis constant override: pin the synthesizer's input coordinate to a fixed value.
    float4 coordConst = saturate(float4(_CoordConstX, _CoordConstY, _CoordConstZ, _CoordConstW));
    p = lerp(p, _CoordConstValues, coordConst);

    float n = SynthesizeNoise(p) * _BaseAmplitude;  // ~[-1, 1]
    n = n * 0.5 + 0.5 + bias;                       // -> ~[0, 1]
    n = saturate(n);
    n = pow(n, _Contrast);

    // Saturation: steepen the mask around its midpoint (1 = hard binary A/B cut).
    float k = 1.0 / max(1.0 - _Saturation, 1e-4);
    n = saturate((n - 0.5) * k + 0.5);
    return n;
}

// Full pipeline: world position -> anchored domain (world-anchored outside the radius,
// when enabled) -> animated domain -> synthesized noise mapped into a stable [0, 1]
// range, used as the A <-> B blend mask.
float SampleNoiseField(float3 positionWS)
{
    // Rigid anchoring: re-express the sample position in _RestFrameAnchor space.
    float3 positionRF = mul(_RestFrameAnchor, float4(positionWS, 1.0)).xyz;

    float3 spatial = positionRF * _BaseFrequency;
    float  bias    = _NoiseBias;

    float4 animOffset = RestFrameAnimOffset();

#if defined(_RESTFRAMERADIUS)
    // Outside a sphere around the anchor the field is world-anchored, with its own bias
    // and frequency (LOD). Hard cutoff: tOut is exactly 0 or 1, so every pixel samples
    // one pure field and the synthesizer still runs exactly once.
    float tOut = step(_RestFrameRadius, length(positionRF));
    spatial = lerp(spatial, positionWS * (_BaseFrequency * _OutsideFrequencyScale), tOut);
    bias    = lerp(bias, _OutsideNoiseBias, tOut);
    // Per-axis animation freeze for the outside region.
    float4 animFreeze = saturate(float4(_OutsideAnimFreezeX, _OutsideAnimFreezeY, _OutsideAnimFreezeZ, _OutsideAnimFreezeW));
    animOffset *= 1.0 - animFreeze * tOut;
#endif

    // xyz = spatial domain (+ optional directional flow); w = time only, so the pattern
    // morphs in place rather than just sliding a rigid field past the surface.
    float4 p;
    p.xyz = spatial + animOffset.xyz;
    p.w   = animOffset.w;

    return RestFrameShapeMask(p, bias);
}

// Direction-anchored entry point for the skybox (Skybox/RestFrame). The sky is the infinitely-
// far rest-frame surface, so only the anchor's ORIENTATION is meaningful: transforming the view
// ray with w = 0 drops the anchor's translation and keeps its rotation. There is deliberately no
// radius (every pixel is "at infinity", i.e. always outside) and no lightmap mask. dirWS need not
// be normalized by the caller, but should be for a stable angular frequency; _BaseFrequency then
// sets the angular feature size (the ray is sampled as a point on a sphere of that radius). Note
// a view ray is order-1 (vs metre-scale world positions), so this wants a higher _BaseFrequency
// than the position-anchored shaders to show comparable detail.
float SampleNoiseFieldDirection(float3 dirWS)
{
    // Orientation-only anchoring: rotate the ray into _RestFrameAnchor space (w = 0 = no translation).
    float3 dirRF = mul(_RestFrameAnchor, float4(dirWS, 0.0)).xyz;

    float4 animOffset = RestFrameAnimOffset();

    // xyz = direction on the celestial sphere (+ optional flow); w = time-only morph.
    float4 p;
    p.xyz = dirRF * _BaseFrequency + animOffset.xyz;
    p.w   = animOffset.w;

    return RestFrameShapeMask(p, _NoiseBias);
}

// Reduce the B-mask where the baked lightmap is bright (forces Surface A in lit areas).
// litLuminance is the baked lightmap luminance at this pixel (0 where unlit / dynamic).
half RestFrameApplyLightmapMask(half mask, half litLuminance)
{
    half litFactor = smoothstep(_LightmapMaskLow, _LightmapMaskHigh, litLuminance);
    litFactor = lerp(litFactor, 1.0h - litFactor, _LightmapMaskInvert);
    return mask * (1.0h - litFactor);
}

#endif
