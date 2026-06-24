// Shared base for the Rest Frame family of material inspectors (RestFrameShaderGUI,
// TerrainRestFrameShaderGUI, SkyboxRestFrameShaderGUI). It owns everything those three
// inspectors have in common: the collapsible-section framework, the per-coordinate
// X / Y / Z / W table, the shared Noise Blend / Animation / Coordinate Override / Blend
// Shaping / Rest Frame Radius / Baked Lightmap Mask sections, and the small property-drawer
// helpers - so each shader's ShaderGUI only adds its own surface-specific sections.
//
// Compiled into the package's editor assembly (RestFrameShader.Editor.asmdef). A subclass
// implements DrawSections() to compose its inspector (its surface sections plus whichever of
// the shared Draw* sections apply), supplies a FoldPrefix to namespace its saved fold state,
// and may override SyncStateKeywords() to reconcile plain [ToggleUI] flags into GPU keywords.
// Keyword-backed properties ([Toggle(...)], [KeywordEnum]) are drawn with
// MaterialEditor.ShaderProperty so their material drawer keeps setting the shader keyword.

using System;
using UnityEditor;
using UnityEngine;

public abstract class RestFrameShaderGUIBase : ShaderGUI
{
    protected MaterialEditor _editor;
    protected MaterialProperty[] _props;

    static GUIStyle s_ColHeader;   // centered X/Y/Z/W column captions
    static readonly string[] s_OscType = { "Perlin", "Sine" };   // _OscType* dropdown (0/1)

    // ---- collapsible-section state, persisted per user in EditorPrefs --------
    // Each shader namespaces its own fold state through FoldPrefix.
    protected abstract string FoldPrefix { get; }
    bool GetFold(string k, bool d) => EditorPrefs.GetBool(FoldPrefix + k, d);
    void SetFold(string k, bool v) => EditorPrefs.SetBool(FoldPrefix + k, v);

    // World-space wording for the mesh shaders; the skybox overrides it (the field is
    // sampled along the view ray there, so its Base Frequency is angular).
    protected virtual string BaseFrequencyTip => "World-space scale; smaller = larger, smoother features.";

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        _editor = materialEditor;
        _props  = properties;
        EnsureStyles();

        DrawSections();
        SyncStateKeywords();
    }

    // Compose the inspector: the shader's surface sections + whichever shared Draw* sections apply.
    protected abstract void DrawSections();

    // Reconcile GPU state derived from plain [ToggleUI] flags (default: nothing to do).
    protected virtual void SyncStateKeywords() { }

    // ===== shared sections ===================================================

    protected void DrawNoiseBlend()
    {
        Prop("_NoiseType",     "Noise Type", "Sine = sum of axis sines; Perlin = Classic 4D; Simplex = 4D.");
        Prop("_BaseFrequency", "Base Frequency", BaseFrequencyTip);
        Prop("_BaseAmplitude", "Base Amplitude");
        Prop("_Octaves",       "Octaves", "Layers of noise summed together. Main per-pixel cost lever.");
        Prop("_Lacunarity",    "Lacunarity", "Frequency multiplier per octave.");
        Prop("_Gain",          "Gain / Persistence", "Amplitude multiplier per octave.");

        var warp = P("_DomainWarpEnabled");
        Prop("_DomainWarpEnabled", "Enable Domain Warp",
             "Feeds noise back into the sample position for swirls / marbling.");
        using (new EditorGUI.DisabledScope(warp == null || warp.floatValue < 0.5f))
        {
            Prop("_WarpStrength", "Warp Strength");
            Prop("_WarpFeedback", "Warp Feedback");
        }
    }

    protected void DrawAnimation()
    {
        AxisHeader();
        VectorRow("Linear Speed", "_AnimationSpeed",
                  "Constant drift per axis (xyz = flow, w = morph). Noise units / sec.");
        EnumRow("Oscillation Type", "Per axis: Perlin (organic wander) or Sine (regular).",
                s_OscType, "_OscTypeX", "_OscTypeY", "_OscTypeZ", "_OscTypeW");
        VectorRow("Oscillatory Speed", "_OscSpeed",
                  "Oscillation rate per axis (Perlin: lattice steps/sec, Sine: cycles/sec).");
        VectorRow("Oscillatory Magnitude", "_OscMagnitude",
                  "Oscillation amplitude per axis (noise-domain units). 0 = no oscillation.");
    }

    protected void DrawCoordinateOverride()
    {
        EditorGUILayout.LabelField(
            "Pin a coordinate to a constant - removes all variation along that axis.",
            EditorStyles.miniLabel);
        AxisHeader();
        ToggleRow("Use Constant", "On = feed the constant below for that axis instead of the real coordinate.",
                  "_CoordConstX", "_CoordConstY", "_CoordConstZ", "_CoordConstW");
        VectorRow("Constant Value", "_CoordConstValues",
                  "Noise-domain value used where the matching axis is pinned.");
    }

    protected void DrawBlendShaping()
    {
        Prop("_NoiseBias",  "Blend Bias", "Shifts the mask toward Surface A or B.");
        Prop("_Contrast",   "Blend Contrast");
        Prop("_Saturation", "Saturation", "0 = smooth gradient, 1 = hard binary A/B cut.");
    }

    protected void DrawRestFrameRadius()
    {
        var en = P("_RestFrameRadiusEnabled");
        Prop("_RestFrameRadiusEnabled", "Enable Radius",
             "Outside the radius the field is world-anchored (does not follow the anchor).");
        using (new EditorGUI.DisabledScope(en == null || en.floatValue < 0.5f))
        {
            Prop("_RestFrameRadius",       "Radius (m)");
            Prop("_OutsideNoiseBias",      "Outside - Blend Bias");
            Prop("_OutsideFrequencyScale", "Outside - Frequency Scale");

            EditorGUILayout.Space(2);
            EditorGUILayout.LabelField(
                "Freeze animation outside the radius (holds the t = 0 state per axis):",
                EditorStyles.miniLabel);
            AxisHeader();
            ToggleRow("Freeze Outside", "On = that axis stops animating in the world-anchored region.",
                      "_OutsideAnimFreezeX", "_OutsideAnimFreezeY", "_OutsideAnimFreezeZ", "_OutsideAnimFreezeW");
        }
    }

    protected void DrawLightmapMask()
    {
        var en = P("_LightmapMaskEnabled");
        Prop("_LightmapMaskEnabled", "Use Baked Lightmap as Mask",
             "Forces Surface A where the baked lightmap is bright. Lightmapped (static) objects only.");
        using (new EditorGUI.DisabledScope(en == null || en.floatValue < 0.5f))
        {
            Prop("_LightmapMaskLow",    "Lit Threshold - Start");
            Prop("_LightmapMaskHigh",   "Lit Threshold - Full");
            Prop("_LightmapMaskInvert", "Invert (noise only in lit areas)");
        }
    }

    // ===== per-axis table (X / Y / Z / W) ====================================

    // Caption row: blank label cell, then centered X Y Z W over the value columns.
    protected void AxisHeader()
    {
        Rect[] cols = AxisColumns(EditorGUILayout.GetControlRect(), out _);
        string[] n = { "X", "Y", "Z", "W" };
        for (int i = 0; i < 4; i++) GUI.Label(cols[i], n[i], s_ColHeader);
    }

    // One Vector4 property drawn as a row of four float fields.
    protected void VectorRow(string label, string propName, string tip = "")
    {
        var prop = P(propName);
        Rect[] cols = AxisColumns(EditorGUILayout.GetControlRect(), out Rect labelRect);
        GUI.Label(labelRect, C(label, tip));
        if (prop == null) return;

        Vector4 v = prop.vectorValue;
        EditorGUI.showMixedValue = prop.hasMixedValue;
        EditorGUI.BeginChangeCheck();
        float x = EditorGUI.FloatField(cols[0], v.x);
        float y = EditorGUI.FloatField(cols[1], v.y);
        float z = EditorGUI.FloatField(cols[2], v.z);
        float w = EditorGUI.FloatField(cols[3], v.w);
        if (EditorGUI.EndChangeCheck())
        {
            _editor.RegisterPropertyChangeUndo(label);
            prop.vectorValue = new Vector4(x, y, z, w);
        }
        EditorGUI.showMixedValue = false;
    }

    // Four 0/1 float properties drawn as a row of centered checkboxes.
    protected void ToggleRow(string label, string tip, params string[] propNames)
    {
        Rect[] cols = AxisColumns(EditorGUILayout.GetControlRect(), out Rect labelRect);
        GUI.Label(labelRect, C(label, tip));
        for (int i = 0; i < 4 && i < propNames.Length; i++)
        {
            var prop = P(propNames[i]);
            if (prop == null) continue;

            Rect box = new Rect(cols[i].x + cols[i].width * 0.5f - 7f, cols[i].y, 16f, cols[i].height);
            EditorGUI.showMixedValue = prop.hasMixedValue;
            EditorGUI.BeginChangeCheck();
            bool on = EditorGUI.Toggle(box, prop.floatValue > 0.5f);
            if (EditorGUI.EndChangeCheck())
            {
                _editor.RegisterPropertyChangeUndo(label);
                prop.floatValue = on ? 1f : 0f;
            }
            EditorGUI.showMixedValue = false;
        }
    }

    // Four enum properties (stored as 0/1 floats) drawn as a row of dropdowns.
    protected void EnumRow(string label, string tip, string[] options, params string[] propNames)
    {
        Rect[] cols = AxisColumns(EditorGUILayout.GetControlRect(), out Rect labelRect);
        GUI.Label(labelRect, C(label, tip));
        for (int i = 0; i < 4 && i < propNames.Length; i++)
        {
            var prop = P(propNames[i]);
            if (prop == null) continue;

            int cur = prop.floatValue > 0.5f ? 1 : 0;
            EditorGUI.showMixedValue = prop.hasMixedValue;
            EditorGUI.BeginChangeCheck();
            int next = EditorGUI.Popup(cols[i], cur, options);
            if (EditorGUI.EndChangeCheck())
            {
                _editor.RegisterPropertyChangeUndo(label);
                prop.floatValue = next;
            }
            EditorGUI.showMixedValue = false;
        }
    }

    // Split a single layout line into [label cell] + four equal value columns.
    static Rect[] AxisColumns(Rect row, out Rect labelRect)
    {
        const float gap = 4f;
        float labelW = EditorGUIUtility.labelWidth;
        labelRect = new Rect(row.x, row.y, labelW - gap, row.height);

        float fieldsX = row.x + labelW;
        float colW    = (row.width - labelW - gap * 3f) / 4f;
        Rect[] cols = new Rect[4];
        for (int i = 0; i < 4; i++)
            cols[i] = new Rect(fieldsX + i * (colW + gap), row.y, colW, row.height);
        return cols;
    }

    // ===== helpers ===========================================================

    protected MaterialProperty P(string name) => FindProperty(name, _props, false);

    protected bool IsOn(string name) { var p = P(name); return p != null && p.floatValue > 0.5f; }

    // Draw a property with the proper drawer (slider / toggle-keyword / etc.).
    protected void Prop(string name, string label, string tip = "")
    {
        var prop = P(name);
        if (prop != null) _editor.ShaderProperty(prop, C(label, tip));
    }

    // A plain 0/1 state flag (no keyword in its attribute) as a checkbox.
    protected void ToggleFlag(MaterialProperty prop, string label, string tip = "")
    {
        EditorGUI.showMixedValue = prop.hasMixedValue;
        EditorGUI.BeginChangeCheck();
        bool on = EditorGUILayout.Toggle(C(label, tip), prop.floatValue > 0.5f);
        if (EditorGUI.EndChangeCheck())
        {
            _editor.RegisterPropertyChangeUndo(label);
            prop.floatValue = on ? 1f : 0f;
        }
        EditorGUI.showMixedValue = false;
    }

    protected void Tex(string label, string texName, string colorName, bool withTiling, string tip = "")
    {
        var tex = P(texName);
        if (tex == null) return;
        var color = string.IsNullOrEmpty(colorName) ? null : P(colorName);

        if (color != null) _editor.TexturePropertySingleLine(C(label, tip), tex, color);
        else               _editor.TexturePropertySingleLine(C(label, tip), tex);

        if (withTiling)
        {
            EditorGUI.indentLevel++;
            _editor.TextureScaleOffsetProperty(tex);
            EditorGUI.indentLevel--;
        }
    }

    protected static void SetKeyword(Material m, string keyword, bool on)
    {
        if (on) m.EnableKeyword(keyword);
        else    m.DisableKeyword(keyword);
    }

    protected void Section(string title, string key, bool def, Action body)
    {
        bool state = GetFold(key, def);
        bool ns = EditorGUILayout.BeginFoldoutHeaderGroup(state, title);
        if (ns != state) SetFold(key, ns);
        if (ns)
        {
            EditorGUILayout.Space(2);
            body();
            EditorGUILayout.Space(4);
        }
        EditorGUILayout.EndFoldoutHeaderGroup();
    }

    protected static GUIContent C(string label, string tip = "") => new GUIContent(label, tip);

    static void EnsureStyles()
    {
        s_ColHeader ??= new GUIStyle(EditorStyles.miniBoldLabel) { alignment = TextAnchor.MiddleCenter };
    }
}
