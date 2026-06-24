//
// 4D port for the rest frame noise synthesizer. Mirrors the package's
// SimplexNoise3D.hlsl style so SimplexNoise() is overloaded by dimension - Fbm() can
// call SimplexNoise(p) with either a float3 or a float4. This lives in the project
// rather than the package cache (Library/PackageCache, which Unity regenerates)
// because the bundled jp.keijiro.noiseshader ships only 2D/3D noise.
//
// Cost note: 4D simplex evaluates a 5-corner simplex, vs the 16-corner lattice of
// 4D Perlin (ClassicNoise4D.hlsl), so it is markedly cheaper per sample - the reason
// to prefer it for the animated/morphing field on VR hardware. The visual character
// differs from classic Perlin, so the choice applies to the whole field.
//

#ifndef _INCLUDE_SIMPLEX_NOISE_4D_HLSL_
#define _INCLUDE_SIMPLEX_NOISE_4D_HLSL_

#include "Packages/jp.keijiro.noiseshader/Shader/Common.hlsl"

// Helpers the package's Common.hlsl does not provide. The guard macros let this
// coexist with ClassicNoise4D.hlsl when both are included in the same shader
// (whichever is included first defines them; the second skips).
#ifndef WGLNOISE_TAYLOR_INV_SQRT
#define WGLNOISE_TAYLOR_INV_SQRT
float  wglnoise_taylorInvSqrt(float  r) { return 1.79284291400159 - 0.85373472095314 * r; }
float4 wglnoise_taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
#endif

#ifndef WGLNOISE_PERMUTE_SCALAR
#define WGLNOISE_PERMUTE_SCALAR
float wglnoise_permute(float x) { return wglnoise_mod289((x * 34 + 10) * x); }
#endif

// One gradient on the 7x7x6 grid mapped onto a 4-cross polytope.
float4 SimplexNoise4DGrad(float j, float4 ip)
{
    float4 p;
    p.xyz = floor(frac(j * ip.xyz) * 7.0) * ip.z - 1.0;
    p.w = 1.5 - dot(abs(p.xyz), 1.0);
    float4 s = (p < 0.0) ? 1.0 : 0.0;
    p.xyz = p.xyz + (s.xyz * 2.0 - 1.0) * s.www;
    return p;
}

float SimplexNoise(float4 v)
{
    const float4 C = float4( 0.138196601125011,   // (5 - sqrt(5))/20 = G4
                             0.276393202250021,   // 2 * G4
                             0.414589803375032,   // 3 * G4
                            -0.447213595499958);  // -1 + 4 * G4
    const float F4 = 0.309016994374947451;        // (sqrt(5) - 1)/4

    // First corner
    float4 i  = floor(v + dot(v, F4));
    float4 x0 = v - i + dot(i, C.xxxx);

    // Other corners: rank the components of x0 to find which simplex cell we are in.
    float4 i0;
    float3 isX  = step(x0.yzw, x0.xxx);
    float3 isYZ = step(x0.zww, x0.yyz);
    i0.x = isX.x + isX.y + isX.z;
    i0.yzw = 1.0 - isX;
    i0.y += isYZ.x + isYZ.y;
    i0.zw += 1.0 - isYZ.xy;
    i0.z += isYZ.z;
    i0.w += 1.0 - isYZ.z;

    // i0 now holds the unique values 0,1,2,3 in its channels - the corner offsets.
    float4 i3 = saturate(i0);
    float4 i2 = saturate(i0 - 1.0);
    float4 i1 = saturate(i0 - 2.0);

    float4 x1 = x0 - i1 + C.xxxx;
    float4 x2 = x0 - i2 + C.yyyy;
    float4 x3 = x0 - i3 + C.zzzz;
    float4 x4 = x0 + C.wwww;

    // Permutations
    i = wglnoise_mod289(i);
    float j0 = wglnoise_permute(wglnoise_permute(wglnoise_permute(wglnoise_permute(i.w) + i.z) + i.y) + i.x);
    float4 j1 = wglnoise_permute(wglnoise_permute(wglnoise_permute(wglnoise_permute(
                 i.w + float4(i1.w, i2.w, i3.w, 1.0))
               + i.z + float4(i1.z, i2.z, i3.z, 1.0))
               + i.y + float4(i1.y, i2.y, i3.y, 1.0))
               + i.x + float4(i1.x, i2.x, i3.x, 1.0));

    // Gradients: 7x7x6 points over a cube, mapped onto a 4-cross polytope.
    // 7*7*6 = 294, which is close to the ring size 17*17 = 289.
    const float4 ip = float4(1.0 / 294.0, 1.0 / 49.0, 1.0 / 7.0, 0.0);

    float4 p0 = SimplexNoise4DGrad(j0,   ip);
    float4 p1 = SimplexNoise4DGrad(j1.x, ip);
    float4 p2 = SimplexNoise4DGrad(j1.y, ip);
    float4 p3 = SimplexNoise4DGrad(j1.z, ip);
    float4 p4 = SimplexNoise4DGrad(j1.w, ip);

    // Normalize gradients
    float4 norm = wglnoise_taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;
    p4 *= wglnoise_taylorInvSqrt(dot(p4, p4));

    // Mix contributions from the five corners
    float3 m0 = max(0.6 - float3(dot(x0, x0), dot(x1, x1), dot(x2, x2)), 0.0);
    float2 m1 = max(0.6 - float2(dot(x3, x3), dot(x4, x4)), 0.0);
    m0 = m0 * m0;
    m1 = m1 * m1;
    return 49.0 * (dot(m0 * m0, float3(dot(p0, x0), dot(p1, x1), dot(p2, x2)))
                 + dot(m1 * m1, float2(dot(p3, x3), dot(p4, x4))));
}

#endif
