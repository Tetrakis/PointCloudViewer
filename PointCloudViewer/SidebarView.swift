import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var vm: PointCloudViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── File info ──────────────────────────────────────────────
                if let d = vm.data {
                    GroupBox("Dataset") {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledValue("Rows",    "\(d.rowCount.formatted())")
                            LabeledValue("Columns", "\(d.columnCount)")
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ── Column mapping ─────────────────────────────────────────
                if let d = vm.data, !vm.columnsAssigned {
                    GroupBox("Map Columns to Axes") {
                        VStack(spacing: 10) {
                            AxisPicker(label: "X axis", columns: d.headers, selection: $vm.xColumn)
                            AxisPicker(label: "Y axis", columns: d.headers, selection: $vm.yColumn)
                            AxisPicker(label: "Z axis", columns: d.headers, selection: $vm.zColumn)

                            Button("Apply & Render") {
                                vm.applyColumnMapping()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                } else if let d = vm.data, vm.columnsAssigned {
                    GroupBox("Axes") {
                        VStack(spacing: 10) {
                            AxisPicker(label: "X axis", columns: d.headers, selection: $vm.xColumn)
                            AxisPicker(label: "Y axis", columns: d.headers, selection: $vm.yColumn)
                            AxisPicker(label: "Z axis", columns: d.headers, selection: $vm.zColumn)

                            Button("Re-apply") {
                                vm.applyColumnMapping()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ── Appearance ─────────────────────────────────────────────
                if vm.columnsAssigned {
                    GroupBox("Appearance") {
                        VStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Point Alpha: \(String(format: "%.2f", vm.pointAlpha))")
                                    .font(.caption)
                                Slider(value: $vm.pointAlpha, in: 0.01...1.0)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Point Size: \(String(format: "%.1f", vm.pointSize))")
                                    .font(.caption)
                                Slider(value: $vm.pointSize, in: 1.0...12.0)
                            }
                            HStack {
                                Text("Selection Color").font(.caption)
                                Spacer()
                                ColorPicker("", selection: $vm.selectedColor, supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // ── Selection ──────────────────────────────────────────
                    GroupBox("Selection") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledValue("Selected", "\(vm.selectedIndices.count.formatted()) points")

                            HStack {
                                Button("Clear") {
                                    vm.clearSelection()
                                }
                                .disabled(vm.selectedIndices.isEmpty)

                                Spacer()

                                Button("Export…") {
                                    vm.showExporter = true
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(vm.selectedIndices.isEmpty)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
    }
}

// MARK: – Sub-views

private struct AxisPicker: View {
    let label: String
    let columns: [String]
    @Binding var selection: Int

    var body: some View {
        HStack {
            Text(label).font(.caption).frame(width: 44, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(columns.indices, id: \.self) { i in
                    Text(columns[i]).tag(i)
                }
            }
            .labelsHidden()
        }
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label; self.value = value
    }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.caption)
    }
}
