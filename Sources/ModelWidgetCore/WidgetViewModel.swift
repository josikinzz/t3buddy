import Combine
import Foundation

@MainActor
public final class WidgetViewModel: ObservableObject {
    @Published public private(set) var models: [LocalModel] = []
    @Published public private(set) var memory: MemorySnapshot = .init(totalBytes: 1, usedBytes: 0)
    @Published public private(set) var activeModelID: LocalModelIdentity?
    @Published public private(set) var statusText: String = "Idle"
    @Published public private(set) var isBusy = false
    @Published public private(set) var pendingModelID: LocalModelIdentity?

    private let session: LocalModelSession
    private let memorySampler: MemorySampling

    public init(providers: [ModelProvider], memorySampler: MemorySampling) {
        self.session = LocalModelSession(providers: providers)
        self.memorySampler = memorySampler
        self.session.onStateChange = { [weak self] state in
            self?.applySessionState(state)
        }
        applySessionState(session.state)
    }

    public func refresh() async {
        do {
            let state = try await session.refresh()
            applySessionState(state)
            memory = try memorySampler.sample()
            if state.isBusy == false {
                statusText = updatedStatus()
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    public func activate(_ model: LocalModel) async {
        guard model.identity != activeModelID else {
            statusText = "Loaded \(model.name)"
            return
        }

        do {
            let result = try await session.activate(model)
            guard result.didRun else { return }
            memory = try memorySampler.sample()
            statusText = result.state.activeModelID == model.identity ? "Loaded \(model.name)" : updatedStatus()
        } catch {
            statusText = error.localizedDescription
        }
    }

    public func unloadActiveModel() async {
        do {
            let result = try await session.unloadActiveModel()
            guard result.didRun else { return }
            memory = try memorySampler.sample()
            statusText = "Unloaded"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func applySessionState(_ state: LocalModelSessionState) {
        models = state.models
        activeModelID = state.activeModelID
        isBusy = state.isBusy
        pendingModelID = state.pendingModelID

        switch state.activity {
        case .idle:
            break
        case let .loading(identity):
            statusText = "Loading \(identity.name)"
        case .unloading:
            statusText = "Unloading"
        }
    }

    private func updatedStatus(at date: Date = Date()) -> String {
        "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}
