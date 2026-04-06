import Foundation
import simd

/// One row from the imported file
struct PointRow: Identifiable {
    let id: Int           // row index (0-based)
    let rawValues: [String]
}

/// A parsed 3D point referencing back to its source row
struct Point3D {
    let rowIndex: Int
    var position: SIMD3<Float>
}

/// The loaded dataset
struct PointCloudData {
    let headers: [String]       // column names (or "Col 0", "Col 1" …)
    let rows: [PointRow]
    var points: [Point3D] = []  // filled once X/Y/Z columns are chosen

    var columnCount: Int { headers.count }
    var rowCount:    Int { rows.count }
}
