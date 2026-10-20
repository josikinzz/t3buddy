import Combine
import Foundation

@MainActor
public final class WidgetViewModel: ObservableObject {
    @Published public private(set) var models: [LocalModel] = []
    @Published public private(set) var activeModelID: LocalModelIdentity?
    @Published public private(set) var statusText: String = "Idle"
    @Published public private(set) var isBusy = false

    private let session: LocalModelSession

    public init(providers: [ModelProvider]) {
        self.session = LocalModelSession(providers: providers)
        self.session.onStateChange = { [weak self] state in
            self?.applySessionState(state)
        }
        applySessionState(session.state)
    }

    public func refresh() async {
        do {
            let state = try await session.refresh()
            applySessionState(state)
            if state.isBusy == false {
                statusText = updatedStatus()
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    public func unloadActiveModel() async {
        do {
            let result = try await session.unloadActiveModel()
            guard result.didRun else { return }
            statusText = "Unloaded"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func applySessionState(_ state: LocalModelSessionState) {
        models = state.models
        activeModelID = state.activeModelID
        isBusy = state.isBusy

        switch state.activity {
        case .idle:
            break
        case .unloading:
            statusText = "Unloading"
        }
    }

    private func updatedStatus(at date: Date = Date()) -> String {
        "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}
