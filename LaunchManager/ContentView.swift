//
//  ContentView.swift
//  LaunchManager
//
//  Created by Shi-Cheng Ma on 2026/4/22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = AgentStore()
    @State private var selectedScope: LaunchItem.Scope? = .userAgent
    @State private var showingNewAgent = false
    @State private var errorMessage: String?

    var filteredItems: [LaunchItem] {
        guard let scope = selectedScope else { return store.items }
        return store.items.filter { $0.scope == scope }
    }

    var filteredInvalidItems: [InvalidPlist] {
        guard let scope = selectedScope else { return store.invalidItems }
        return store.invalidItems.filter { $0.scope == scope }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedScope: $selectedScope, store: store)
        } detail: {
            AgentListView(
                items: filteredItems,
                invalidItems: filteredInvalidItems,
                store: store,
                showingNewAgent: $showingNewAgent,
                errorMessage: $errorMessage
            )
        }
        .onAppear { store.refresh() }
        .sheet(isPresented: $showingNewAgent) {
            EditAgentSheet(
                existingItem: nil,
                defaultScope: selectedScope ?? .userAgent,
                store: store
            )
        }
        .alert("错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
