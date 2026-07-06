//
//  ContentView.swift
//  LaunchManager
//
//  Created by Shi-Cheng Ma on 2026/4/22.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = AgentStore()
    @StateObject private var serviceStore = ServiceStore()
    @StateObject private var updateChecker = UpdateChecker()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarSelection? = .agents
    @State private var showingNewAgent = false
    @State private var showingNewFromXml = false
    @State private var newAgentScope: LaunchItem.Scope = .userAgent
    @State private var serviceLaunchDraft: LaunchAgentDraft?
    @State private var searchText = ""
    @State private var errorMessage: String?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var showAbout = false
    @State private var pendingUpdateCheck = false

    private var isLoginItemsGuide: Bool {
        selection == .loginItems
    }

    private var isServicesView: Bool {
        selection == .services
    }

    private var isAgentsView: Bool {
        selection == .agents || selection == nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, store: store)
        } detail: {
            detailView
        }
        .modifier(ConditionalSearchable(
            isEnabled: isAgentsView && !isLoginItemsGuide && !isServicesView,
            text: $searchText,
            prompt: "搜索 Label 或路径"
        ))
        .onAppear {
            store.refresh()
            store.startWatching()
            serviceStore.startPolling(isActive: scenePhase == .active)
            if !hasSeenOnboarding {
                showOnboarding = true
                hasSeenOnboarding = true
                pendingUpdateCheck = true
            } else {
                updateChecker.checkIfNeeded()
            }
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if pendingUpdateCheck && !isShowing {
                pendingUpdateCheck = false
                updateChecker.checkIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            serviceStore.startPolling(isActive: phase == .active)
            if phase == .active {
                store.refresh()
            }
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
            AboutView(updateChecker: updateChecker)
        }
        .sheet(item: $updateChecker.pendingRelease) { release in
            UpdateAvailableSheet(
                release: release,
                currentVersion: updateChecker.currentVersion,
                onSkip: { updateChecker.skipVersion(release.version) },
                onDismiss: { updateChecker.dismissForLater() }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
            showAbout = true
        }
        .sheet(isPresented: $showingNewAgent) {
            EditAgentSheet(
                existingItem: nil,
                defaultScope: newAgentScope,
                store: store
            )
        }
        .sheet(isPresented: $showingNewFromXml) {
            EditAgentSheet(
                existingItem: nil,
                defaultScope: newAgentScope,
                store: store,
                initialXml: newAgentInitialXml
            )
        }
        .sheet(item: $serviceLaunchDraft) { draft in
            EditAgentSheet(
                existingItem: nil,
                defaultScope: .userAgent,
                store: store,
                draft: draft
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

    private var newAgentInitialXml: String {
        if let clip = NSPasteboard.general.string(forType: .string),
           clip.contains("<plist") {
            return clip
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.example.myagent</string>
            <key>ProgramArguments</key>
            <array><string>/path/to/program</string></array>
            <key>RunAtLoad</key><true/>
        </dict></plist>
        """
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .services:
            ServicesListView(
                store: serviceStore,
                errorMessage: $errorMessage,
                onCreateLaunchAgent: { draft in serviceLaunchDraft = draft }
            )
        case .loginItems:
            LoginItemsGuideView()
        case .agents, .none:
            AgentListView(
                store: store,
                searchText: searchText,
                newAgentScope: $newAgentScope,
                showingNewAgent: $showingNewAgent,
                showingNewFromXml: $showingNewFromXml,
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
