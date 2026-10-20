import LocalModelWidgetPanel
import ModelWidgetCore
import SwiftUI

struct SubscriptionPanelView: View {
    @ObservedObject var runtime: SubscriptionPanelRuntime
    @Binding var windowMode: DesktopPanelWindowMode
    @AppStorage(PetLayer.soundsDefaultsKey) private var petSounds = true
    var body: some View {
        // The card grows to fit its rows; the dashboard grid gives it its natural height.
        panel.fixedSize(horizontal: false, vertical: true)
            // Without a cached or fresh read the card is only its header.
            .masonryReady(runtime.updated != nil)
    }
    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subscription Usage")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Menu {
                    Button("Refresh now") { runtime.refresh() }.disabled(runtime.refreshing)
                    WindowModeMenuSection(mode: $windowMode)
                    IdleHideMenuItems()
                    Toggle("T3boii sounds", isOn: $petSounds)
                    Button("Connect T3") { NotificationCenter.default.post(name: FeedClient.connectT3Notification, object: nil) }
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold)).frame(width: 24, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Widget settings")
            }
            VStack(alignment: .leading, spacing: 8) {
                SubscriptionRows(rows: runtime.shownRows)
                if let message = runtime.message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(footer(now: context.date)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12).frame(width: DesktopPanelLayout.panelWidth)
        .background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private func footer(now: Date) -> String {
        if runtime.refreshing { return "Checking…" }
        guard let updated = runtime.updated else { return "Waiting for first check" }
        let minutes = max(0, Int(now.timeIntervalSince(updated) / 60))
        return "Checked \(minutes == 0 ? "just now" : "\(minutes)m ago") · refreshes every 5m"
    }
}

/// Usable accounts first; emails stay pixelated until clicked. Reveal state is view-only, keyed by row id.
private struct SubscriptionRows: View {
    var rows: [SubscriptionUsage]
    @State private var revealed: [String: UUID] = [:]
    var body: some View {
        ForEach(SubscriptionUsageReader.usableFirst(rows)) { row in
            SubscriptionRow(row: row, emailRevealed: revealed[row.id] != nil) { toggle(row.id) }
        }
    }
    private func toggle(_ id: String) {
        guard revealed[id] == nil else { revealed[id] = nil; return }
        let token = UUID()
        revealed[id] = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(EmailMask.revealSeconds))
            if revealed[id] == token { revealed[id] = nil }
        }
    }
}

private struct SubscriptionRow: View {
    var row: SubscriptionUsage
    var emailRevealed: Bool
    var toggleEmail: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(row.provider).font(.system(size: 12, weight: .semibold))
                Spacer()
                // A plan id like "pro" is capitalised; a display label like Grok Bot's keeps its own casing.
                if !row.plan.isEmpty { Text(row.plan == row.plan.lowercased() ? row.plan.capitalized : row.plan).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
            }
            if !row.email.isEmpty {
                Button(action: toggleEmail) {
                    Group {
                        if emailRevealed {
                            Text(row.email).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                        } else {
                            PixelatedText(text: row.email, fontSize: 10)
                        }
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).clipped().contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(emailRevealed ? "Click to hide email" : "Click to show email for \(Int(EmailMask.revealSeconds)) s")
                .accessibilityLabel(emailRevealed ? row.email : "Hidden \(row.provider) email")
                .accessibilityHint(emailRevealed ? "Hides the email" : "Shows the email for \(Int(EmailMask.revealSeconds)) seconds")
            }
            ForEach(row.windows) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(window.title)
                        Spacer()
                        Text("\(Int(window.used.rounded()))% used").monospacedDigit()
                    }.font(.system(size: 10, weight: .medium))
                    UsageBar(fraction: window.used / 100, color: window.used >= 95 ? .orange : ProviderPalette.color(forProvider: row.provider))
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(resetText(window.reset, now: context.date)).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            if let note = row.note {
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let error = row.error {
                Text(error + (row.checked != nil ? " · stale data" : ""))
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
        }.padding(9).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .help(row.checked.map { "Last successful check: " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "No successful check yet")
    }
    private func resetText(_ reset: Date?, now: Date) -> String {
        guard let reset else { return "No active reset reported" }
        let seconds = Int(reset.timeIntervalSince(now))
        guard seconds > 0 else { return "Reset due · waiting for next check" }
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        let countdown = days > 0 ? "\(days)d \(hours)h" : hours > 0 ? "\(hours)h \(minutes)m" : "\(max(1, minutes))m"
        return "Resets \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · in \(countdown)"
    }
}

private struct UsageBar: View {
    var fraction: Double
    var color: Color
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(color.opacity(0.78)).frame(width: geometry.size.width * min(1, max(0, fraction)))
        }.frame(height: 5).background(Color.primary.opacity(0.09), in: Capsule()).clipShape(Capsule())
        .accessibilityLabel("Usage").accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
