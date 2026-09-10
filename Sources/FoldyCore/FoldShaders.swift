import Foundation

/// The Metal shaders, compiled at first use.
///
/// They live in a string rather than a `.metal` file so `swift build` and a hand-made
/// app bundle need no resource bundle and no Metal build step. The compile takes a
/// few dozen milliseconds, once per process.
enum FoldShaders {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    // MARK: - Fold pass

    struct FoldUniforms {
        float progress;
        float perspective;
        float blur;
        float shadow;
        float bend;
        float frost;
        float aspect;
        float cornerRadius;
        float cameraDistance;
        float maxTilt;
        float pad0;
        float pad1;
    };

    struct FoldVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    // Where the sheet is at normalized height h above the hinge (0 hinge, 1 top).
    // The sheet is a curve in the (y, z) plane. Its local tilt is theta scaled by a
    // profile that is 1 everywhere for a rigid tilt and ramps up from the hinge for a
    // bend, so the base stays put and the upper part curls back. Integrated numerically.
    static float2 sheetProfile(float h, float theta, float bend) {
        const int steps = 24;
        float2 p = float2(0.0);
        float step = h / float(steps);
        for (int i = 0; i < steps; i++) {
            float s = (float(i) + 0.5) * step;
            float profile = mix(1.0, smoothstep(0.0, 0.8, s), bend);
            float phi = theta * profile;
            p += float2(cos(phi), -sin(phi)) * step;
        }
        return p;
    }

    vertex FoldVertexOut fold_vertex(uint vid [[vertex_id]],
                                     const device float2 *vertices [[buffer(0)]],
                                     constant FoldUniforms &u [[buffer(1)]]) {
        float2 uv = vertices[vid];            // x 0…1 left→right, y 0…1 top→bottom
        float h = 1.0 - uv.y;                 // height above the hinge
        float theta = u.progress * u.perspective * u.maxTilt;
        float2 yz = sheetProfile(h, theta, u.bend);
        float x = (uv.x - 0.5) * u.aspect;
        float y = -0.5 + yz.x;
        float z = yz.y;                       // ≤ 0: away from the viewer
        float d = u.cameraDistance;
        float w = d - z;                      // perspective divide; keeps uv perspective-correct
        FoldVertexOut out;
        out.position = float4(x / (u.aspect * 0.5) * d, y / 0.5 * d, 0.5 * w, w);
        out.uv = uv;
        return out;
    }

    static float roundedBox(float2 p, float2 halfSize, float radiusTop, float radiusBottom) {
        float r = p.y > 0.0 ? radiusTop : radiusBottom;
        float2 q = abs(p) - halfSize + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    fragment float4 fold_fragment(FoldVertexOut in [[stage_in]],
                                  texture2d<float> source [[texture(0)]],
                                  constant FoldUniforms &u [[buffer(1)]]) {
        constexpr sampler smp(address::clamp_to_edge, filter::linear, mip_filter::linear);
        float2 uv = in.uv;
        float p = u.progress;
        float topness = 1.0 - uv.y;
        float band = smoothstep(0.0, 0.85, topness);

        // Variable blur: the mip level climbs toward the top edge. Five taps in a
        // small rotated cross at that level hide the mip steps.
        float lod = p * band * (u.blur * 6.0 + u.frost * 1.5);
        float2 texel = 1.0 / float2(source.get_width(), source.get_height());
        float radius = exp2(lod) * 0.7;
        float3 color = source.sample(smp, uv, level(lod)).rgb * 0.36;
        color += source.sample(smp, uv + float2( 0.9,  0.4) * radius * texel, level(lod)).rgb * 0.16;
        color += source.sample(smp, uv + float2(-0.9, -0.4) * radius * texel, level(lod)).rgb * 0.16;
        color += source.sample(smp, uv + float2(-0.4,  0.9) * radius * texel, level(lod)).rgb * 0.16;
        color += source.sample(smp, uv + float2( 0.4, -0.9) * radius * texel, level(lod)).rgb * 0.16;

        // Frost: a milky haze where the blur is.
        color = mix(color, float3(0.93, 0.95, 0.98), p * u.frost * band * 0.6);

        // Shade: a top gradient and two dark top corners, the same shape as the CSS demo.
        float2 ellipse = float2(1.2, 0.6);
        float cornerL = 1.0 - smoothstep(0.0, 0.6, length(uv / ellipse));
        float cornerR = 1.0 - smoothstep(0.0, 0.6, length((uv - float2(1.0, 0.0)) / ellipse));
        float top = 1.0 - smoothstep(0.0, 0.45, uv.y);
        float shade = clamp(0.55 * (cornerL + cornerR) + 0.35 * top, 0.0, 1.0);
        shade *= p * 0.9 * (u.shadow * 1.8);
        color *= 1.0 - clamp(shade, 0.0, 0.95);

        // Feather the top edge with the bend, tapering to nothing at the base.
        float featherBand = p * 0.22;
        float alpha = smoothstep(0.0, max(featherBand, 0.0005), uv.y);

        // Rounded top corners and a soft silhouette.
        float2 sp = float2((uv.x - 0.5) * u.aspect, 0.5 - uv.y);
        float sd = roundedBox(sp, float2(u.aspect * 0.5, 0.5), u.cornerRadius, 0.0);
        float edge = fwidth(sd) + p * 0.006;
        alpha *= 1.0 - smoothstep(-edge, 0.0, sd);

        return float4(color * alpha, alpha);
    }

    // MARK: - MacBook scene pass (settings preview)

    struct SceneUniforms {
        float4x4 mvp;
        float4x4 model;
        float4 color;
        float4 params;    // x kind (0 base, 1 lid front, 2 shadow, 3 lid back), y width, z corner radius, w height
        float4 params2;   // lid: x side inset, y bottom inset, z top inset, w notch width
        float4 eye;
    };

    struct SceneVertexOut {
        float4 position [[position]];
        float2 uv;
        float3 world;
        float3 normal;
    };

    vertex SceneVertexOut scene_vertex(uint vid [[vertex_id]],
                                       const device float2 *vertices [[buffer(0)]],
                                       constant SceneUniforms &u [[buffer(1)]]) {
        float2 uv = vertices[vid];
        float4 local = float4((uv.x - 0.5) * u.params.y, (1.0 - uv.y) * u.params.w, 0.0, 1.0); // params.y width, params.w height
        SceneVertexOut out;
        out.position = u.mvp * local;
        out.world = (u.model * local).xyz;
        out.normal = normalize((u.model * float4(0.0, 0.0, 1.0, 0.0)).xyz);
        out.uv = uv;
        return out;
    }

    fragment float4 scene_fragment(SceneVertexOut in [[stage_in]],
                                   texture2d<float> screen [[texture(0)]],
                                   constant SceneUniforms &u [[buffer(1)]]) {
        constexpr sampler smp(address::clamp_to_edge, filter::linear);
        int kind = int(u.params.x);
        float width = u.params.y;
        float height = u.params.w;
        float radius = u.params.z;

        // Local rectangle, centred, y up.
        float2 p = float2((in.uv.x - 0.5) * width, (0.5 - in.uv.y) * height);
        float2 halfSize = float2(width * 0.5, height * 0.5);

        if (kind == 2) {
            float d = length(p / halfSize);
            float a = (1.0 - smoothstep(0.35, 1.0, d)) * u.color.a;
            return float4(0.0, 0.0, 0.0, a);
        }

        float sd = roundedBox(p, halfSize, radius, radius);
        float aa = fwidth(sd);
        float alpha = 1.0 - smoothstep(-aa, aa, sd);
        if (alpha <= 0.001) discard_fragment();

        float3 lightDir = normalize(float3(0.25, 1.0, 0.7));
        float3 color = u.color.rgb;

        if (kind == 1) {
            float3 viewDir = normalize(u.eye.xyz - in.world);
            bool front = dot(in.normal, viewDir) > 0.0;
            if (front) {
                float side = u.params2.x, bottom = u.params2.y, top = u.params2.z;
                float2 suv = float2((in.uv.x - side) / (1.0 - 2.0 * side),
                                    (in.uv.y - top) / (1.0 - top - bottom));
                bool inScreen = suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0;
                // The notch hangs from the top edge of the glass into the panel.
                float notchW = u.params2.w;
                float notchH = 0.06;
                float2 np = float2((in.uv.x - 0.5) * width, in.uv.y * height);
                float notch = roundedBox(np - float2(0.0, notchH * 0.5 + 0.005), float2(notchW * 0.5, notchH * 0.5 + 0.03), 0.014, 0.014);
                bool inNotch = notch < 0.0 && in.uv.y * height < notchH + 0.005;
                color = (inScreen && !inNotch) ? screen.sample(smp, suv).rgb : float3(0.07, 0.07, 0.075);
                // A faint glass sheen across the panel.
                float sheen = 0.04 * (1.0 - smoothstep(0.0, 0.7, in.uv.y)) * (1.0 - smoothstep(0.2, 0.9, in.uv.x));
                color += sheen;
            } else {
                float3 n = -in.normal;
                color = u.color.rgb * (0.78 + 0.22 * max(dot(n, lightDir), 0.0));
            }
        } else if (kind == 3) {
            float3 n = in.normal;
            color = u.color.rgb * (0.78 + 0.22 * max(dot(n, lightDir), 0.0));
        } else {
            // Base deck: a slight front-to-back gradient and the lip at the front centre.
            float grade = 0.9 + 0.1 * in.uv.y;
            color = u.color.rgb * grade;
            float2 lp = float2((in.uv.x - 0.5) * width, in.uv.y * height);
            float lip = roundedBox(lp, float2(0.17, 0.02), 0.018, 0.0);
            if (lip < 0.0) color *= 0.62;
        }

        return float4(color * alpha, alpha);
    }
    """#
}
