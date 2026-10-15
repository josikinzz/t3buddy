import AppKit
import Combine
import LocalModelWidgetPanel
import ModelWidgetCore
import SwiftUI

enum DesktopPanelIntent: Equatable {
    case unloadActiveModel
    case quit
}

@MainActor
final class DesktopPanelRuntime: ObservableObject {
    @Published private(set) var presentation: DesktopPanelPresentation

    private let viewModel: WidgetViewModel
    private let refreshInterval: TimeInterval
    private var refreshTimer: Timer?
    private var viewModelChanges: AnyCancellable?

    init(
        viewModel: WidgetViewModel? = nil,
        refreshInterval: TimeInterval = DesktopPanelLayout.refreshInterval
    ) {
        let viewModel = viewModel ?? WidgetViewModel(
            providers: [BonsaiClient(), MagnitudeClient(), OllamaClient()],
            memorySampler: SystemMemorySampler()
        )
        self.viewModel = viewModel
        self.refreshInterval = refreshInterval
        self.presentation = DesktopPanelPresentation.make(from: viewModel)
        self.viewModelChanges = viewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePresentation()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func startRefreshing() {
        refreshTimer?.invalidate()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func send(_ intent: DesktopPanelIntent) {
        switch intent {
        case .unloadActiveModel:
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.viewModel.unloadActiveModel()
                self.updatePresentation()
            }

        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    private func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.refresh()
            self.updatePresentation()
        }
    }

    private func updatePresentation() {
        presentation = DesktopPanelPresentation.make(from: viewModel)
    }
}
