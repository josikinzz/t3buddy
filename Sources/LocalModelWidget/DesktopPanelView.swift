import AppKit
import LocalModelWidgetPanel
import SwiftUI

struct DesktopPanelView: View {
    @ObservedObject var runtime: DesktopPanelRuntime
    @Binding var windowMode: DesktopPanelWindowMode

    var body: some View {
        let presentation = runtime.presentation

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(presentation.title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer(minLength: 8)

                DesktopPanelSettingsMenu(
                    presentation: presentation,
                    windowMode: $windowMode,
                    onQuit: { runtime.send(.quit) }
                )
            }

            LocalModelCardRow(
                card: presentation.card,
                onUnload: { runtime.send(.unloadActiveModel) }
            )
        }
        .padding(12)
        .frame(width: DesktopPanelLayout.panelWidth, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct LocalModelCardRow: View {
    let card: LocalModelCardPresentation
    let onUnload: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: card.loaded == nil ? "circle" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(card.loaded == nil ? Color.secondary.opacity(0.58) : Color.green)
                .frame(width: 14)
                .accessibilityHidden(true)

            if let loaded = card.loaded {
                Text(loaded.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(loaded.hostName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else {
                Text(card.line)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let unloadButton = card.unloadButton {
                Button(unloadButton.title, action: onUnload)
                    .font(.system(size: 10, weight: .medium))
                    .controlSize(.small)
                    .disabled(unloadButton.isEnabled == false)
                    .accessibilityLabel(unloadButton.accessibilityLabel)
                    .help(unloadButton.accessibilityLabel)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.line)
    }

    private var rowBackground: Color {
        card.loaded == nil ? Color.primary.opacity(0.055) : Color.green.opacity(0.14)
    }
}

private struct DesktopPanelSettingsMenu: View {
    let presentation: DesktopPanelPresentation
    let windowMode: Binding<DesktopPanelWindowMode>
    let onQuit: () -> Void

    var body: some View {
        Menu {
            WindowModeMenuSection(mode: windowMode)

            Section {
                Button {
                    BenchmarkDoc.open()
                } label: {
                    Label("Model Benchmarks…", systemImage: "chart.bar.doc.horizontal")
                }
            }

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
