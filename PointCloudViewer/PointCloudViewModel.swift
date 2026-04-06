import SwiftUI
import Combine

enum SelectionTool {
    case box, lasso, none
}

@MainActor
final class PointCloudViewModel: ObservableObject {

    // MARK: – Data
    @Published var data: PointCloudData?
    @Published var isLoading = false
    @Published var loadError: String?

    // MARK: – Column mapping
    @Published var xColumn: Int = 0
    @Published var yColumn: Int = 1
    @Published var zColumn: Int = 2
    @Published var columnsAssigned = false

    // MARK: – Render settings
    @Published var pointAlpha: Float = 0.8
    @Published var pointSize:  Float = 3.0
    @Published var selectedColor: Color = .red

    // MARK: – Selection
    @Published var selectedIndices: Set<Int> = []
    @Published var activeTool: SelectionTool = .none

    // MARK: – UI flags
    @Published var showFileImporter  = false
    @Published var showExporter      = false

    // MARK: – File import
    func importFile(url: URL) {
        isLoading = true
        loadError = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try CSVImporter.load(url: url)
                await MainActor.run {
                    self?.data = result
                    self?.xColumn = 0
                    self?.yColumn = min(1, result.columnCount - 1)
                    self?.zColumn = min(2, result.columnCount - 1)
                    self?.columnsAssigned = false
                    self?.selectedIndices = []
                    self?.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self?.loadError = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }

    // MARK: – Build point array from chosen columns
    func applyColumnMapping() {
        guard var d = data else { return }
        var pts = [Point3D]()
        pts.reserveCapacity(d.rows.count)
        for row in d.rows {
            let vals = row.rawValues
            let x = Float(vals.indices.contains(xColumn) ? vals[xColumn] : "0") ?? 0
            let y = Float(vals.indices.contains(yColumn) ? vals[yColumn] : "0") ?? 0
            let z = Float(vals.indices.contains(zColumn) ? vals[zColumn] : "0") ?? 0
            pts.append(Point3D(rowIndex: row.id, position: SIMD3(x, y, z)))
        }
        d.points = pts
        data = d
        columnsAssigned = true
        selectedIndices = []
    }

    // MARK: – Selection helpers
    func clearSelection() { selectedIndices = [] }

    func addToSelection(_ indices: Set<Int>) {
        selectedIndices.formUnion(indices)
    }

    // MARK: – Derived
    var selectedColorSIMD: SIMD4<Float> {
        let ns = NSColor(selectedColor).usingColorSpace(.deviceRGB) ?? .red
        return SIMD4(Float(ns.redComponent),
                     Float(ns.greenComponent),
                     Float(ns.blueComponent),
                     1.0)
    }
}
