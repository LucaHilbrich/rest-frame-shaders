# Third Party Notices

This package uses the following third-party components.

## NoiseShader (jp.keijiro.noiseshader)

The 4D noise primitives in `Runtime/Shaders/ClassicNoise4D.hlsl` and
`Runtime/Shaders/SimplexNoise4D.hlsl` are ports/extensions of the noise functions in
**jp.keijiro.noiseshader**, which is released into the public domain (Unlicense).

- Source: https://github.com/keijiro/NoiseShader

The package also takes a runtime dependency on `jp.keijiro.noiseshader` (declared in
`package.json`); install it via the Keijiro scoped registry as described in the README.
