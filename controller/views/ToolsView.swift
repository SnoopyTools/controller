//
//  ToolsView.swift
//  controller
//

import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var mgr: controllermgr

    var body: some View {
        NavigationStack {
            List {
                Section("Filesystem") {
                    NavigationLink {
                        FileBrowserView(initialPath: "/var/mobile")
                            .environmentObject(mgr)
                    } label: {
                        Label("File Browser", systemImage: "folder.fill")
                    }
                }
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}