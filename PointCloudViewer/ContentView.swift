import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var vm: PointCloudViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ZStack {
                if vm.isLoading {
                    ProgressView("Loading…")
                } else if vm.columnsAssigned, let pts = vm.data?.points, !pts.isEmpty {
                    VStack(spacing: 0) {
                        SelectionToolbar()
                        Divider()
                        MetalPointCloudView()
                            .ignoresSafeArea()
                    }
                } else {
                    DropZoneView()
                }
            }
        }
        .fileImporter(
            isPresented: $vm.showFileImporter,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { vm.importFile(url: url) }
            case .failure(let err):
                vm.loadError = err.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $vm.showExporter,
            document: SelectedRowsDocument(viewModel: vm),
            contentType: .commaSeparatedText,
            defaultFilename: "selected_points"
        ) { result in
            if case .failure(let err) = result { vm.loadError = err.localizedDescription }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.loadError != nil },
            set: { if !$0 { vm.loadError = nil } }
        )) {
            Button("OK") { vm.loadError = nil }
        } message: {
            Text(vm.loadError ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            providers.first?.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                if let data = item as? Data,
                   let url  = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async { vm.importFile(url: url) }
                }
            }
            return true
        }
        .toolbar {
            ToolbarItem {
                Button {
                    vm.showFileImporter = true
                } label: {
                    Label("Open File", systemImage: "folder.badge.plus")
                }
                .help("Open CSV / TSV file  (⌘O)")
            }
        }
    }
}

// MARK: – Empty state
struct DropZoneView: View {
    @EnvironmentObject var vm: PointCloudViewModel
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Point Cloud Viewer")
                .font(.title2)
            Text("Open a CSV or TSV file with X, Y, Z columns.\nDrag & drop or use File → Open.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open File…") { vm.showFileImporter = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: – FileDocument for export (no @MainActor needed here)
struct SelectedRowsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    // Capture the data we need at construction time (on MainActor)
    let csvString: String

    @MainActor init(viewModel: PointCloudViewModel) {
        guard let d = viewModel.data else { csvString = ""; return }
        var lines: [String] = [d.headers.joined(separator: ",")]
        for idx in viewModel.selectedIndices.sorted() where idx < d.rows.count {
            lines.append(d.rows[idx].rawValues.joined(separator: ","))
        }
        csvString = lines.joined(separator: "\n")
    }

    init(configuration: ReadConfiguration) throws {
        csvString = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = csvString.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
