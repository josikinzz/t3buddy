import LocalModelWidgetPanel
import SwiftUI

struct ProcessPanelView: View {
    @ObservedObject var runtime: ProcessPanelRuntime
    @Binding var windowMode: DesktopPanelWindowMode

    var body: some View {
        let presentation = runtime.presentation

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(presentation.title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer(minLength: 8)

                ProcessPanelSettingsMenu(
                    presentation: presentation,
                    windowMode: $windowMode,
                    onQuit: { runtime.send(.quit) }
                )
            }

            ProcessMemoryMeter(
                memory: presentation.memory,
                segments: presentation.proportionSegments
            )

            // At most 12 rows (see `ProcessPanelPresentation`), so the card shows them all at its natural height.
            VStack(spacing: 6) {
                ForEach(presentation.processRows) { row in
                    ProcessPanelRow(row: row) {
                        runtime.send(.forceQuit(row.id))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: DesktopPanelLayout.panelWidth, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Until the first sample lands the card is only its header and meter.
        .masonryReady(presentation.processRows.isEmpty == false)
    }
}

private struct ProcessPanelSettingsMenu: View {
    let presentation: ProcessPanelPresentation
    let windowMode: Binding<DesktopPanelWindowMode>
    let onQuit: () -> Void

    var body: some View {
        Menu {
            WindowModeMenuSection(mode: windowMode)

            Section {
                Button(action: onQuit) {
                    Label(presentation.quitButton.title, systemImage: "power")
                }
                .disabled(presentation.quitButton.isEnabled == false)
            }

            Section {
                Button {} label: {
                    Label(presentation.statusText, systemImage: "clock")
                }
                .disabled(true)
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
        .accessibilityLabel("Widget settings")
        .help("Widget settings")
    }
}

private struct ProcessMemoryMeter: View {
    let memory: ProcessPanelPresentation.Memory
    let segments: [ProcessPanelPresentation.ProportionSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(memory.summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 6)
            }

            ProcessProportionBar(segments: segments)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(memory.title)
    }
}

private struct ProcessProportionBar: View {
    let segments: [ProcessPanelPresentation.ProportionSegment]

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(totalWidth: proxy.size.width)

            HStack(spacing: 1) {
                ForEach(Array(zip(segments, widths)), id: \.0.id) { segment, width in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: segment))
                        .frame(width: width)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Color.primary.opacity(0.09), in: Capsule())
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Process memory proportions")
        .accessibilityValue(segments.map(\.accessibilityLabel).joined(separator: ", "))
    }

    private func segmentWidths(totalWidth: CGFloat) -> [CGFloat] {
        var remainingWidth = totalWidth
        return segments.map { segment in
            guard remainingWidth > 0 else { return 0 }
            let proposedWidth = totalWidth * segment.fraction
            let width = min(remainingWidth, proposedWidth)
            remainingWidth -= width
            return width
        }
    }

    private func color(for segment: ProcessPanelPresentation.ProportionSegment) -> Color {
        guard let colorIndex = segment.colorIndex else {
            return Color.secondary.opacity(0.34)
        }
        return processColor(colorIndex)
    }
}

private struct ProcessPanelRow: View {
    let row: ProcessPanelPresentation.ProcessRow
    let onForceQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(processColor(row.colorIndex))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(row.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Text(row.memoryText)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 60, alignment: .trailing)

            Text(row.percentText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 28, alignment: .trailing)

            Button {
                onForceQuit()
            } label: {
                forceQuitIcon
            }
            .buttonStyle(.borderless)
            .disabled(row.forceQuitButton.isEnabled == false)
            .accessibilityLabel(forceQuitAccessibilityLabel)
            .accessibilityHint(row.accessibilityHint)
            .help("Force Quit \(row.title)")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .help(row.subtitle)
    }

    @ViewBuilder
    private var forceQuitIcon: some View {
        if row.isTerminating {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "xmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(row.forceQuitButton.isEnabled ? Color.red.opacity(0.86) : Color.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
    }

    private var forceQuitAccessibilityLabel: String {
        row.isTerminating ? "Quitting \(row.title)" : "Force Quit \(row.title)"
    }

    private var rowBackground: Color {
        row.isTerminating ? Color.red.opacity(0.10) : Color.primary.opacity(0.055)
    }
}

private func processColor(_ index: Int) -> Color {
    let palette: [Color] = [
        .blue.opacity(0.78),
        .orange.opacity(0.78),
        .purple.opacity(0.78),
        .green.opacity(0.78),
        .pink.opacity(0.72),
        .teal.opacity(0.78),
        .indigo.opacity(0.74),
        .yellow.opacity(0.82),
        .mint.opacity(0.78),
        .cyan.opacity(0.78),
        .brown.opacity(0.68),
        .red.opacity(0.72)
    ]
    return palette[index % palette.count]
}
