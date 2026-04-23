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
    @State private var searchText = ""
    @State private var errorMessage: String?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var showAbout = false

    var filteredItems: [LaunchItem] {
        let scoped = selectedScope.map { scope in store.items.filter { $0.scope == scope } } ?? store.items
        guard !searchText.isEmpty else { return scoped }
        return scoped.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.program.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredInvalidItems: [InvalidPlist] {
        let scoped = selectedScope.map { scope in store.invalidItems.filter { $0.scope == scope } } ?? store.invalidItems
        guard !searchText.isEmpty else { return scoped }
        return scoped.filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
        }
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
        .searchable(text: $searchText, prompt: "搜索 Label 或路径")
        .onAppear {
            store.refresh()
            if !hasSeenOnboarding {
                showOnboarding = true
                hasSeenOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
            showAbout = true
        }
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
