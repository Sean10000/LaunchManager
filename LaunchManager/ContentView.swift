//
//  ContentView.swift
//  LaunchManager
//
//  Created by Shi-Cheng Ma on 2026/4/22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = AgentStore()
    @StateObject private var serviceStore = ServiceStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarSelection? = .scope(.userAgent)
    @State private var showingNewAgent = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var showAbout = false

    private var selectedScope: LaunchItem.Scope? {
        if case .scope(let scope) = selection { return scope }
        return nil
    }

    private var isLoginItemsGuide: Bool {
        selection == .loginItems
    }

    private var isServicesView: Bool {
        selection == .services
    }

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
            SidebarView(selection: $selection, store: store)
        } detail: {
            detailView
        }
        .modifier(ConditionalSearchable(
            isEnabled: !isLoginItemsGuide && !isServicesView,
            text: $searchText,
            prompt: "搜索 Label 或路径"
        ))
        .onAppear {
            store.refresh()
            serviceStore.startPolling(isActive: scenePhase == .active)
            if !hasSeenOnboarding {
                showOnboarding = true
                hasSeenOnboarding = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            serviceStore.startPolling(isActive: phase == .active)
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection == .services {
                serviceStore.refreshNow()
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

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .services:
            ServicesListView(store: serviceStore, errorMessage: $errorMessage)
        case .loginItems:
            LoginItemsGuideView()
        case .scope, .none:
            AgentListView(
                items: filteredItems,
                invalidItems: filteredInvalidItems,
                store: store,
                showingNewAgent: $showingNewAgent,
                errorMessage: $errorMessage
            )
        }
    }
}

/// Applies `.searchable` only when listing launchd agents (hidden on Login Items guide).
private struct ConditionalSearchable: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String
    let prompt: LocalizedStringKey

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}
