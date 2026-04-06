import SwiftUI

struct SelectionToolbar: View {
    @EnvironmentObject var vm: PointCloudViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Tool:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ToolButton(label: "Orbit / Pan",
                       systemImage: "hand.draw",
                       isActive: vm.activeTool == .none) {
                vm.activeTool = .none
            }
            ToolButton(label: "Box Select",
                       systemImage: "rectangle.dashed",
                       isActive: vm.activeTool == .box) {
                vm.activeTool = (vm.activeTool == .box) ? .none : .box
            }
            ToolButton(label: "Lasso Select",
                       systemImage: "lasso",
                       isActive: vm.activeTool == .lasso) {
                vm.activeTool = (vm.activeTool == .lasso) ? .none : .lasso
            }

            Divider().frame(height: 20)

            Button {
                vm.clearSelection()
            } label: {
                Label("Clear Selection", systemImage: "xmark.circle")
                    .font(.caption)
            }
            .disabled(vm.selectedIndices.isEmpty)

            Spacer()

            if !vm.selectedIndices.isEmpty {
                Text("\(vm.selectedIndices.count.formatted()) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct ToolButton: View {
    let label: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
