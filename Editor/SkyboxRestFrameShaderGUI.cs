// Custom material inspector for the "Skybox/RestFrame" shader. On top of the shared Rest Frame
// sections (RestFrameShaderGUIBase) it adds the two cubemap surfaces (A / B) and an Exposure
// control. There are no Surface feature toggles, no Rest Frame Radius and no Baked Lightmap
// Mask (those features are dropped on the skybox), so it needs no state-keyword reconciliation.
// The field is sampled along the per-pixel view ray, so Base Frequency is angular here (see
// BaseFrequencyTip). Wired up by  CustomEditor "SkyboxRestFrameShaderGUI"  at the end of
// SkyboxRestFrame.shader.

using System;
using UnityEditor;
using UnityEngine;

public class SkyboxRestFrameShaderGUI : RestFrameShaderGUIBase
{
    protected override string FoldPrefix => "VR.SkyboxRestFrame.fold.";

    // The skybox samples the field along the (unit) view ray, so Base Frequency is angular.
    protected override string BaseFrequencyTip => "Angular scale; higher = finer detail across the sky.";

    protected override void DrawSections()
    {
        Section("Surface A (Cubemap)",  "surfA", true,  () => DrawSurface("A"));
        Section("Surface B (Cubemap)",  "surfB", true,  () => DrawSurface("B"));
        Section("Sky",                  "sky",   true,  DrawSky);
        Section("Noise Blend",          "noise", true,  DrawNoiseBlend);
        Section("Animation",            "anim",  true,  DrawAnimation);
        Section("Coordinate Override",  "coord", false, DrawCoordinateOverride);
        Section("Blend Shaping",        "shape", true,  DrawBlendShaping);
    }

    void DrawSurface(string s)
    {
        Tex("Cubemap", "_Cubemap" + s, "_Tint" + s, withTiling: false,
            tip: "Cubemap sky for this surface, multiplied by the (HDR) tint. Sampled with the " +
                 "plain world view ray - only the noise reveal is rest-frame anchored, not the imagery.");
    }

    void DrawSky()
    {
        Prop("_Exposure", "Exposure", "Overall brightness multiplier on the blended sky.");
    }
}
