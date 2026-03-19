import SwiftUI

@main
struct UsageKitApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var historyService = UsageHistoryService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var codexService = CodexUsageService()
    @StateObject private var codexHistoryService = UsageHistoryService(subdirectory: "codex")
    @StateObject private var codexNotificationService = NotificationService()
    @StateObject private var appUpdater = AppUpdater()
    @AppStorage("claudeEnabled") private var claudeEnabled = true
    @AppStorage("codexEnabled") private var codexEnabled = true

    var body: some Scene {
        MenuBarExtra(isInserted: $claudeEnabled) {
            PopoverView(
                service: service,
                historyService: historyService,
                notificationService: notificationService,
                appUpdater: appUpdater
            )
        } label: {
            Image(nsImage: service.isAuthenticated
                ? renderIcon(pct5h: 1.0 - service.pct5h, pct7d: 1.0 - service.pct7d)
                : renderUnauthenticatedIcon()
            )
                .task {
                    if service.isAuthenticated && !UserDefaults.standard.bool(forKey: "setupComplete") {
                        UserDefaults.standard.set(true, forKey: "setupComplete")
                    }
                    historyService.loadHistory()
                    service.historyService = historyService
                    service.notificationService = notificationService
                    service.startPolling()
                }
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $codexEnabled) {
            CodexPopoverView(
                service: codexService,
                historyService: codexHistoryService,
                notificationService: codexNotificationService,
                appUpdater: appUpdater
            )
        } label: {
            Image(nsImage: codexMenuBarImage)
                .task {
                    if codexService.isAuthenticated && !UserDefaults.standard.bool(forKey: "codexSetupComplete") {
                        UserDefaults.standard.set(true, forKey: "codexSetupComplete")
                    }
                    codexHistoryService.loadHistory()
                    codexService.historyService = codexHistoryService
                    codexService.notificationService = codexNotificationService
                    codexService.startPolling()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowContent(
                service: service,
                notificationService: notificationService,
                appUpdater: appUpdater,
                claudeEnabled: $claudeEnabled,
                codexEnabled: $codexEnabled
            )
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }

    private var codexMenuBarImage: NSImage {
        guard codexService.isAuthenticated,
              let pctPrimary = codexService.pctPrimary,
              let pctSecondary = codexService.pctSecondary else {
            return renderCodexUnauthenticatedIcon()
        }

        return renderCodexIcon(
            pctPrimary: 1.0 - pctPrimary,
            pctSecondary: 1.0 - pctSecondary,
            primaryLabel: "5h",
            secondaryLabel: "7d"
        )
    }
}
