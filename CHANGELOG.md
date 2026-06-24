# Changelog

All notable changes to this package are documented in this file.

## [1.0.0] - 2026-06-24

### Added
- Initial release.
- `VR/RestFrame` — lit mesh shader (URP SimpleLit base) that cross-fades between two complete surfaces (A/B) via a rest-frame-anchored 4D noise field.
- `VR/TerrainRestFrame` — terrain shader that reveals a second PBR surface over the painted terrain using the same field.
- `Skybox/RestFrame` — unlit skybox that cross-fades two cubemaps along the view ray.
- `RestFrameShaderFeed` component to anchor the noise field to a moving object.
- Shared sectioned material inspectors and a `Demo Scene` sample.
