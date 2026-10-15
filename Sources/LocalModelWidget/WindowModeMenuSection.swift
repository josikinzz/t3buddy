import LocalModelWidgetPanel
import SwiftUI

/// The Desktop/Float picker every card's gear menu shows. `mode` is bound to `DashboardRuntime.windowMode`,
/// the one source of truth, so every card shows the same mode and a change in any card applies to the dashboard.
struct WindowModeMenuSection: View {
    @Binding var mode: DesktopPanelWindowMode

    var body: some View {
        Section("Window") {
            Picker("Mode", selection: $mode) {
                ForEach(DesktopPanelWindowMode.allCases) { mode in
                    Label(mode.title, systemImage: mode == .desktop ? "display" : "macwindow")
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)
        }
    }
}
