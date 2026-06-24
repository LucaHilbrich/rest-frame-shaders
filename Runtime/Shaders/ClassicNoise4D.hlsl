//
// 4D port for the rest frame noise synthesizer. Mirrors the package's
// ClassicNoise3D.hlsl (same ClassicNoise_impl / ClassicNoise / PeriodicNoise layout)
// so ClassicNoise() is simply overloaded by dimension - Fbm() can call ClassicNoise(p)
// with either a float3 or a float4. This lives in the project rather than the package
// cache (Library/PackageCache, which Unity regenerates) because the bundled
// jp.keijiro.noiseshader ships only 2D/3D noise.
//
// Cost note: 4D Perlin evaluates a 2^4 = 16-corner lattice (vs 8 for 3D), so each
// sample is roughly twice the work of ClassicNoise(float3). See SimplexNoise4D.hlsl
// for a cheaper 5-corner alternative.
//

#ifndef _INCLUDE_CLASSIC_NOISE_4D_HLSL_
#define _INCLUDE_CLASSIC_NOISE_4D_HLSL_

#include "Packages/jp.keijiro.noiseshader/Shader/Common.hlsl"

// Helpers the package's Common.hlsl does not provide at float4 width. The guard
// macros let this coexist with SimplexNoise4D.hlsl when both are included in the
// same shader (whichever is included first defines them; the second skips).
#ifndef WGLNOISE_TAYLOR_INV_SQRT
#define WGLNOISE_TAYLOR_INV_SQRT
float  wglnoise_taylorInvSqrt(float  r) { return 1.79284291400159 - 0.85373472095314 * r; }
float4 wglnoise_taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
#endif

#ifndef WGLNOISE_FADE4
#define WGLNOISE_FADE4
float4 wglnoise_fade(float4 t) { return t * t * t * (t * (t * 6 - 15) + 10); }
#endif

float ClassicNoise_impl(float4 pi0, float4 pf0, float4 pi1, float4 pf1)
{
    pi0 = wglnoise_mod289(pi0);
    pi1 = wglnoise_mod289(pi1);

    float4 ix = float4(pi0.x, pi1.x, pi0.x, pi1.x);
    float4 iy = float4(pi0.y, pi0.y, pi1.y, pi1.y);
    float4 iz0 = pi0.z;
    float4 iz1 = pi1.z;
    float4 iw0 = pi0.w;
    float4 iw1 = pi1.w;

    float4 ixy = wglnoise_permute(wglnoise_permute(ix) + iy);
    float4 ixy0 = wglnoise_permute(ixy + iz0);
    float4 ixy1 = wglnoise_permute(ixy + iz1);
    float4 ixy00 = wglnoise_permute(ixy0 + iw0);
    float4 ixy01 = wglnoise_permute(ixy0 + iw1);
    float4 ixy10 = wglnoise_permute(ixy1 + iw0);
    float4 ixy11 = wglnoise_permute(ixy1 + iw1);

    // Gradients: 7x7x6 points over a cube, mapped onto a 4-cross polytope.
    // 7*7*6 = 294, which is close to the ring size 17*17 = 289.
    float4 gx00 = ixy00 / 7.0;
    float4 gy00 = floor(gx00) / 7.0;
    float4 gz00 = floor(gy00) / 6.0;
    gx00 = frac(gx00) - 0.5;
    gy00 = frac(gy00) - 0.5;
    gz00 = frac(gz00) - 0.5;
    float4 gw00 = 0.75 - abs(gx00) - abs(gy00) - abs(gz00);
    float4 sw00 = step(gw00, 0.0);
    gx00 -= sw00 * (step(0.0, gx00) - 0.5);
    gy00 -= sw00 * (step(0.0, gy00) - 0.5);

    float4 gx01 = ixy01 / 7.0;
    float4 gy01 = floor(gx01) / 7.0;
    float4 gz01 = floor(gy01) / 6.0;
    gx01 = frac(gx01) - 0.5;
    gy01 = frac(gy01) - 0.5;
    gz01 = frac(gz01) - 0.5;
    float4 gw01 = 0.75 - abs(gx01) - abs(gy01) - abs(gz01);
    float4 sw01 = step(gw01, 0.0);
    gx01 -= sw01 * (step(0.0, gx01) - 0.5);
    gy01 -= sw01 * (step(0.0, gy01) - 0.5);

    float4 gx10 = ixy10 / 7.0;
    float4 gy10 = floor(gx10) / 7.0;
    float4 gz10 = floor(gy10) / 6.0;
    gx10 = frac(gx10) - 0.5;
    gy10 = frac(gy10) - 0.5;
    gz10 = frac(gz10) - 0.5;
    float4 gw10 = 0.75 - abs(gx10) - abs(gy10) - abs(gz10);
    float4 sw10 = step(gw10, 0.0);
    gx10 -= sw10 * (step(0.0, gx10) - 0.5);
    gy10 -= sw10 * (step(0.0, gy10) - 0.5);

    float4 gx11 = ixy11 / 7.0;
    float4 gy11 = floor(gx11) / 7.0;
    float4 gz11 = floor(gy11) / 6.0;
    gx11 = frac(gx11) - 0.5;
    gy11 = frac(gy11) - 0.5;
    gz11 = frac(gz11) - 0.5;
    float4 gw11 = 0.75 - abs(gx11) - abs(gy11) - abs(gz11);
    float4 sw11 = step(gw11, 0.0);
    gx11 -= sw11 * (step(0.0, gx11) - 0.5);
    gy11 -= sw11 * (step(0.0, gy11) - 0.5);

    float4 g0000 = float4(gx00.x, gy00.x, gz00.x, gw00.x);
    float4 g1000 = float4(gx00.y, gy00.y, gz00.y, gw00.y);
    float4 g0100 = float4(gx00.z, gy00.z, gz00.z, gw00.z);
    float4 g1100 = float4(gx00.w, gy00.w, gz00.w, gw00.w);
    float4 g0010 = float4(gx10.x, gy10.x, gz10.x, gw10.x);
    float4 g1010 = float4(gx10.y, gy10.y, gz10.y, gw10.y);
    float4 g0110 = float4(gx10.z, gy10.z, gz10.z, gw10.z);
    float4 g1110 = float4(gx10.w, gy10.w, gz10.w, gw10.w);
    float4 g0001 = float4(gx01.x, gy01.x, gz01.x, gw01.x);
    float4 g1001 = float4(gx01.y, gy01.y, gz01.y, gw01.y);
    float4 g0101 = float4(gx01.z, gy01.z, gz01.z, gw01.z);
    float4 g1101 = float4(gx01.w, gy01.w, gz01.w, gw01.w);
    float4 g0011 = float4(gx11.x, gy11.x, gz11.x, gw11.x);
    float4 g1011 = float4(gx11.y, gy11.y, gz11.y, gw11.y);
    float4 g0111 = float4(gx11.z, gy11.z, gz11.z, gw11.z);
    float4 g1111 = float4(gx11.w, gy11.w, gz11.w, gw11.w);

    // Normalize the 16 gradients (taylorInvSqrt approximates 1/length).
    float4 norm00 = wglnoise_taylorInvSqrt(float4(dot(g0000, g0000), dot(g0100, g0100), dot(g1000, g1000), dot(g1100, g1100)));
    g0000 *= norm00.x;
    g0100 *= norm00.y;
    g1000 *= norm00.z;
    g1100 *= norm00.w;

    float4 norm01 = wglnoise_taylorInvSqrt(float4(dot(g0001, g0001), dot(g0101, g0101), dot(g1001, g1001), dot(g1101, g1101)));
    g0001 *= norm01.x;
    g0101 *= norm01.y;
    g1001 *= norm01.z;
    g1101 *= norm01.w;

    float4 norm10 = wglnoise_taylorInvSqrt(float4(dot(g0010, g0010), dot(g0110, g0110), dot(g1010, g1010), dot(g1110, g1110)));
    g0010 *= norm10.x;
    g0110 *= norm10.y;
    g1010 *= norm10.z;
    g1110 *= norm10.w;

    float4 norm11 = wglnoise_taylorInvSqrt(float4(dot(g0011, g0011), dot(g0111, g0111), dot(g1011, g1011), dot(g1111, g1111)));
    g0011 *= norm11.x;
    g0111 *= norm11.y;
    g1011 *= norm11.z;
    g1111 *= norm11.w;

    float n0000 = dot(g0000, pf0);
    float n1000 = dot(g1000, float4(pf1.x, pf0.y, pf0.z, pf0.w));
    float n0100 = dot(g0100, float4(pf0.x, pf1.y, pf0.z, pf0.w));
    float n1100 = dot(g1100, float4(pf1.x, pf1.y, pf0.z, pf0.w));
    float n0010 = dot(g0010, float4(pf0.x, pf0.y, pf1.z, pf0.w));
    float n1010 = dot(g1010, float4(pf1.x, pf0.y, pf1.z, pf0.w));
    float n0110 = dot(g0110, float4(pf0.x, pf1.y, pf1.z, pf0.w));
    float n1110 = dot(g1110, float4(pf1.x, pf1.y, pf1.z, pf0.w));
    float n0001 = dot(g0001, float4(pf0.x, pf0.y, pf0.z, pf1.w));
    float n1001 = dot(g1001, float4(pf1.x, pf0.y, pf0.z, pf1.w));
    float n0101 = dot(g0101, float4(pf0.x, pf1.y, pf0.z, pf1.w));
    float n1101 = dot(g1101, float4(pf1.x, pf1.y, pf0.z, pf1.w));
    float n0011 = dot(g0011, float4(pf0.x, pf0.y, pf1.z, pf1.w));
    float n1011 = dot(g1011, float4(pf1.x, pf0.y, pf1.z, pf1.w));
    float n0111 = dot(g0111, float4(pf0.x, pf1.y, pf1.z, pf1.w));
    float n1111 = dot(g1111, pf1);

    float4 fade_xyzw = wglnoise_fade(pf0);
    float4 n_0w = lerp(float4(n0000, n1000, n0100, n1100), float4(n0001, n1001, n0101, n1101), fade_xyzw.w);
    float4 n_1w = lerp(float4(n0010, n1010, n0110, n1110), float4(n0011, n1011, n0111, n1111), fade_xyzw.w);
    float4 n_zw = lerp(n_0w, n_1w, fade_xyzw.z);
    float2 n_yzw = lerp(n_zw.xy, n_zw.zw, fade_xyzw.y);
    float n_xyzw = lerp(n_yzw.x, n_yzw.y, fade_xyzw.x);
    return 2.2 * n_xyzw;
}

// Classic Perlin noise, 4D
float ClassicNoise(float4 p)
{
    float4 i = floor(p);
    float4 f = frac(p);
    return ClassicNoise_impl(i, f, i + 1, f - 1);
}

// Classic Perlin noise, 4D periodic variant. `rep` is the integer period on each
// axis; useful for looping the animation/morph (w) axis seamlessly.
float PeriodicNoise(float4 p, float4 rep)
{
    float4 i0 = wglnoise_mod(floor(p), rep);
    float4 i1 = wglnoise_mod(i0 + 1, rep);
    float4 f = frac(p);
    return ClassicNoise_impl(i0, f, i1, f - 1);
}

#endif
