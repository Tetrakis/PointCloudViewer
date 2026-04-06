import SwiftUI

@main
struct PointCloudViewerApp: App {
    @StateObject private var viewModel = PointCloudViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File…") {
                    viewModel.showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Selection") {
                Button("Clear Selection") {
                    viewModel.clearSelection()
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Button("Export Selected Rows…") {
                    viewModel.showExporter = true
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(viewModel.selectedIndices.isEmpty)
            }
        }
    }
}
