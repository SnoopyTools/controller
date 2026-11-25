import SwiftUI
import UIKit

enum BrowserSkin: String, CaseIterable, Identifiable {
    case solid = "Solid Explorer"
    case asus = "ASUS File Manager"
    case rootExplorer = "Root Explorer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .solid: return "square.grid.2x2.fill"
        case .asus: return "sparkles.rectangle.stack.fill"
        case .rootExplorer: return "terminal.fill"
        }
    }
}

enum BrowserBackend: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case vfs = "VFS"
    case fileManager = "FS"

    var id: String { rawValue }
}

enum BrowserSortMode: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Size"
    case kind = "Type"

    var id: String { rawValue }
}

struct QuickBookmark: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let path: String
    let icon: String
    let tint: Color
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

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
}

struct FileBrowserView: View {
    @EnvironmentObject private var mgr: controllermgr

    @State private var currentPath: String
    @State private var skin: BrowserSkin = .solid
    @State private var backend: BrowserBackend = .auto
    @State private var sortMode: BrowserSortMode = .name
    @State private var isGridView: Bool = false
    @State private var entries: [BrowserEntry] = []
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var showDrawer: Bool = false
    @State private var previewEntry: BrowserEntry?
    @State private var shareURL: URL?

    init(initialPath: String = "/var/mobile") {
        _currentPath = State(initialValue: initialPath)
    }

    private var appDocumentsPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "/var/mobile"
    }

    private var collectionBookmarks: [QuickBookmark] {
        [
            QuickBookmark(title: "Documents", subtitle: "/var/mobile/Documents", path: "/var/mobile/Documents", icon: "doc.text.fill", tint: .purple),
            QuickBookmark(title: "Downloads", subtitle: "/var/mobile/Downloads", path: "/var/mobile/Downloads", icon: "arrow.down.circle.fill", tint: .indigo),
            QuickBookmark(title: "Pictures", subtitle: "/var/mobile/Media/DCIM", path: "/var/mobile/Media/DCIM", icon: "photo.fill.on.rectangle.fill", tint: .pink),
            QuickBookmark(title: "Videos", subtitle: "/var/mobile/Media/DCIM", path: "/var/mobile/Media/DCIM", icon: "film.fill", tint: .orange),
            QuickBookmark(title: "Media & Audio", subtitle: "/var/mobile/Media", path: "/var/mobile/Media", icon: "music.note.list", tint: .teal)
        ]
    }

    private var storageBookmarks: [QuickBookmark] {
        [
            QuickBookmark(title: "App Sandbox", subtitle: "Local Documents", path: appDocumentsPath, icon: "shippingbox.fill", tint: .purple),
            QuickBookmark(title: "Device Root", subtitle: "/", path: "/", icon: "internaldrive.fill", tint: .purple),
            QuickBookmark(title: "Mobile Home", subtitle: "/var/mobile", path: "/var/mobile", icon: "house.fill", tint: .blue),
            QuickBookmark(title: "App Containers", subtitle: "/var/containers/Bundle/Application", path: "/var/containers/Bundle/Application", icon: "square.grid.2x2.fill", tint: .cyan),
            QuickBookmark(title: "System Library", subtitle: "/System/Library", path: "/System/Library", icon: "gearshape.2.fill", tint: .gray)
        ]
    }

    private var sortedAndFilteredEntries: [BrowserEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = q.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(q) }

        return base.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            switch sortMode {
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                let lSize = lhs.size ?? -1
                let rSize = rhs.size ?? -1
                if lSize != rSize { return lSize > rSize }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .kind:
                if lhs.fileExtension != rhs.fileExtension {
                    return lhs.fileExtension.localizedStandardCompare(rhs.fileExtension) == .orderedAscending
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var activeUsesVFS: Bool {
        switch backend {
        case .vfs: return true
        case .fileManager: return false
        case .auto: return mgr.vfsready
        }
    }

    private var breadcrumbs: [(title: String, path: String)] {
        if currentPath == "/" {
            return [("Root", "/")]
        }
        var crumbs: [(String, String)] = [("Root", "/")]
        let parts = currentPath.split(separator: "/").map(String.init)
        var running = ""
        for part in parts {
            running += "/" + part
            crumbs.append((part, running))
        }
        return crumbs
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                switch skin {
                case .solid:
                    solidSkinBody
                case .asus:
                    asusSkinBody
                case .rootExplorer:
                    rootExplorerSkinBody
                }
            }

            if showDrawer {
                drawerOverlay
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search in \(displayTitle)")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDrawer.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.purple)
                    }

                    if currentPath != "/" {
                        Button {
                            navigate(to: parentPath(of: currentPath))
                        } label: {
                            Image(systemName: "arrow.up.to.line")
                                .foregroundColor(.purple)
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(BrowserSkin.allCases) { option in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    skin = option
                                }
                            } label: {
                                Label(option.rawValue, systemImage: skin == option ? "checkmark" : option.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "paintbrush.fill")
                            .foregroundColor(.purple)
                    }

                    Menu {
                        Picker("Sort By", selection: $sortMode) {
                            ForEach(BrowserSortMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.purple)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isGridView.toggle()
                        }
                    } label: {
                        Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                            .foregroundColor(.purple)
                    }

                    Button {
                        reloadDirectory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.purple)
                    }
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

    // MARK: - Skin 1: Solid Explorer

    private var solidSkinBody: some View {
        VStack(spacing: 0) {
            headerBar
            breadcrumbBar

            if let errorMessage {
                errorCard(errorMessage)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            if sortedAndFilteredEntries.isEmpty {
                emptyStateView
            } else if isGridView {
                gridContent
            } else {
                listContent
            }

            bottomStatusBar
        }
    }

    // MARK: - Skin 2: ASUS File Manager

    private var asusSkinBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ASUS Style • \(skin.rawValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.purple)
                        Text(currentPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    Spacer()
                    Picker("Backend", selection: $backend) {
                        ForEach(BrowserBackend.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 155)
                    .onChange(of: backend) { _ in
                        reloadDirectory()
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(collectionBookmarks) { item in
                            Button {
                                navigate(to: item.path)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.icon)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.purple)
                                    Text(item.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(white: 0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.07))

            if let errorMessage {
                errorCard(errorMessage)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            if sortedAndFilteredEntries.isEmpty {
                emptyStateView
            } else if isGridView {
                gridContent
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedAndFilteredEntries) { entry in
                            let style = badgeStyle(for: entry)
                            Button {
                                if entry.isDirectory {
                                    navigate(to: entry.path)
                                } else {
                                    previewEntry = entry
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(style.color.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: style.icon)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(style.color)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(entry.isDirectory ? "Folder" : entry.formattedSize)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    if entry.isDirectory {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundColor(.purple)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(white: 0.1))
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                entryContextMenu(for: entry)
                            }
                        }
                    }
                    .padding(14)
                }
            }

            bottomStatusBar
        }
    }

    // MARK: - Skin 3: Root Explorer

    private var rootExplorerSkinBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("ROOT EXPLORER")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(activeUsesVFS ? "VFS: READY" : "FS: SANDBOX")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(activeUsesVFS ? .green : .gray)

                    Spacer()

                    Picker("Backend", selection: $backend) {
                        ForEach(BrowserBackend.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .onChange(of: backend) { _ in
                        reloadDirectory()
                    }
                }

                Text(currentPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.purple.opacity(0.35), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.06))

            if let errorMessage {
                errorCard(errorMessage)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if sortedAndFilteredEntries.isEmpty {
                emptyStateView
            } else if isGridView {
                gridContent
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedAndFilteredEntries) { entry in
                            let style = badgeStyle(for: entry)
                            Button {
                                if entry.isDirectory {
                                    navigate(to: entry.path)
                                } else {
                                    previewEntry = entry
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: style.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(entry.isDirectory ? .purple : style.color)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.system(.subheadline, design: .monospaced))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(entry.isDirectory ? "dir • \(entry.usesVFS ? "vfs" : "fs")" : "\(entry.formattedSize.isEmpty ? "0 B" : entry.formattedSize) • \(entry.usesVFS ? "vfs" : "fs")")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    if entry.isDirectory {
                                        Text(">")
                                            .font(.system(.caption, design: .monospaced).weight(.bold))
                                            .foregroundColor(.purple)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(white: 0.04))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                entryContextMenu(for: entry)
                            }

                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
            }

            bottomStatusBar
        }
    }

    // MARK: - Shared Header, Breadcrumbs, List/Grid & Drawer

    private var headerBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(activeUsesVFS ? Color.green : Color.purple)
                    .frame(width: 8, height: 8)
                Text(activeUsesVFS ? "VFS Active" : "FileManager")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.12))
            .clipShape(Capsule())

            Spacer()

            Picker("Backend", selection: $backend) {
                ForEach(BrowserBackend.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .onChange(of: backend) { _ in
                reloadDirectory()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.06))
    }

    private var breadcrumbBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                        Button {
                            navigate(to: crumb.path)
                        } label: {
                            HStack(spacing: 4) {
                                if index == 0 {
                                    Image(systemName: "internaldrive.fill")
                                        .font(.caption2)
                                }
                                Text(crumb.title)
                                    .font(.caption.weight(index == breadcrumbs.count - 1 ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                index == breadcrumbs.count - 1
                                    ? Color.purple.opacity(0.28)
                                    : Color(white: 0.12)
                            )
                            .foregroundColor(index == breadcrumbs.count - 1 ? .white : .gray)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        index == breadcrumbs.count - 1 ? Color.purple.opacity(0.6) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .id(index)

                        if index < breadcrumbs.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Color(white: 0.08))
            .overlay(