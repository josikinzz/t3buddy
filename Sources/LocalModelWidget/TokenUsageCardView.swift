import Charts
import LocalModelWidgetPanel
import ModelWidgetCore
import SwiftUI

/// Token usage over 7 days: today's fresh total as one large number, a stacked area of fresh input plus output
/// per provider, and cache reads in their own small chart so they never flatten the main one.
struct TokenUsageCardView: View {
    @ObservedObject var runtime: TokenUsageRuntime
    @Binding var windowMode: DesktopPanelWindowMode

    var body: some View {
        let presentation = runtime.presentation

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Tokens")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                TokenUsageSettingsMenu(runtime: runtime, windowMode: $windowMode)
            }

            // The one display-size numeral DESIGN.md allows: today's total, read from across the room.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.todayText)
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.todayTotal) tokens today, fresh input plus output")

            if presentation.legend.isEmpty {
                Text(runtime.updated == nil ? "Reading session logs…" : "No token usage in the last 7 days")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                TokenUsageLegend(legend: presentation.legend)
                TokenFreshChart(presentation: presentation)
                    .frame(height: 120)
                TokenCacheChart(presentation: presentation)
            }
        }
        .padding(12)
        .frame(width: DesktopPanelLayout.panelWidth, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Before the first scan the card shows a short "Reading session logs…" placeholder.
        .masonryReady(runtime.updated != nil)
    }

    private var statusText: String {
        if runtime.refreshing && runtime.updated == nil { return "Reading logs…" }
        guard let updated = runtime.updated else { return "Last 7 days" }
        return "7 days · \(updated.formatted(date: .omitted, time: .shortened))"
    }
}

private struct TokenUsageSettingsMenu: View {
    @ObservedObject var runtime: TokenUsageRuntime
    @Binding var windowMode: DesktopPanelWindowMode

    var body: some View {
        Menu {
            WindowModeMenuSection(mode: $windowMode)

            Section {
                Button {
                    runtime.refresh()
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(runtime.refreshing)
            }

            Section {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Token settings")
        .help("Token settings")
    }
}

private struct TokenUsageLegend: View {
    let legend: [TokenUsagePresentation.ProviderTotal]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(legend) { entry in
                HStack(spacing: 4) {
                    Circle()
                        .fill(ProviderPalette.color(for: entry.provider))
                        .frame(width: 7, height: 7)
                    Text(entry.provider.displayName)
                        .font(.system(size: 10, weight: .medium))
                    Text(TokenUsagePresentation.compact(entry.today))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .help("\(entry.provider.displayName): \(TokenUsagePresentation.compact(entry.today)) today, \(TokenUsagePresentation.compact(entry.week)) in 7 days")
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TokenFreshChart: View {
    let presentation: TokenUsagePresentation

    var body: some View {
        let providers = presentation.legend.map(\.provider)
        Chart(presentation.freshPoints.filter { providers.contains($0.provider) }) { point in
            AreaMark(
                x: .value("Hour", point.hour),
                y: .value("Tokens", point.tokens),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Provider", point.provider.displayName))
            .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(
            domain: providers.map(\.displayName),
            range: providers.map(ProviderPalette.color(for:))
        )
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain(presentation))
        .chartXAxis { dayAxis() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(TokenUsagePresentation.compact(tokens))
                    }
                }
            }
        }
    }
}

/// Cache reads on their own scale, drawn as a line so they read apart from the stacked area.
private struct TokenCacheChart: View {
    let presentation: TokenUsagePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cache reads · \(TokenUsagePresentation.compact(presentation.cacheWeekTotal)) in 7 days")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Chart(presentation.cachePoints) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Cache reads", point.tokens)
                )
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .interpolationMethod(.monotone)
            }
            .chartXScale(domain: xDomain(presentation))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TokenUsagePresentation.compact(tokens))
                        }
                    }
                }
            }
            .frame(height: 34)
        }
    }
}

private func xDomain(_ presentation: TokenUsagePresentation) -> ClosedRange<Date> {
    let first = presentation.hours.first ?? Date()
    let last = presentation.hours.last ?? first
    return first...last
}

@AxisContentBuilder
private func dayAxis() -> some AxisContent {
    AxisMarks(values: .stride(by: .day)) { _ in
        AxisGridLine()
        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
    }
}
