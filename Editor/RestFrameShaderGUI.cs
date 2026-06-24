// Custom material inspector for the "VR/RestFrame" shader. On top of the shared Rest Frame
// sections (RestFrameShaderGUIBase) it adds the SimpleLit Surface A / B maps, the shared
// surface feature toggles and an Advanced block. The few plain [ToggleUI] state flags
// (_AlphaClip, _ReceiveShadows) have their keywords reconciled in SyncStateKeywords().
// Wired up by  CustomEditor "RestFrameShaderGUI"  at the end of RestFrame.shader.

using System;
using UnityEditor;
using UnityEngine;

public class RestFrameShaderGUI : RestFrameShaderGUIBase
{
    protected override string FoldPrefix => "VR.RestFrame.fold.";

    protected override void DrawSections()
    {
        Section("Surface A (Object)",      "surfA",       true,  () => DrawSurface(""));
        Section("Surface B (Object)",      "surfB",       true,  () => DrawSurface("B"));
        Section("Noise Blend",             "noise",       true,  DrawNoiseBlend);
        Section("Animation",               "anim",        true,  DrawAnimation);
        Section("Coordinate Override",     "coord",       false, DrawCoordinateOverride);
        Section("Blend Shaping",           "shape",       true,  DrawBlendShaping);
        Section("Rest Frame Radius",       "radius",      false, DrawRestFrameRadius);
        Section("Baked Lightmap Mask",     "lightmap",    false, DrawLightmapMask);
        Section("Shared Surface Options",  "surfaceOpts", false, DrawSharedOptions);
        Section("Advanced",                "advanced",    false, DrawAdvanced);
    }

    void DrawSurface(string s)
    {
        Tex("Base Map", "_BaseMap" + s, "_BaseColor" + s, withTiling: true,
            tip: "RGB albedo, A = smoothness / alpha.");
        Tex("Specular Map", "_SpecGlossMap" + s, "_SpecColor" + s, withTiling: false,
            tip: "Specular tint; alpha of the color = smoothness. Needs 'Use Specular Highlights'.");
        Tex("Normal Map", "_BumpMap" + s, null, withTiling: false,
            tip: "Tangent-space normals. Needs 'Use Normal Maps'.");
        Tex("Emission Map", "_EmissionMap" + s, "_EmissionColor" + s, withTiling: false,
            tip: "Emissive color (HDR). Needs 'Use Emission'.");
    }

    void DrawSharedOptions()
    {
        EditorGUILayout.HelpBox(
            "These enable Normal / Specular / Emission for BOTH surfaces. The matching " +
            "map slots in Surface A / B only take effect when enabled here.", MessageType.None);

        Prop("_NormalMapEnabled",     "Use Normal Maps");
        Prop("_SpecularColorEnabled", "Use Specular Highlights");
        Prop("_EmissionEnabled",      "Use Emission");

        EditorGUILayout.Space(4);

        // Alpha clipping - plain state flag; the _ALPHATEST_ON keyword and
        // _AlphaToMask are derived from it in SyncStateKeywords().
        var clip = P("_AlphaClip");
        if (clip != null)
        {
            ToggleFlag(clip, "Alpha Clipping", "Discard pixels below the threshold (cutout).");
            using (new EditorGUI.DisabledScope(clip.floatValue < 0.5f))
                Prop("_Cutoff", "Threshold");
        }

        // Receive shadows - drives the _RECEIVE_SHADOWS_OFF keyword (see sync).
        var recv = P("_ReceiveShadows");
        if (recv != null)
            ToggleFlag(recv, "Receive Shadows");
    }

    void DrawAdvanced()
    {
        // Render face from _Cull. URP convention: Front = Cull Back (2, default),
        // Back = Cull Front (1), Both = Cull Off (0).
        var cull = P("_Cull");
        if (cull != null)
        {
            string[] names  = { "Front", "Back", "Both" };
            int[]    values = { 2, 1, 0 };
            int idx = Mathf.Max(0, Array.IndexOf(values, Mathf.RoundToInt(cull.floatValue)));

            EditorGUI.showMixedValue = cull.hasMixedValue;
            EditorGUI.BeginChangeCheck();
            idx = EditorGUILayout.Popup(C("Render Face", "Which faces to render."), idx, names);
            if (EditorGUI.EndChangeCheck())
            {
                _editor.RegisterPropertyChangeUndo("Render Face");
                cull.floatValue = values[idx];
            }
            EditorGUI.showMixedValue = false;
        }

        _editor.EnableInstancingField();
        _editor.DoubleSidedGIField();
        _editor.RenderQueueField();
    }

    protected override void SyncStateKeywords()
    {
        foreach (var o in _editor.targets)
        {
            if (!(o is Material m)) continue;

            if (m.HasProperty("_AlphaClip"))
            {
                bool clip = m.GetFloat("_AlphaClip") > 0.5f;
                if (m.IsKeywordEnabled("_ALPHATEST_ON") != clip)
                    SetKeyword(m, "_ALPHATEST_ON", clip);
                if (m.HasProperty("_AlphaToMask") && (m.GetFloat("_AlphaToMask") > 0.5f) != clip)
                    m.SetFloat("_AlphaToMask", clip ? 1f : 0f);
            }

            if (m.HasProperty("_ReceiveShadows"))
            {
                bool off = m.GetFloat("_ReceiveShadows") < 0.5f;
                if (m.IsKeywordEnabled("_RECEIVE_SHADOWS_OFF") != off)
                    SetKeyword(m, "_RECEIVE_SHADOWS_OFF", off);
            }
        }
    }
}
