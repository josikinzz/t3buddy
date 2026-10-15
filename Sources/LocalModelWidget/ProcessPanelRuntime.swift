import AppKit
import Combine
import LocalModelWidgetPanel
import ModelWidgetCore
import SwiftUI

enum ProcessPanelIntent: Equatable {
    case forceQuit(Int32)
    case quit
}

@MainActor
final class ProcessPanelRuntime: ObservableObject {
    @Published private(set) var presentation: ProcessPanelPresentation

    private let viewModel: ProcessHUDViewModel
    private let refreshInterval: TimeInterval
    private var refreshTimer: Timer?
    private var viewModelChanges: AnyCancellable?

    init(
        viewModel: ProcessHUDViewModel? = nil,
        refreshInterval: TimeInterval = DesktopPanelLayout.refreshInterval
    ) {
        let viewModel = viewModel ?? ProcessHUDViewModel(
            processSampler: SystemProcessSampler(),
            memorySampler: SystemMemorySampler(),
            terminator: SystemProcessTerminator()
        )
        self.viewModel = viewModel
        self.refreshInterval = refreshInterval
        self.presentation = ProcessPanelPresentation.make(from: viewModel)
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

    func send(_ intent: ProcessPanelIntent) {
        switch intent {
        case let .forceQuit(processID):
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.viewModel.forceQuit(processID: processID)
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
        presentation = ProcessPanelPresentation.make(from: viewModel)
    }
}
