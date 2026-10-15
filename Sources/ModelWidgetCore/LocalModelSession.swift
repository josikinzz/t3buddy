import Foundation

public enum LocalModelSessionActivity: Equatable {
    case idle
    case loading(LocalModelIdentity)
    case unloading

    public var isBusy: Bool {
        switch self {
        case .idle:
            return false
        case .loading, .unloading:
            return true
        }
    }

    public var pendingModelID: LocalModelIdentity? {
        switch self {
        case let .loading(identity):
            return identity
        case .idle, .unloading:
            return nil
        }
    }
}

public struct LocalModelSessionState: Equatable {
    public static let empty = LocalModelSessionState(
        models: [],
        activeModelID: nil,
        activeLoadedModel: nil,
        activity: .idle
    )

    public let models: [LocalModel]
    public let activeModelID: LocalModelIdentity?
    public let activeLoadedModel: LoadedModel?
    public let activity: LocalModelSessionActivity

    public var pendingModelID: LocalModelIdentity? { activity.pendingModelID }
    public var isBusy: Bool { activity.isBusy }

    public init(
        models: [LocalModel],
        activeModelID: LocalModelIdentity?,
        activeLoadedModel: LoadedModel? = nil,
        activity: LocalModelSessionActivity
    ) {
        self.models = models
        self.activeModelID = activeModelID
        self.activeLoadedModel = activeLoadedModel
        self.activity = activity
    }

    func withActivity(_ activity: LocalModelSessionActivity) -> LocalModelSessionState {
        LocalModelSessionState(
            models: models,
            activeModelID: activeModelID,
            activeLoadedModel: activeLoadedModel,
            activity: activity
        )
    }
}

public struct LocalModelSessionActionResult: Equatable {
    public let state: LocalModelSessionState
    public let didRun: Bool

    public init(state: LocalModelSessionState, didRun: Bool) {
        self.state = state
        self.didRun = didRun
    }
}

@MainActor
public final class LocalModelSession {
    public typealias StateObserver = @MainActor (LocalModelSessionState) -> Void

    public private(set) var state: LocalModelSessionState
    public var onStateChange: StateObserver?

    private let hosts: [ModelHost]

    public init(providers: [ModelProvider]) {
        self.hosts = providers.map(ModelHost.init(provider:))
        self.state = .empty
    }

    @discardableResult
    public func refresh() async throws -> LocalModelSessionState {
        guard state.isBusy == false else {
            return state
        }

        let refreshed = try await reconciledState(activity: .idle)
        setState(refreshed)
        return state
    }

    @discardableResult
    public func activate(_ model: LocalModel) async throws -> LocalModelSessionActionResult {
        try await activateModel(with: model.identity)
    }

    @discardableResult
    public func activateModel(with identity: LocalModelIdentity) async throws -> LocalModelSessionActionResult {
        guard state.isBusy == false, let targetHost = host(for: identity) else {
            return LocalModelSessionActionResult(state: state, didRun: false)
        }

        setState(state.withActivity(.loading(identity)))

        do {
            try await activate(identity, on: targetHost)
            let refreshed = try await reconciledState(activity: .idle)
            setState(refreshed)
            return LocalModelSessionActionResult(state: state, didRun: true)
        } catch {
            setState(state.withActivity(.idle))
            throw error
        }
    }

    @discardableResult
    public func unloadActiveModel() async throws -> LocalModelSessionActionResult {
        guard state.isBusy == false else {
            return LocalModelSessionActionResult(state: state, didRun: false)
        }

        setState(state.withActivity(.unloading))

        do {
            try await unloadLoadedModels()
            let refreshed = try await reconciledState(activity: .idle)
            setState(refreshed)
            return LocalModelSessionActionResult(state: state, didRun: true)
        } catch {
            setState(state.withActivity(.idle))
            throw error
        }
    }

    nonisolated private static func prefersFirstLoadedModel(_ lhs: LoadedModel, _ rhs: LoadedModel) -> Bool {
        switch (lhs.expiresAt, rhs.expiresAt) {
        case let (left?, right?):
            if left != right { return left > right }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return lhs.providerID < rhs.providerID
    }

    private func activate(_ identity: LocalModelIdentity, on targetHost: ModelHost) async throws {
        let loadedModels = try await loadedModels()
        for loadedModel in loadedModels where loadedModel.identity != identity {
            try await loadedModel.host.unloadModel(named: loadedModel.model.name)
        }

        if loadedModels.contains(where: { $0.identity == identity }) == false {
            try await targetHost.loadModel(named: identity.name)
        }
    }

    private func unloadLoadedModels() async throws {
        for loadedModel in try await loadedModels() {
            try await loadedModel.host.unloadModel(named: loadedModel.model.name)
        }
    }

    private func reconciledState(activity: LocalModelSessionActivity) async throws -> LocalModelSessionState {
        let installedModels = try await installedModels()
        let keptLoadedModel = try await normalizeLoadedModels()
        let loadedByIdentity: [LocalModelIdentity: LoadedModel]
        if let keptLoadedModel {
            loadedByIdentity = [keptLoadedModel.identity: keptLoadedModel.model]
        } else {
            loadedByIdentity = [:]
        }
        let annotatedModels = installedModels.map { installedModel in
            annotate(installedModel, with: loadedByIdentity[installedModel.identity])
        }
        let activeModelID = keptLoadedModel?.identity

        return LocalModelSessionState(
            models: modelsWithActiveFirst(annotatedModels, activeModelID: activeModelID),
            activeModelID: activeModelID,
            activeLoadedModel: keptLoadedModel?.model,
            activity: activity
        )
    }

    private func installedModels() async throws -> [LocalModel] {
        var models: [LocalModel] = []
        for host in hosts {
            let installed = try await host.installedModels()
            models.append(contentsOf: installed)
        }
        return models
    }

    private func normalizeLoadedModels() async throws -> HostedLoadedModel? {
        let loadedModels = try await loadedModels()
        guard let keptModel = loadedModels.sorted(by: Self.prefersFirstLoadedModel).first else {
            return nil
        }

        for loadedModel in loadedModels where loadedModel.identity != keptModel.identity {
            try await loadedModel.host.unloadModel(named: loadedModel.model.name)
        }

        return keptModel
    }

    private func loadedModels() async throws -> [HostedLoadedModel] {
        var loadedModels: [HostedLoadedModel] = []
        for host in hosts {
            let loaded = try await host.loadedModels()
            loadedModels.append(contentsOf: loaded.map { HostedLoadedModel(host: host, model: $0) })
        }
        return loadedModels
    }

    private func host(for identity: LocalModelIdentity) -> ModelHost? {
        hosts.first { $0.id == identity.providerID }
    }

    private func annotate(_ installedModel: LocalModel, with loadedModel: LoadedModel?) -> LocalModel {
        var model = installedModel
        guard let loadedModel else {
            model.isLoaded = false
            model.loadedSizeBytes = nil
            model.processor = nil
            model.expiresAt = nil
            return model
        }

        model.isLoaded = true
        model.loadedSizeBytes = loadedModel.sizeBytes
        model.processor = loadedModel.processor
        model.expiresAt = loadedModel.expiresAt
        return model
    }

    private func modelsWithActiveFirst(
        _ models: [LocalModel],
        activeModelID: LocalModelIdentity?
    ) -> [LocalModel] {
        guard let activeModelID, let activeIndex = models.firstIndex(where: { $0.identity == activeModelID }) else {
            return models
        }

        var orderedModels = models
        let activeModel = orderedModels.remove(at: activeIndex)
        orderedModels.insert(activeModel, at: 0)
        return orderedModels
    }

    private func setState(_ state: LocalModelSessionState) {
        self.state = state
        onStateChange?(state)
    }

    nonisolated private static func prefersFirstLoadedModel(_ lhs: HostedLoadedModel, _ rhs: HostedLoadedModel) -> Bool {
        prefersFirstLoadedModel(lhs.model, rhs.model)
    }
}

/// A provider whose server is not running contributes no models instead of failing the whole refresh.
private struct ModelHost {
    let provider: ModelProvider

    var id: String { provider.id }

    private static let unreachableCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .timedOut,
    ]

    private func tolerateUnreachable<T>(_ body: () async throws -> [T]) async throws -> [T] {
        do {
            return try await body()
        } catch let error as URLError where Self.unreachableCodes.contains(error.code) {
            return []
        }
    }

    func installedModels() async throws -> [LocalModel] {
        let models = try await tolerateUnreachable { try await provider.installedModels() }
        return models.map { model in
            guard model.providerID != provider.id else { return model }
            return LocalModel(
                providerID: provider.id,
                name: model.name,
                sizeBytes: model.sizeBytes,
                family: model.family,
                parameterSize: model.parameterSize,
                quantization: model.quantization,
                isLoaded: model.isLoaded,
                loadedSizeBytes: model.loadedSizeBytes,
                processor: model.processor,
                expiresAt: model.expiresAt
            )
        }
    }

    func loadedModels() async throws -> [LoadedModel] {
        let models = try await tolerateUnreachable { try await provider.loadedModels() }
        return models.map { model in
            guard model.providerID != provider.id else { return model }
            return LoadedModel(
                providerID: provider.id,
                name: model.name,
                sizeBytes: model.sizeBytes,
                processor: model.processor,
                expiresAt: model.expiresAt
            )
        }
    }

    func loadModel(named name: String) async throws {
        try await provider.loadModel(named: name)
    }

    func unloadModel(named name: String) async throws {
        try await provider.unloadModel(named: name)
    }
}

private struct HostedLoadedModel {
    let host: ModelHost
    let model: LoadedModel

    var identity: LocalModelIdentity { model.identity }
}
