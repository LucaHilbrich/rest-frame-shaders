using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

// Feeds this object's pose to the shaders as the global _RestFrameAnchor matrix
// (world -> anchor-local, rotation + translation only), once per rendered frame.
// Put it on the rest-frame anchor object (e.g. the XR camera or rig); the
// RestFrame field then rigidly follows that object.
//
// The matrix is a shader GLOBAL so every material sees the same value and, in XR,
// both eyes sample the same field - per-eye built-ins like UNITY_MATRIX_V would
// split the field between the eyes. While no feed is active the global is kept at
// identity, which leaves the field in plain world space.
[ExecuteAlways]
[DisallowMultipleComponent]
public class RestFrameShaderFeed : MonoBehaviour
{
    static readonly int RestFrameAnchorId = Shader.PropertyToID("_RestFrameAnchor");
    static RestFrameShaderFeed activeFeed;

    public Vector3 rotationOffset = new Vector3(0f, 0f, 0f);
    public Vector3 positionOffset = new Vector3(0f, 0f, 0f);

    // Unset shader globals are ZERO matrices, which would collapse the noise field
    // to one uniform value. Make identity (= world space) the baseline as soon as
    // the player / editor loads, before any feed runs.
#if UNITY_EDITOR
    [UnityEditor.InitializeOnLoadMethod]
#endif
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    static void ResetToWorldSpace()
    {
        Shader.SetGlobalMatrix(RestFrameAnchorId, Matrix4x4.identity);
    }

    void OnEnable()
    {
        if (activeFeed != null && activeFeed != this)
            Debug.LogWarning($"Two active RestFrameShaderFeeds ('{activeFeed.name}', '{name}') are fighting over _RestFrameAnchor.", this);
        activeFeed = this;

        // beginContextRendering fires right before the cameras render, i.e. after
        // the XR before-render pose update - LateUpdate would lag a head-tracked
        // anchor by the late pose correction. It also fires for scene-view
        // rendering, so the anchor works in edit mode too.
        RenderPipelineManager.beginContextRendering += OnBeginContextRendering;
        PushAnchorMatrix();
    }

    void OnDisable()
    {
        RenderPipelineManager.beginContextRendering -= OnBeginContextRendering;
        if (activeFeed == this)
        {
            activeFeed = null;
            ResetToWorldSpace(); // back to the world-anchored field
        }
    }

    void OnBeginContextRendering(ScriptableRenderContext context, List<Camera> cameras)
    {
        PushAnchorMatrix();
    }

    void PushAnchorMatrix()
    {
        // Analytic inverse of the anchor's rigid pose: x_anchor = R^-1 * (x_world - t).
        // Scale is deliberately left out (unlike transform.worldToLocalMatrix) so a
        // scaled anchor/rig does not rescale the noise frequency.
        Matrix4x4 worldToAnchor =
            Matrix4x4.Rotate(Quaternion.Inverse(transform.rotation * Quaternion.Euler(rotationOffset.x, rotationOffset.y, rotationOffset.z))) *
            Matrix4x4.Translate(-transform.position + positionOffset);
        Shader.SetGlobalMatrix(RestFrameAnchorId, worldToAnchor);
    }
}
