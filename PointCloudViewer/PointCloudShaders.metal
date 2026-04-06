#include <metal_stdlib>
using namespace metal;

struct PointVertex {
    packed_float3 position;
    uint          flags;
};

struct Uniforms {
    float4x4 mvp;
    float4   baseColor;
    float4   selectedColor;
    float4   pointSizeVec;
};

struct VertexOut {
    float4 position  [[position]];
    float4 color;
    float  pointSize [[point_size]];
};

vertex VertexOut point_vertex(uint vid [[vertex_id]],
                              device const PointVertex* verts [[buffer(0)]],
                              constant Uniforms& uniforms [[buffer(1)]])
{
    PointVertex v = verts[vid];
    VertexOut out;

    out.position  = uniforms.mvp * float4(v.position.x, v.position.y, v.position.z, 1.0);
    out.pointSize = uniforms.pointSizeVec.x;

    bool selected = (v.flags & 1u) != 0u;
    out.color     = selected ? uniforms.selectedColor : uniforms.baseColor;

    return out;
}

fragment float4 point_fragment(VertexOut in [[stage_in]],
                               float2 point [[point_coord]])
{
    float dist = length(point - float2(0.5));
    if (dist > 0.5) discard_fragment();
    float alpha = 1.0 - smoothstep(0.35, 0.5, dist);
    return float4(in.color.rgb, in.color.a * alpha);
}
