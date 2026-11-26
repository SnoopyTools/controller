import SwiftUI
import UIKit

enum BrowserBackend: String, CaseIterable, Identifiable {
    case auto = "Auto (VFS / FS)"
    case vfs = "VFS"
    case fileManager = "FileManager"

    var id: String { rawValue }
}

struct BrowserEntry: Identifiable, Hashable {
    let id: String
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let usesVFS: Bool

    var formattedSize: String {
        guard !isDirectory, let size, size >= 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct FileBrowserView: View {
    @EnvironmentObject private var mgr: controllermgr

    @State private var currentPath: String
    @State private var backend: BrowserBackend = .auto
    @State private var entries: [BrowserEntry] = []
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var previewEntry: BrowserEntry?
    @State private var shareURL: URL?

    init(initialPath: String = "/var/mobile") {
        _currentPath = State(initialValue: initialPath)
    }

    private var filteredEntries: [BrowserEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var activeUsesVFS: Bool {
        switch backend {
        case .vfs: return true
        case .fileManager: return false
        case .auto: return mgr.vfsready
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: activeUsesVFS ? "externaldrive.connected.to.line.below.fill" : "folder.fill")
                        .foregroundColor(.purple)
                    Text(currentPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                Picker("Backend", selection: $backend) {
                    ForEach(BrowserBackend.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: backend) { _ in
                    reloadDirectory()
                }
            }

            Section {
                if filteredEntries.isEmpty {
                    Text(errorMessage == nil ? "Empty or unreadable directory" : "No entries loaded")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filteredEntries) { entry in
                        row(for: entry)
                    }
                }
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Filter")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    if currentPath != "/" {
                        Button {
                            navigate(to: parentPath(of: currentPath))
                        } label: {
                            Label("Up", systemImage: "chevron.up")
                        }
                    }
                    Menu("Jump") {
                        Button("/") { navigate(to: "/") }
                        Button("/var/mobile") { navigate(to: "/var/mobile") }
                        Button("/var/containers/Bundle/Application") { navigate(to: "/var/containers/Bundle/Application") }
                        Button("/System/Library") { navigate(to: "/System/Library") }
                        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            Button("App Documents") { navigate(to: docs.path) }
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reloadDirectory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            reloadDirectory()
        }
        .sheet(item: $previewEntry) { entry in
            BrowserPreviewSheet(entry: entry, usesVFS: entry.usesVFS)
                .environmentObject(mgr)
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ShareSheetView(items: [shareURL])
            }
        }
    }

    private var displayTitle: String {
        if currentPath == "/" { return "/" }
        let name = (currentPath as NSString).lastPathComponent
        return name.isEmpty ? currentPath : name
    }

    private func parentPath(of path: String) -> String {
        if path == "/" { return "/" }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    private func joinPath(_ base: String, _ child: String) -> String {
        if base == "/" { return "/\(child)" }
        return (base as NSString).appendingPathComponent(child)
    }

    @ViewBuilder
    private func row(for entry: BrowserEntry) -> some View {
        Button {
            if entry.isDirectory {
                navigate(to: entry.path)
            } else {
                previewEntry = entry
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory ? "folder.fill" : iconName(for: entry.name))
                    .foregroundColor(entry.isDirectory ? .purple : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !entry.isDirectory && !entry.formattedSize.isEmpty {
                        Text(entry.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contextMenu {
            if !entry.isDirectory {
                Button {
                    previewEntry = entry
                } label: {
                    Label("Preview", systemImage: "doc.text.magnifyingglass")
                }

                if entry.name.lowercased().hasSuffix(".zip") || entry.name.lowercased().hasSuffix(".ipa") {
                    Button {
                        extractArchive(entry)
                    } label: {
                        Label("Extract to Documents", systemImage: "doc.zipper")
                    }
                }

                Button {
                    prepareShare(for: entry)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func iconName(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "plist", "json", "xml", "yml", "yaml", "txt", "log", "md", "c", "h", "m", "swift":
            return "doc.text"
        case "png", "jpg", "jpeg", "heic", "gif":
            return "photo"
        case "zip", "ipa", "deb", "tar", "gz":
            return "doc.zipper"
        case "dylib", "axf", "bin", "img":
            return "cpu"
        default:
            return "doc"
        }
    }

    private func navigate(to path: String) {
        currentPath = path
        searchText = ""
        reloadDirectory()
    }

    private func reloadDirectory() {
        errorMessage = nil
        let targetPath = currentPath
        let shouldUseVFS = activeUsesVFS

        if shouldUseVFS {
            guard mgr.vfsready else {
                entries = []
                errorMessage = "VFS not ready (run exploit first or switch to FileManager)."
                return
            }
            if let vfsItems = mgr.vfslistdir(path: targetPath) {
                entries = vfsItems.map { item in
                    let full = joinPath(targetPath, item.name)
                    let sz = item.isDir ? nil : mgr.vfssize(path: full)
                    return BrowserEntry(
                        id: full,
                        path: full,
                        name: item.name,
                        isDirectory: item.isDir,
                        size: sz,
                        usesVFS: true
                    )
                }.sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                globallogger.log("[BROWSER] Listed \(targetPath) via VFS (\(entries.count) items)")
            } else {
                entries = []
                errorMessage = "VFS listdir failed for \(targetPath)"
            }
        } else {
            let fm = FileManager.default
            do {
                let names = try fm.contentsOfDirectory(atPath: targetPath)
                var list: [BrowserEntry] = []
                for name in names {
                    let full = joinPath(targetPath, name)
                    var isDir: ObjCBool = false
                    _ = fm.fileExists(atPath: full, isDirectory: &isDir)
                    let attrs = try? fm.attributesOfItem(atPath: full)
                    let sz = (attrs?[.size] as? NSNumber)?.int64Value
                    list.append(
                        BrowserEntry(
                            id: full,
                            path: full,
                            name: name,
                            isDirectory: isDir.boolValue,
                            size: isDir.boolValue ? nil : sz,
                            usesVFS: false
                        )
                    )
                }
                entries = list.sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                globallogger.log("[BROWSER] Listed \(targetPath) via FileManager (\(entries.count) items)")
            } catch {
                entries = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadData(for entry: BrowserEntry, maxSize: Int = 512 * 1024) -> Data? {
        if entry.usesVFS {
            return mgr.vfsread(path: entry.path, maxSize: maxSize)
        }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: entry.path)) else {
            return nil
        }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxSize)
    }

    private func extractArchive(_ entry: BrowserEntry) {
        globallogger.log("[BROWSER] Extracting \(entry.path)...")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = loadData(for: entry, maxSize: 128 * 1024 * 1024) else {
                DispatchQueue.main.async {
                    errorMessage = "Could not read archive \(entry.name)"
                }
                return
            }
            do {
                let archive = try ZipArchive(data: data)
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let baseName = (entry.name as NSString).deletingPathExtension
                let destRoot = docs.appendingPathComponent("Extracted_\(baseName)_\(UUID().uuidString.prefix(6))", isDirectory: true)
                try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)

                for zEntry in archive.entries {
                    let norm = zEntry.path.replacingOccurrences(of: "\\", with: "/")
                    guard !norm.contains("..") else { continue }
                    let outURL = destRoot.appendingPathComponent(norm)
                    if zEntry.isDirectory {
                        try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
                    } else {
                        try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let extracted = try archive.extract(zEntry)
                        try extracted.write(to: outURL)
                    }
                }
                globallogger.log("[BROWSER] Extracted \(entry.name) to \(destRoot.path)")
                DispatchQueue.main.async {
                    mgr.emitResult(title: "Extracted", body: "Saved to:\n\(destRoot.path)", ok: true, icon: "doc.zipper")
                }
            } catch {
                globallogger.log("[BROWSER] Extract failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func prepareShare(for entry: BrowserEntry) {
        if !entry.usesVFS {
            shareURL = URL(fileURLWithPath: entry.path)
            return
        }
        guard let data = loadData(for: entry, maxSize: 32 * 1024 * 1024) else {
            errorMessage = "Unable to read \(entry.name) via VFS for sharing."
            return
        }
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(entry.name)
        do {
            try data.write(to: tmpURL)
            shareURL = tmpURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BrowserPreviewSheet: View {
    @EnvironmentObject private var mgr: controllermgr
    @Environment(\.dismiss) private var dismiss

    let entry: BrowserEntry
    let usesVFS: Bool

    @State private var image: UIImage?
    @State private var text: String = "Loading..."

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                } else {
                    ScrollView {
                        Text(text)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                load()
            }
        }
    }

    private func load() {
        let cap = 256 * 1024
        let data: Data?
        if usesVFS {
            data = mgr.vfsread(path: entry.path, maxSize: cap)
        } else {
            let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: entry.path))
            data = try? handle?.read(upToCount: cap)
            try? handle?.close()
        }

        guard let data else {
            text = "Unable to read file (\(usesVFS ? "VFS" : "FileManager"))."
            return
        }

        if let img = UIImage(data: data) {
            image = img
            return
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            text = data.count >= cap ? utf8 + "\n\n... (truncated at 256 KB)" : utf8
            return
        }

        let hexBytes = data.prefix(2048).map { String(format: "%02X", $0) }.joined(separator: " ")
        text = "Binary (\(data.count) bytes read):\n\n" + hexBytes
    }
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}