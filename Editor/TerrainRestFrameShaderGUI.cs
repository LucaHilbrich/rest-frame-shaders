// Custom material inspector for the "VR/TerrainRestFrame" shader. Terrain layers (Surface A)
// are painted via the Terrain component's Paint Texture tool - Unity's terrain system manages
// the layer / normal / mask data, not this ShaderGUI - so on top of the shared Rest Frame
// sections (RestFrameShaderGUIBase) this only adds the revealed Surface B inputs and a small
// terrain info block. Wired up by  CustomEditor "TerrainRestFrameShaderGUI"  in
// TerrainRestFrame.shader.

using System;
using UnityEditor;
using UnityEngine;

public class TerrainRestFrameShaderGUI : RestFrameShaderGUIBase
{
    protected override string FoldPrefix => "VR.TerrainRestFrame.fold.";

    protected override void DrawSections()
    {
        Section("Surface A (Terrain)",     "terrain",  true,  DrawTerrain);
        Section("Surface B (Object)",      "surfB",    true,  DrawSurfaceB);
        Section("Noise Blend",             "noise",    true,  DrawNoiseBlend);
        Section("Animation",               "anim",     true,  DrawAnimation);
        Section("Coordinate Override",     "coord",    false, DrawCoordinateOverride);
        Section("Blend Shaping",           "shape",    true,  DrawBlendShaping);
        Section("Rest Frame Radius",       "radius",   false, DrawRestFrameRadius);
        Section("Baked Lightmap Mask",     "lightmap", false, DrawLightmapMask);
    }

    void DrawTerrain()
    {
        EditorGUILayout.HelpBox(
            "Surface A is the painted terrain. Add and paint terrain layers from the " +
            "Terrain component's Paint Texture tool, as with any URP terrain.", MessageType.None);
        Prop("_HeightTransition", "Height Transition", "Height-blend sharpness (only used when layers have height in their mask maps).");
        var ppn = P("_EnableInstancedPerPixelNormal");
        if (ppn != null)
            ToggleFlag(ppn, "Instanced Per-Pixel Normal",
                       "Sample the terrain normal per pixel when GPU instancing is on (smoother normals).");
    }

    void DrawSurfaceB()
    {
        Tex("Base Map", "_BaseMapB", "_BaseColorB", withTiling: true,
            tip: "RGB albedo. Tiling/offset controls how Surface B repeats over the terrain.");
        Tex("Normal Map", "_BumpMapB", null, withTiling: false,
            tip: "Tangent-space normals (only applied where the terrain has a normal/tangent frame).");
        Prop("_BumpScaleB",  "Normal Scale");
        Prop("_MetallicB",   "Metallic");
        Prop("_SmoothnessB", "Smoothness");
        Prop("_OcclusionB",  "Occlusion");

        EditorGUILayout.Space(2);
        Prop("_EmissionEnabledB", "Use Emission");   // [Toggle(_EMISSIONB)] -> keyword
        using (new EditorGUI.DisabledScope(!IsOn("_EmissionEnabledB")))
            Tex("Emission Map", "_EmissionMapB", "_EmissionColorB", withTiling: false,
                tip: "Emissive color (HDR).");
    }

    protected override void SyncStateKeywords()
    {
        foreach (var o in _editor.targets)
        {
            if (!(o is Material m)) continue;

            if (m.HasProperty("_EnableInstancedPerPixelNormal"))
            {
                bool on = m.GetFloat("_EnableInstancedPerPixelNormal") > 0.5f;
                if (m.IsKeywordEnabled("_TERRAIN_INSTANCED_PERPIXEL_NORMAL") != on)
                    SetKeyword(m, "_TERRAIN_INSTANCED_PERPIXEL_NORMAL", on);
            }
        }
    }
}
