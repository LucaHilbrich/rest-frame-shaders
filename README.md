# Rest Frame Shaders

Rest-frame-anchored 4D-noise cross-fade shaders for the **Universal Render Pipeline (URP)**.

Each shader cross-fades between two complete surfaces ("A" and "B") using one shared,
rest-frame-anchored noise field. Anchor the field to a moving object (e.g. an XR camera or
rig) and the reveal pattern rides with it; with no anchor it is plain world space.

- **VR/RestFrame** — lit mesh shader (URP SimpleLit base); Surface A/B with normal / specular / emission maps.
- **VR/TerrainRestFrame** — terrain shader; reveals a second PBR surface over the painted terrain.
- **Skybox/RestFrame** — unlit skybox; cross-fades two cubemaps along the view ray.

## Requirements

- Unity **6000.0** or newer
- Universal Render Pipeline (`com.unity.render-pipelines.universal`) **17.0+**
- `jp.keijiro.noiseshader` **3.x** (from the Keijiro scoped registry — see install step 1)

## Installation

### 1. Add the Keijiro scoped registry (required)

This package depends on `jp.keijiro.noiseshader`, which is served from Keijiro's scoped
registry. Add it **before** installing this package, or the install will fail to resolve.

**Edit > Project Settings > Package Manager > Scoped Registries > +**

- Name: `Keijiro`
- URL: `https://registry.npmjs.com`
- Scope(s): `jp.keijiro`

(Equivalent edit to `Packages/manifest.json`:)

```json
"scopedRegistries": [
  { "name": "Keijiro", "url": "https://registry.npmjs.com", "scopes": ["jp.keijiro"] }
]
```

### 2a. Add this package by downloading the zip file and unpacking it

**Window > Package Manager > + > Install package from disk…**

Choose the package.json file inside the package folder.

### 2b. Add this package by Git URL

**Window > Package Manager > + > Install package from git URL…**

```
https://github.com/<your-username>/rest-frame-shaders.git
```

To pin a specific release, append a tag:

```
https://github.com/<your-username>/rest-frame-shaders.git#v1.0.0
```

## Usage

1. Create a material and assign one of the shaders (`VR/RestFrame`, `VR/TerrainRestFrame`,
   `Skybox/RestFrame`). The custom inspector groups Surface A/B, Noise Blend, Animation,
   Coordinate Override, Blend Shaping and (where applicable) Rest Frame Radius / Baked
   Lightmap Mask.
2. To anchor the noise field to a moving object, add the **RestFrameShaderFeed** component
   to that object (e.g. your XR rig or camera). It feeds the global `_RestFrameAnchor`
   matrix each frame, so the reveal pattern rigidly follows the anchor. Without a feed, the
   field stays in world space.
3. For the skybox, assign the material in **Lighting > Environment > Skybox Material**.

## Demo

**Window > Package Manager > Rest Frame Shaders > Samples > Import "Demo Scene"**, then open
the imported `Demo` scene.

## License

MIT — see [LICENSE.md](LICENSE.md). The 4D noise primitives derive from
`jp.keijiro.noiseshader` (public domain); see [Third Party Notices.md](Third%20Party%20Notices.md).
