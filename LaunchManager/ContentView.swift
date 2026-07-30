//
//  ContentView.swift
//  LaunchManager
//
//  Created by Shi-Cheng Ma on 2026/4/22.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var moduleSettings = ModuleSettingsStore()
    @StateObject private var store = AgentStore()
    @StateObject private var crontabStore = CrontabStore()
    @StateObject private var homebrewStore = HomebrewServiceStore()
    @StateObject private var serviceStore = ServiceStore()
    @StateObject private var updateChecker = UpdateChecker()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarSelection? = .agents
    @State private var showingNewAgent = false
    @State private var showingNewFromXml = false
    @State private var newAgentScope: LaunchItem.Scope = .userAgent
    @State private var showingNewCron = false
    @State private var newCronScope: CrontabScope = .user
    @State private var serviceLaunchDraft: LaunchAgentDraft?
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var showModuleSettings = false
    @State private var showHelpConfirm = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var showAbout = false
    @State private var pendingUpdateCheck = false

    private var isCrontabView: Bool {
        selection == .crontab
    }

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
            SidebarView(
                selection: $selection,
                moduleSettings: moduleSettings,
                store: store,
                crontabStore: crontabStore,
                showModuleSettings: $showModuleSettings,
                onHelpTapped: { showHelpConfirm = true }
            )
        } detail: {
            detailView
        }
        .modifier(ConditionalSearchable(
            isEnabled: (isAgentsView || isCrontabView) && !isLoginItemsGuide && !isServicesView,
            text: $searchText,
            prompt: searchPrompt
        ))
        .onAppear {
            ensureValidSelection()
            syncModuleScanning()
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
            syncModuleScanning(active: phase == .active)
        }
        .onChange(of: selection) { _, newSelection in
            guard let newSelection else { return }
            refreshModuleIfNeeded(newSelection)
        }
        .onChange(of: moduleSettings.settings) { _, _ in
            ensureValidSelection()
            syncModuleScanning()
        }
        .onReceive(NotificationCenter.default.publisher(for: .brewServicesDidChange)) { _ in
            if isAgentsView, moduleSettings.isEnabled(.agents) {
                store.refresh()
            }
        }
        .sheet(isPresented: $showModuleSettings) {
            ModuleSettingsSheet(moduleSettings: moduleSettings)
        }
        .confirmationDialog(
            "打开用户手册？",
            isPresented: $showHelpConfirm,
            titleVisibility: .visible
        ) {
            Button("在浏览器中打开") {
                NSWorkspace.shared.open(AppLinks.helpURL)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将在默认浏览器中打开 launchmanager.dev/help")
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
        .sheet(isPresented: $showingNewCron) {
            EditCronSheet(
                existingJob: nil,
                scope: newCronScope,
                store: crontabStore,
                errorMessage: $errorMessage
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
        if !isCurrentModuleEnabled {
            ContentUnavailableView(
                "模块已关闭",
                systemImage: "gearshape",
                description: Text("在左下角设置中启用此模块。")
            )
        } else {
            switch selection {
            case .services:
                ServicesListView(
                    store: serviceStore,
                    errorMessage: $errorMessage,
                    onCreateLaunchAgent: { draft in serviceLaunchDraft = draft }
                )
            case .crontab:
                CronListView(
                    store: crontabStore,
                    searchText: searchText,
                    newCronScope: $newCronScope,
                    showingNewCron: $showingNewCron,
                    errorMessage: $errorMessage
                )
            case .loginItems:
                LoginItemsGuideView()
            case .agents, .none:
                AgentListView(
                    store: store,
                    homebrewStore: homebrewStore,
                    searchText: searchText,
                    newAgentScope: $newAgentScope,
                    showingNewAgent: $showingNewAgent,
                    showingNewFromXml: $showingNewFromXml,
                    errorMessage: $errorMessage
                )
            }
        }
    }

    private var isCurrentModuleEnabled: Bool {
        guard let selection, let module = selection.appModule else { return true }
        return moduleSettings.isEnabled(module)
    }

    private var searchPrompt: LocalizedStringKey {
        if isCrontabView {
            return "搜索命令或计划"
        }
        return "搜索 Label、路径或 formula"
    }

    private func ensureValidSelection() {
        if let current = selection,
           let module = current.appModule,
           moduleSettings.isEnabled(module) {
            return
        }
        selection = moduleSettings.settings.firstEnabledSelection
    }

    private func syncModuleScanning(active: Bool = true) {
        let settings = moduleSettings.settings

        if settings.agents {
            store.refresh()
            store.startWatching()
            homebrewStore.refresh()
        } else {
            store.stopWatching()
        }

        if settings.crontab {
            crontabStore.refresh()
        }

        if settings.services, active {
            serviceStore.startPolling(isActive: true)
        } else {
            serviceStore.stopPolling()
        }
    }

    private func refreshModuleIfNeeded(_ selection: SidebarSelection) {
        guard let module = selection.appModule, moduleSettings.isEnabled(module) else { return }
        switch module {
        case .services:
            serviceStore.refreshNow()
        case .crontab:
            crontabStore.refresh()
        case .loginItems:
            break
        case .agents:
            homebrewStore.refresh()
        }
    }
}

/// Applies `.searchable` when listing launchd agents or crontab jobs.
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
