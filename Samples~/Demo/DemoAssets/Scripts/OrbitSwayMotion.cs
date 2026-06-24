using UnityEngine;

// Animates the GameObject around a circular orbit while it weaves side-to-side
// across the path, keeping it pointed along its real direction of travel the
// whole time - the sway included. Attach it to any object: the object's pose at
// play start marks a point ON the orbit (angle 0), so it begins exactly where
// you placed it instead of snapping to a far-off center.
[DisallowMultipleComponent]
public class OrbitSwayMotion : MonoBehaviour
{
    [Header("Orbit")]
    [Min(0f)]
    [Tooltip("Radius of the circle, in world units (meters).")]
    public float radius = 2f;

    [Tooltip("Travel speed around the circle, in degrees per second. " +
             "Negative reverses the direction.")]
    public float orbitSpeed = 45f;

    [Tooltip("Normal of the plane the circle lies in. World up (0,1,0) gives a " +
             "flat horizontal orbit; tilt this to tilt the orbit.")]
    public Vector3 orbitAxis = Vector3.up;

    [Header("Side-to-side sway")]
    [Min(0f)]
    [Tooltip("How far it weaves toward and away from the orbit center, in world " +
             "units. Set to 0 for a clean circle.")]
    public float swayAmplitude = 0.5f;

    [Min(0f)]
    [Tooltip("Full left-right sway cycles per second.")]
    public float swayFrequency = 1f;

    // Orthonormal frame of the orbit plane: u and v span it, n is the normal.
    // Angle 0 points along +u, which is where the object starts.
    Vector3 center, u, v, n;
    float elapsed;

    void Start()
    {
        n = orbitAxis.sqrMagnitude > 1e-6f ? orbitAxis.normalized : Vector3.up;

        // u = any in-plane direction. Cross n with a reference axis that is not
        // parallel to it (swap the reference when n itself is near-vertical).
        Vector3 reference = Mathf.Abs(Vector3.Dot(n, Vector3.up)) > 0.99f
            ? Vector3.forward
            : Vector3.up;
        u = Vector3.Normalize(Vector3.Cross(reference, n));
        v = Vector3.Cross(n, u); // unit length already: n is perpendicular to u and both are unit

        // Place the center one radius back along u so that at angle 0 the rim
        // sits exactly on the start position - no jump when play begins.
        center = transform.position - radius * u;
    }

    void Update()
    {
        elapsed += Time.deltaTime;

        float omegaOrbit = orbitSpeed * Mathf.Deg2Rad;    // rad / s around circle
        float omegaSway = swayFrequency * 2f * Mathf.PI;  // rad / s of the weave
        float theta = omegaOrbit * elapsed;
        float swayPhase = omegaSway * elapsed;

        // In-plane radial (in/out) and tangential (along-path) unit directions.
        Vector3 radial = Mathf.Cos(theta) * u + Mathf.Sin(theta) * v;
        Vector3 tangent = -Mathf.Sin(theta) * u + Mathf.Cos(theta) * v;

        // The sway rides on the radius. Because radial is perpendicular to tangent
        // inside the plane, moving in and out IS moving left/right of the heading.
        float r = radius + swayAmplitude * Mathf.Sin(swayPhase);
        transform.position = center + r * radial;

        // Exact time-derivative of the line above, so the facing follows the true
        // direction of travel - sway and all:
        //   d/dt[ r * radial ] = r' * radial + r * omegaOrbit * tangent
        Vector3 velocity =
            swayAmplitude * omegaSway * Mathf.Cos(swayPhase) * radial +
            r * omegaOrbit * tangent;

        if (velocity.sqrMagnitude > 1e-8f)
            transform.rotation = Quaternion.LookRotation(velocity, n);
    }

    // Draws the orbit (and the inner / outer sway extents) when the object is
    // selected, so the radius can be dialed in visually before pressing play.
    void OnDrawGizmosSelected()
    {
        Vector3 axis = orbitAxis.sqrMagnitude > 1e-6f ? orbitAxis.normalized : Vector3.up;
        Vector3 reference = Mathf.Abs(Vector3.Dot(axis, Vector3.up)) > 0.99f
            ? Vector3.forward
            : Vector3.up;
        Vector3 gu = Vector3.Normalize(Vector3.Cross(reference, axis));
        Vector3 gv = Vector3.Cross(axis, gu);

        // Live position is the rim in edit mode; the captured center once playing.
        Vector3 c = Application.isPlaying ? center : transform.position - radius * gu;

        Gizmos.color = Color.cyan;
        DrawRing(c, gu, gv, radius);
        if (swayAmplitude > 0f)
        {
            Gizmos.color = new Color(0f, 1f, 1f, 0.35f);
            DrawRing(c, gu, gv, radius + swayAmplitude);
            DrawRing(c, gu, gv, Mathf.Max(0f, radius - swayAmplitude));
        }
    }

    static void DrawRing(Vector3 c, Vector3 a, Vector3 b, float rad)
    {
        const int seg = 64;
        Vector3 prev = c + rad * a;
        for (int i = 1; i <= seg; i++)
        {
            float t = (i / (float)seg) * 2f * Mathf.PI;
            Vector3 p = c + rad * (Mathf.Cos(t) * a + Mathf.Sin(t) * b);
            Gizmos.DrawLine(prev, p);
            prev = p;
        }
    }
}
