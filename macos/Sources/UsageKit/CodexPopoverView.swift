import SwiftUI

struct CodexPopoverView: View {
    @ObservedObject var service: CodexUsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex Usage")
                .font(.headline)

            if !service.isAuthenticated {
                signInView
            } else {
                usageView
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear { dismissOtherMenuBarPanels() }
    }

    @ViewBuilder
    private var signInView: some View {
        Text("Sign in to view your Codex usage.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        if service.isAwaitingCode {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for browser sign-in to complete…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Button("Sign in with Codex") {
            service.startOAuthFlow()
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .disabled(service.isAwaitingCode)

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        Divider()
        HStack {
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var usageView: some View {
        CodexUsageRow(
            label: "5-Hour Window",
            pct: service.usage?.rateLimit?.primaryWindow?.usedPercent,
            resetDate: service.usage?.primaryResetsAt
        )

        CodexUsageRow(
            label: "7-Day Window",
            pct: service.usage?.rateLimit?.secondaryWindow?.usedPercent,
            resetDate: service.usage?.secondaryResetsAt
        )

        if let credits = service.usage?.credits {
            Divider()
            CodexCreditsView(credits: credits)
        }

        Divider()
        UsageChartView(
            historyService: historyService,
            primaryLabel: service.usage?.primaryWindowLabel ?? service.primaryLabel,
            secondaryLabel: service.usage?.secondaryWindowLabel ?? service.secondaryLabel
        )

        if let error = service.lastError {
            Divider()
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        if let updaterError = appUpdater.lastError {
            Divider()
            Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        Divider()

        HStack(spacing: 12) {
            if let updated = service.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }

        HStack(spacing: 12) {
            SettingsLink {
                Text("Settings")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
            Button("Refresh") {
                Task { await service.fetchUsage() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Sign Out") {
                service.signOut()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CodexUsageRow: View {
    let label: String
    let pct: Int?
    let resetDate: Date?

    private var remaining: Double {
        1.0 - Double(pct ?? 0) / 100.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(percentageText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            ProgressView(value: remaining, total: 1.0)
                .tint(.green)
            if let resetDate {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentageText: String {
        guard pct != nil else { return "—" }
        return "\(Int(round(remaining * 100)))%"
    }
}

private struct CodexCreditsView: View {
    let credits: CodexCredits

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Credits")
                .font(.subheadline)

            HStack {
                Text(credits.hasCredits ? "Available" : "Unavailable")
                    .font(.caption)
                Spacer()
                if credits.unlimited {
                    Text("Unlimited")
                        .font(.caption)
                        .monospacedDigit()
                } else if let balance = credits.balance, !balance.isEmpty {
                    Text(balance)
                        .font(.caption)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}


