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
        _currentPath = State(initialValue: Self.normalizePath(initialPath))
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

    private var backendStatusLabel: String {
        if activeUsesVFS {
            if !mgr.vfsready { return "VFS Not Ready" }
            return errorMessage != nil ? "VFS Read Error" : "VFS Ready"
        }
        return "FileManager"
    }

    private var backendStatusColor: Color {
        if activeUsesVFS {
            if !mgr.vfsready { return .orange }
            return errorMessage != nil ? .red : .green
        }
        return .purple
    }

    private var breadcrumbs: [(title: String, path: String)] {
        let clean = Self.normalizePath(currentPath)
        if clean == "/" {
            return [("Root", "/")]
        }
        var crumbs: [(String, String)] = [("Root", "/")]
        let parts = clean.split(separator: "/").map(String.init)
        var running = ""
        for part in parts {
            running += "/" + part
            crumbs.append((part, running))
        }
        return crumbs
    }

    var body: some View {
        ZStack {
            Color.black

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
        .background(Color.black)
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search in \(displayTitle)")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 10) {
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
                HStack(spacing: 10) {
                    Button {
                        reloadDirectory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.purple)
                    }

                    Menu {
                        Section("Skin") {
                            ForEach(BrowserSkin.allCases) { option in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        skin = option
                                    }
                                } label: {
                                    Label(option.rawValue, systemImage: skin == option ? "checkmark" : option.icon)
                                }
                            }
                        }

                        Section("Sort By") {
                            ForEach(BrowserSortMode.allCases) { mode in
                                Button {
                                    sortMode = mode
                                } label: {
                                    Label(mode.rawValue, systemImage: sortMode == mode ? "checkmark" : "arrow.up.arrow.down")
                                }
                            }
                        }

                        Section("Layout") {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isGridView.toggle()
                                }
                            } label: {
                                Label(isGridView ? "Switch to List" : "Switch to Grid", systemImage: isGridView ? "list.bullet" : "square.grid.2x2")
                            }
                        }
                    } label: {
                        Image(systemName: "paintbrush.fill")
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
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skin.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.purple)
                            .lineLimit(1)
                        Text(currentPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Picker("Backend", selection: $backend) {
                        ForEach(BrowserBackend.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
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
                                        .lineLimit(1)
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
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(backendStatusLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundColor(backendStatusColor)
                        .lineLimit(1)

                    Spacer()

                    Picker("Backend", selection: $backend) {
                        ForEach(BrowserBackend.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: backend) { _ in
                        reloadDirectory()
                    }
                }

                Text(currentPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(backendStatusColor)
                    .frame(width: 8, height: 8)
                Text(backendStatusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
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
            .fixedSize()
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
                                    .lineLimit(1)
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
                Divider().background(Color.white.opacity(0.08)),
                alignment: .bottom
            )
            .onChange(of: currentPath) { _ in
                withAnimation {
                    proxy.scrollTo(breadcrumbs.count - 1, anchor: .trailing)
                }
            }
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(sortedAndFilteredEntries) { entry in
                    solidListRow(for: entry)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var gridContent: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(sortedAndFilteredEntries) { entry in
                    solidGridCell(for: entry)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func solidListRow(for entry: BrowserEntry) -> some View {
        let style = badgeStyle(for: entry)
        Button {
            if entry.isDirectory {
                navigate(to: entry.path)
            } else {
                previewEntry = entry
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(style.color.opacity(0.2))
                        .frame(width: 42, height: 42)
                    Image(systemName: style.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(style.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(entry.isDirectory ? "Folder" : (entry.fileExtension.isEmpty ? "File" : entry.fileExtension.uppercased()))
                            .font(.caption2)
                            .foregroundColor(.gray)

                        if !entry.isDirectory && !entry.formattedSize.isEmpty {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.6))
                            Text(entry.formattedSize)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }

                Spacer()

                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(white: 0.05))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            entryContextMenu(for: entry)
        }
    }

    @ViewBuilder
    private func solidGridCell(for entry: BrowserEntry) -> some View {
        let style = badgeStyle(for: entry)
        Button {
            if entry.isDirectory {
                navigate(to: entry.path)
            } else {
                previewEntry = entry
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(style.color.opacity(0.18))
                        .frame(width: 54, height: 54)
                    Image(systemName: style.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(style.color)
                }

                Text(entry.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(entry.isDirectory ? "Folder" : entry.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            entryContextMenu(for: entry)
        }
    }

    @ViewBuilder
    private func entryContextMenu(for entry: BrowserEntry) -> some View {
        Button {
            UIPasteboard.general.string = entry.path
            globallogger.log("[BROWSER] Copied path: \(entry.path)")
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

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

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: errorMessage == nil ? "folder" : "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.purple.opacity(0.6))
            Text(errorMessage == nil ? "Empty Directory" : "Cannot Read Directory")
                .font(.headline)
                .foregroundColor(.white)
            Text(errorMessage == nil ? "No files or folders in \(displayTitle)" : "Switch backend or jump to another folder from the sidebar.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var bottomStatusBar: some View {
        let folderCount = sortedAndFilteredEntries.filter { $0.isDirectory }.count
        let fileCount = sortedAndFilteredEntries.count - folderCount
        return HStack(spacing: 10) {
            Text("\(folderCount) folders, \(fileCount) files")
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(1)
                .fixedSize()
            Spacer()
            Text(currentPath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
        .overlay(
            Divider().background(Color.white.opacity(0.12)),
            alignment: .top
        )
    }

    private var drawerOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.6)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDrawer = false
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.25))
                                .frame(width: 44, height: 44)
                            Image(systemName: "folder.fill")
                                .font(.title2)
                                .foregroundColor(.purple)
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showDrawer = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                    }
                    Text("Controller Explorer")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Skin: \(skin.rawValue)")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
                .padding(18)
                .background(Color(white: 0.11))

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        drawerSection(title: "COLLECTIONS", items: collectionBookmarks)
                        Divider().background(Color.white.opacity(0.1))
                        drawerSection(title: "STORAGE & SYSTEM", items: storageBookmarks)
                    }
                    .padding(14)
                }
            }
            .frame(width: 285)
            .background(Color(white: 0.08))
            .overlay(
                Divider().background(Color.purple.opacity(0.3)),
                alignment: .trailing
            )
            .transition(.move(edge: .leading))
        }
    }

    @ViewBuilder
    private func drawerSection(title: String, items: [QuickBookmark]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 8)

            ForEach(items) { item in
                let isSelected = currentPath == item.path
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDrawer = false
                    }
                    navigate(to: item.path)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(item.tint.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(item.tint)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                            Text(item.subtitle)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.purple.opacity(0.22) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers & Existing Filesystem Logic

    private static func normalizePath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" { return "/" }
        let components = trimmed.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }

    private var displayTitle: String {
        if currentPath == "/" { return "Root" }
        let name = (currentPath as NSString).lastPathComponent
        return name.isEmpty ? currentPath : name
    }

    private func parentPath(of path: String) -> String {
        let clean = Self.normalizePath(path)
        if clean == "/" { return "/" }
        let parent = (clean as NSString).deletingLastPathComponent
        return Self.normalizePath(parent.isEmpty ? "/" : parent)
    }

    private func joinPath(_ base: String, _ child: String) -> String {
        let cleanBase = Self.normalizePath(base)
        let cleanChild = child.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleanChild.isEmpty { return cleanBase }
        if cleanBase == "/" { return "/\(cleanChild)" }
        return "\(cleanBase)/\(cleanChild)"
    }

    private func badgeStyle(for entry: BrowserEntry) -> (icon: String, color: Color) {
        if entry.isDirectory {
            return ("folder.fill", .purple)
        }
        switch entry.fileExtension {
        case "plist", "json", "xml", "yml", "yaml", "txt", "log", "md", "c", "h", "m", "swift":
            return ("doc.text.fill", .blue)
        case "png", "jpg", "jpeg", "heic", "gif", "webp":
            return ("photo.fill", .pink)
        case "mp4", "mov", "m4v", "avi", "mkv":
            return ("film.fill", .orange)
        case "mp3", "m4a", "wav", "aac", "flac":
            return ("music.note", .teal)
        case "zip", "ipa", "deb", "tar", "gz":
            return ("doc.zipper", .indigo)
        case "dylib", "axf", "bin", "img":
            return ("cpu.fill", .green)
        default:
            return ("doc.fill", .gray)
        }
    }

    private func navigate(to path: String) {
        let nextPath = Self.normalizePath(path)
        globallogger.log("[BROWSER] Navigate \(currentPath) -> \(nextPath)")
        currentPath = nextPath
        searchText = ""
        reloadDirectory()
    }

    private func reloadDirectory() {
        errorMessage = nil
        let targetPath = Self.normalizePath(currentPath)
        currentPath = targetPath
        let shouldUseVFS = activeUsesVFS

        if shouldUseVFS {
            guard mgr.vfsready else {
                entries = []
                errorMessage = "VFS not ready (run exploit first or switch to FS)."
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
                }
                globallogger.log("[BROWSER] Listed \(targetPath) via VFS (\(entries.count) items)")
            } else {
                entries = []
                errorMessage = "VFS listdir failed for \(targetPath)"
                globallogger.log("[BROWSER] VFS listdir failed for \(targetPath)")
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
                entries = list
                globallogger.log("[BROWSER] Listed \(targetPath) via FileManager (\(entries.count) items)")
            } catch {
                entries = []
                errorMessage = error.localizedDescription
                globallogger.log("[BROWSER] FileManager failed for \(targetPath): \(error.localizedDescription)")
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
            ZStack {
                Color.black.ignoresSafeArea()

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
                            .foregroundColor(.white)
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
                        .foregroundColor(.purple)
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