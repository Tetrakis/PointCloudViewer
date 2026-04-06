import Foundation
import simd

/// Arcball / orbit camera for 3D point cloud navigation.
struct Camera3D {
    var distance: Float      = 5.0
    var azimuth:  Float      = 0.3   // radians
    var elevation: Float     = 0.4   // radians
    var target:   SIMD3<Float> = .zero
    var fovY:     Float      = 60.0  // degrees

    // Orbit by dragging
    mutating func orbit(dx: Float, dy: Float) {
        azimuth   -= dx * 0.005
        elevation = clamp(elevation + dy * 0.005, -(.pi / 2 - 0.01), .pi / 2 - 0.01)
    }

    // Pan (shift+drag)
    mutating func pan(dx: Float, dy: Float) {
        let right = normalize(cross(SIMD3<Float>(0,1,0), eye - target))
        let up    = normalize(cross(eye - target, right))
        let scale: Float = distance * 0.001
        target -= right * dx * scale
        target += up    * dy * scale
    }

    // Zoom (scroll)
    mutating func zoom(delta: Float) {
        distance = max(0.1, distance * (1 - delta * 0.1))
    }

    var eye: SIMD3<Float> {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        return target + SIMD3(x, y, z)
    }

    func viewMatrix() -> float4x4 {
        let e = eye
        let f = normalize(target - e)          // forward
        let r = normalize(cross(f, SIMD3<Float>(0,1,0))) // right
        let u = cross(r, f)                    // up

        return float4x4(columns: (
            SIMD4( r.x,  u.x, -f.x, 0),
            SIMD4( r.y,  u.y, -f.y, 0),
            SIMD4( r.z,  u.z, -f.z, 0),
            SIMD4(-dot(r,e), -dot(u,e), dot(f,e), 1)
        ))
    }

    func projectionMatrix(aspect: Float) -> float4x4 {
        let fovR = fovY * .pi / 180
        let ys = 1 / tan(fovR * 0.5)
        let xs = ys / aspect
        let near: Float = 0.01
        let far:  Float = 10_000
        let zs = far / (near - far)
        return float4x4(columns: (
            SIMD4(xs,  0,  0,  0),
            SIMD4( 0, ys,  0,  0),
            SIMD4( 0,  0, zs, -1),
            SIMD4( 0,  0, zs*near, 0)
        ))
    }

    func mvpMatrix(aspect: Float) -> float4x4 {
        projectionMatrix(aspect: aspect) * viewMatrix()
    }

    /// Auto-frame the camera to contain the given point cloud
    mutating func frame(points: [Point3D]) {
        guard !points.isEmpty else { return }
        var mn = SIMD3<Float>(repeating:  Float.greatestFiniteMagnitude)
        var mx = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for p in points {
            mn = min(mn, p.position)
            mx = max(mx, p.position)
        }
        target   = (mn + mx) * 0.5
        let diag = length(mx - mn)
        distance = max(diag * 0.8, 0.1)
    }
}

private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}
