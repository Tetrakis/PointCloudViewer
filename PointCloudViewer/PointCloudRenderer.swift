import Metal
import MetalKit
import simd

// Must mirror PointCloudShaders.metal
struct PointVertex {
    var position: SIMD3<Float>
    var flags:    UInt32   // bit 0 = selected
}

struct Uniforms {
    var mvp:           float4x4
    var baseColor:     SIMD4<Float>
    var selectedColor: SIMD4<Float>
    var pointSize:     Float
}

final class PointCloudRenderer: NSObject, MTKViewDelegate {

    // MARK: – Metal objects
    private let device:        MTLDevice
    private let commandQueue:  MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer:  MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    // MARK: – Data
    private var vertexCount: Int = 0

    // MARK: – Camera
    var camera = Camera3D()

    // MARK: – Appearance (set from ViewModel)
    var pointAlpha:     Float        = 0.8
    var pointSize:      Float        = 3.0
    var selectedColor:  SIMD4<Float> = SIMD4(1, 0, 0, 1)

    // MARK: – Callback when a box/lasso selection is committed
    var onSelectionCommitted: ((Set<Int>) -> Void)?

    // MARK: – Init
    init?(mtkView: MTKView) {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else { return nil }
        self.device       = dev
        self.commandQueue = queue
        mtkView.device    = dev
        mtkView.colorPixelFormat        = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        super.init()
        buildPipeline(view: mtkView)
    }
    // MARK: - Compile Shaders at Runtime
    private var metalShaderSource: String { """
    #include <metal_stdlib>
    using namespace metal;

    struct PointVertex { float3 position; uint flags; };
    struct Uniforms { float4x4 mvp; float4 baseColor; float4 selectedColor; float pointSize; };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
        float  pointSize [[point_size]];
    };

    vertex VertexOut point_vertex(uint vid [[vertex_id]],
                                   device const PointVertex* verts [[buffer(0)]],
                                   constant Uniforms& uniforms [[buffer(1)]]) {
        PointVertex v = verts[vid];
        VertexOut out;
        out.position  = uniforms.mvp * float4(v.position, 1.0);
        out.pointSize = uniforms.pointSize;
        bool selected = (v.flags & 1u) != 0u;
        out.color     = selected ? uniforms.selectedColor : uniforms.baseColor;
        return out;
    }

    fragment float4 point_fragment(VertexOut in [[stage_in]],
                                    float2 point [[point_coord]]) {
        float dist = length(point - float2(0.5));
        if (dist > 0.5) discard_fragment();
        float alpha = 1.0 - smoothstep(0.35, 0.5, dist);
        return float4(in.color.rgb, in.color.a * alpha);
    }
    """ }
    
    // MARK: – Pipeline
    private func buildPipeline(view: MTKView) {
        guard let lib = try? device.makeLibrary(source: metalShaderSource, options: nil) else {
            print("⚠️  Failed to compile Metal shaders.")
            return
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction                  = lib.makeFunction(name: "point_vertex")
        desc.fragmentFunction                = lib.makeFunction(name: "point_fragment")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.colorAttachments[0].isBlendingEnabled             = true
        desc.colorAttachments[0].sourceRGBBlendFactor          = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor     = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor        = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor   = .oneMinusSourceAlpha
        desc.depthAttachmentPixelFormat                        = view.depthStencilPixelFormat
        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: – Upload geometry
    func upload(points: [Point3D], selectedIndices: Set<Int>) {
        var verts = points.map { p in
            PointVertex(position: p.position,
                        flags:    selectedIndices.contains(p.rowIndex) ? 1 : 0)
        }
        vertexCount  = verts.count
        vertexBuffer = device.makeBuffer(bytes: &verts,
                                         length: MemoryLayout<PointVertex>.stride * max(1, verts.count),
                                         options: .storageModeShared)
    }

    // MARK: – MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard vertexCount > 0,
              let pipeline = pipelineState,
              let vBuf     = vertexBuffer,
              let rpd      = view.currentRenderPassDescriptor,
              let drawable  = view.currentDrawable,
              let cmdBuf    = commandQueue.makeCommandBuffer(),
              let enc        = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        let size   = view.drawableSize
        let aspect = Float(size.width / size.height)

        let mvp = camera.mvpMatrix(aspect: aspect)
        let baseColor = SIMD4<Float>(0, 0, 0, pointAlpha)
        
        var uniforms = Uniforms(
            mvp:           camera.mvpMatrix(aspect: aspect),
            baseColor:     SIMD4(0, 0, 0, pointAlpha),
            selectedColor: selectedColor,
            pointSize:     pointSize
        )

        if uniformBuffer == nil || uniformBuffer!.length < MemoryLayout<Uniforms>.size {
            uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size,
                                              options: .storageModeShared)
        }
        memcpy(uniformBuffer!.contents(), &uniforms, MemoryLayout<Uniforms>.size)

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vBuf,          offset: 0, index: 0)
        enc.setVertexBuffer(uniformBuffer!, offset: 0, index: 1)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
        enc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: – Box selection (screen-space NDC rect → rowIndices)
    func selectBox(rect: CGRect, viewSize: CGSize, points: [Point3D]) -> Set<Int> {
        guard !points.isEmpty else { return [] }
        let aspect = Float(viewSize.width / viewSize.height)
        let mvp    = camera.mvpMatrix(aspect: aspect)

        let minX = Float(min(rect.minX, rect.maxX) / viewSize.width)  * 2 - 1
        let maxX = Float(max(rect.minX, rect.maxX) / viewSize.width)  * 2 - 1
        // Flip Y: screen Y grows down, NDC Y grows up
        let minY = 1 - Float(max(rect.minY, rect.maxY) / viewSize.height) * 2
        let maxY = 1 - Float(min(rect.minY, rect.maxY) / viewSize.height) * 2

        var result = Set<Int>()
        for p in points {
            let clip = mvp * SIMD4(p.position, 1)
            guard clip.w != 0 else { continue }
            let ndx = clip.x / clip.w
            let ndy = clip.y / clip.w
            if ndx >= minX && ndx <= maxX && ndy >= minY && ndy <= maxY {
                result.insert(p.rowIndex)
            }
        }
        return result
    }

    // MARK: – Lasso selection (screen-space polygon → rowIndices)
    func selectLasso(polygon: [CGPoint], viewSize: CGSize, points: [Point3D]) -> Set<Int> {
        guard polygon.count >= 3, !points.isEmpty else { return [] }
        let aspect = Float(viewSize.width / viewSize.height)
        let mvp    = camera.mvpMatrix(aspect: aspect)
        var result = Set<Int>()
        for p in points {
            let clip = mvp * SIMD4(p.position, 1)
            guard clip.w != 0 else { continue }
            let ndcX = clip.x / clip.w
            let ndcY = clip.y / clip.w
            let sx = ((ndcX + 1) / 2) * Float(viewSize.width)
            let sy = ((1 - ndcY) / 2) * Float(viewSize.height)
            if pointInPolygon(CGPoint(x: CGFloat(sx), y: CGFloat(sy)), polygon: polygon) {                result.insert(p.rowIndex)
            }
        }
        return result
    }

    // Ray-casting point-in-polygon
    private func pointInPolygon(_ pt: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0 ..< polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if ((pi.y > pt.y) != (pj.y > pt.y)) &&
               (pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside = !inside
            }
            j = i
        }
        return inside
    }
}
