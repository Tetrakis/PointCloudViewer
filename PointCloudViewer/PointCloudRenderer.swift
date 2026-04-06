import Metal
import MetalKit
import simd

/// 16 bytes exactly (matches packed_float3 + uint)
struct PointVertex {
    var x: Float
    var y: Float
    var z: Float
    var flags: UInt32
}

final class PointCloudRenderer: NSObject, MTKViewDelegate {

    // MARK: – Metal objects
    private let device:        MTLDevice
    private let commandQueue:  MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer:  MTLBuffer?

    // Uniforms are written as 8x SIMD4<Float> = 128 bytes
    private var uniformBuffer: MTLBuffer?

    // MARK: – Data
    private var vertexCount: Int = 0

    // MARK: – Camera
    var camera = Camera3D()

    // MARK: – Appearance
    var pointAlpha:    Float        = 0.8
    var pointSize:     Float        = 3.0
    var selectedColor: SIMD4<Float> = SIMD4(1, 0, 0, 1)

    // MARK: – Init
    init?(mtkView: MTKView) {
        guard let dev   = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else { return nil }
        self.device       = dev
        self.commandQueue = queue

        mtkView.device    = dev
        mtkView.colorPixelFormat        = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)

        super.init()

        // 8 * 16 bytes = 128 bytes, matches Metal Uniforms exactly
        uniformBuffer = dev.makeBuffer(length: 8 * MemoryLayout<SIMD4<Float>>.stride,
                                       options: .storageModeShared)

        buildPipeline(view: mtkView)
    }

    // MARK: – Pipeline (uses compiled .metal file)
    private func buildPipeline(view: MTKView) {
        do {
            guard let lib = device.makeDefaultLibrary() else {
                print("🔴 Failed to load default Metal library")
                return
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction   = lib.makeFunction(name: "point_vertex")
            desc.fragmentFunction = lib.makeFunction(name: "point_fragment")

            let ca = desc.colorAttachments[0]!
            ca.pixelFormat                 = view.colorPixelFormat
            ca.isBlendingEnabled           = true
            ca.sourceRGBBlendFactor        = .sourceAlpha
            ca.destinationRGBBlendFactor   = .oneMinusSourceAlpha
            ca.sourceAlphaBlendFactor      = .one
            ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha

            desc.depthAttachmentPixelFormat = view.depthStencilPixelFormat

            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("🔴 Pipeline build failed: \(error)")
        }
    }

    // MARK: – Upload geometry
    func upload(points: [Point3D], selectedIndices: Set<Int>) {
        guard !points.isEmpty else {
            vertexCount = 0
            vertexBuffer = nil
            return
        }

        var verts: [PointVertex] = []
        verts.reserveCapacity(points.count)

        for p in points {
            let pos = p.position
            let flags: UInt32 = selectedIndices.contains(p.rowIndex) ? 1 : 0
            verts.append(PointVertex(x: pos.x, y: pos.y, z: pos.z, flags: flags))
        }

        vertexCount = verts.count
        vertexBuffer = device.makeBuffer(bytes: verts,
                                         length: MemoryLayout<PointVertex>.stride * verts.count,
                                         options: .storageModeShared)
    }

    // MARK: – MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard vertexCount > 0,
              let pipeline = pipelineState,
              let vBuf     = vertexBuffer,
              let uBuf     = uniformBuffer,
              let rpd      = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmdBuf   = commandQueue.makeCommandBuffer(),
              let enc      = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        let drawSize = view.drawableSize
        let aspect   = Float(drawSize.width / drawSize.height)

        // Build MVP
        let mvp = camera.mvpMatrix(aspect: aspect)

        // Write uniforms as 8 float4's (128 bytes) in the exact order Metal expects:
        // mvp columns (4), baseColor (1), selectedColor (1), pointSizeVec (1), (padding float4) (1)
        var u: [SIMD4<Float>] = Array(repeating: SIMD4<Float>(0,0,0,0), count: 8)
        u[0] = mvp.columns.0
        u[1] = mvp.columns.1
        u[2] = mvp.columns.2
        u[3] = mvp.columns.3
        u[4] = SIMD4<Float>(0, 0, 0, pointAlpha)   // baseColor
        u[5] = selectedColor                       // selectedColor
        u[6] = SIMD4<Float>(pointSize, 0, 0, 0)     // pointSizeVec
        u[7] = SIMD4<Float>(0, 0, 0, 0)             // unused, keeps 128B stable

        memcpy(uBuf.contents(), u, 8 * MemoryLayout<SIMD4<Float>>.stride)

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vBuf, offset: 0, index: 0)
        enc.setVertexBuffer(uBuf, offset: 0, index: 1)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
        enc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // Selection helpers (unchanged)
    func selectBox(rect: CGRect, viewSize: CGSize, points: [Point3D]) -> Set<Int> {
        guard !points.isEmpty else { return [] }
        let aspect = Float(viewSize.width / viewSize.height)
        let mvp    = camera.mvpMatrix(aspect: aspect)

        let minX = Float(min(rect.minX, rect.maxX) / viewSize.width)  * 2 - 1
        let maxX = Float(max(rect.minX, rect.maxX) / viewSize.width)  * 2 - 1
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
            if pointInPolygon(CGPoint(x: CGFloat(sx), y: CGFloat(sy)), polygon: polygon) {
                result.insert(p.rowIndex)
            }
        }
        return result
    }

    private func pointInPolygon(_ pt: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
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

