import SwiftUI
import MetalKit

// Custom MTKView subclass so we can intercept scroll events
final class InteractiveMTKView: MTKView {
    weak var coordinator: MetalPointCloudView.Coordinator?
    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleScroll(event)
    }
}

struct MetalPointCloudView: NSViewRepresentable {
    @EnvironmentObject var vm: PointCloudViewModel

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    func makeNSView(context: Context) -> InteractiveMTKView {
        let view = InteractiveMTKView()
        view.coordinator = context.coordinator
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        guard let renderer = PointCloudRenderer(mtkView: view) else { return view }
        context.coordinator.renderer = renderer
        view.delegate = renderer
        let pan = NSPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        return view
    }

    func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        let pts = vm.data?.points ?? []
        renderer.pointAlpha    = vm.pointAlpha
        renderer.pointSize     = vm.pointSize
        renderer.selectedColor = vm.selectedColorSIMD
        if context.coordinator.lastPointCount != pts.count ||
           context.coordinator.lastSelection  != vm.selectedIndices {
            renderer.upload(points: pts, selectedIndices: vm.selectedIndices)
            context.coordinator.lastPointCount = pts.count
            context.coordinator.lastSelection  = vm.selectedIndices
        }
        context.coordinator.activeTool = vm.activeTool
    }

    final class Coordinator: NSObject {
        weak var vm: PointCloudViewModel?
        var renderer: PointCloudRenderer?
        var activeTool: SelectionTool = .none
        private var dragStart: CGPoint = .zero
        private var lassoPoints: [CGPoint] = []
        private var overlayLayer: CAShapeLayer?
        var lastPointCount: Int = -1
        var lastSelection: Set<Int> = []

        init(vm: PointCloudViewModel) { self.vm = vm }

        func handleScroll(_ event: NSEvent) {
            renderer?.camera.zoom(delta: Float(event.scrollingDeltaY) * 0.05)
        }

        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard let view = g.view, let vm = vm, let renderer = renderer else { return }
            let loc = flipY(g.location(in: view), in: view)
            switch g.state {
            case .began:
                dragStart = loc
                lassoPoints = [loc]
                if activeTool != .none { addOverlay(to: view) }
            case .changed:
                let d = g.translation(in: view)
                g.setTranslation(.zero, in: view)
                if activeTool == .none {
                    if #available(macOS 26.0, *), g.modifierFlags.contains(.shift) {                        renderer.camera.pan(dx: Float(d.x), dy: Float(d.y))
                    } else {
                        renderer.camera.orbit(dx: Float(d.x), dy: Float(-d.y))
                    }
                } else if activeTool == .box {
                    updateBoxOverlay(start: dragStart, current: loc, in: view)
                } else {
                    lassoPoints.append(loc)
                    updateLassoOverlay(points: lassoPoints, in: view)
                }
            case .ended:
                removeOverlay(from: view)
                guard activeTool != .none else { return }
                let vsz = view.frame.size
                let localDragStart = dragStart
                let localLasso = lassoPoints
                let localTool = activeTool
                Task { @MainActor [weak self] in
                    guard let self, let pts = vm.data?.points else { return }
                    let selected: Set<Int>
                    if localTool == .box {
                        let rect = CGRect(x: min(localDragStart.x, loc.x),
                                         y: min(localDragStart.y, loc.y),
                                         width:  abs(loc.x - localDragStart.x),
                                         height: abs(loc.y - localDragStart.y))
                        selected = renderer.selectBox(rect: rect, viewSize: vsz, points: pts) 
                    } else {
                        selected = renderer.selectLasso(polygon: localLasso, viewSize: vsz, points: pts)
                    }
                    vm.addToSelection(selected)
                }
            default:
                removeOverlay(from: view)
            }
        }

        private func flipY(_ p: CGPoint, in view: NSView) -> CGPoint {
            CGPoint(x: p.x, y: view.frame.height - p.y)
        }
        private func addOverlay(to view: NSView) {
            view.wantsLayer = true
            let l = CAShapeLayer()
            l.strokeColor = NSColor.systemYellow.cgColor
            l.fillColor   = NSColor.systemYellow.withAlphaComponent(0.12).cgColor
            l.lineWidth   = 1.5
            l.lineDashPattern = [6, 3]
            view.layer?.addSublayer(l)
            overlayLayer = l
        }
        private func removeOverlay(from view: NSView) {
            overlayLayer?.removeFromSuperlayer()
            overlayLayer = nil
        }
        private func updateBoxOverlay(start: CGPoint, current: CGPoint, in view: NSView) {
            guard let l = overlayLayer else { return }
            let h = view.frame.height
            let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                           width: abs(current.x - start.x), height: abs(current.y - start.y))
            let flipped = CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
            l.path = CGPath(rect: flipped, transform: nil)
        }
        private func updateLassoOverlay(points: [CGPoint], in view: NSView) {
            guard let l = overlayLayer, !points.isEmpty else { return }
            let h = view.frame.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: points[0].x, y: h - points[0].y))
            for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: h - p.y)) }
            path.closeSubpath()
            l.path = path
        }
    }
}
