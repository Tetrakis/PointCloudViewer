#include <metal_stdlib>
using namespace metal;

// ── Shared types (must match Swift side) ─────────────────────────────────────

struct PointVertex {
    float3 position;
    uint   flags;      // bit 0 = selected
};

struct Uniforms {
    float4x4 mvp;
    float4   baseColor;      // (r,g,b,a)  a = alpha
    float4   selectedColor;  // (r,g,b,1)
    float    pointSize;
};

// ── Vertex shader ─────────────────────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float  pointSize [[point_size]];
};

vertex VertexOut point_vertex(uint            vid       [[vertex_id]],
                               device const PointVertex* verts     [[buffer(0)]],
                               constant       Uniforms&  uniforms  [[buffer(1)]])
{
    PointVertex v = verts[vid];
    VertexOut   out;

    out.position  = uniforms.mvp * float4(v.position, 1.0);
    out.pointSize = uniforms.pointSize;

    bool selected = (v.flags & 1u) != 0u;
    out.color     = selected ? uniforms.selectedColor : uniforms.baseColor;

    return out;
}

// ── Fragment shader ───────────────────────────────────────────────────────────

fragment float4 point_fragment(VertexOut        in    [[stage_in]],
                                float2          point [[point_coord]])
{
    // Round point sprites
    float dist = length(point - float2(0.5));
    if (dist > 0.5) discard_fragment();

    // Soft edge for anti-aliasing
    float alpha = 1.0 - smoothstep(0.35, 0.5, dist);
    return float4(in.color.rgb, in.color.a * alpha);
}
