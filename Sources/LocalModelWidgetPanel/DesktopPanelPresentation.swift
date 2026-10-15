import Foundation
import ModelWidgetCore

public struct DesktopPanelPresentation: Equatable {
    public struct Button: Equatable {
        public let title: String
        public let isEnabled: Bool
    }

    public let title: String
    public let card: LocalModelCardPresentation
    public let statusText: String
    public let quitButton: Button

    @MainActor
    public static func make(
        from viewModel: WidgetViewModel
    ) -> DesktopPanelPresentation {
        DesktopPanelPresentation(
            title: "Local Models",
            card: LocalModelCardPresentation.make(
                activeModel: viewModel.activeModelID,
                isBusy: viewModel.isBusy
            ),
            statusText: viewModel.statusText,
            quitButton: Button(title: "Quit", isEnabled: true)
        )
    }
}
