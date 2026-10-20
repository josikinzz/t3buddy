import Foundation

/// PrismML llama-server fork running in router mode (`bonsai-serve`).
/// Router endpoints: `GET /models`, `POST /models/unload`, `GET /slots`.
public final class BonsaiClient: ModelProvider {
    public let id = "bonsai"
    public let displayName = "Bonsai"

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func installedModels() async throws -> [LocalModel] {
        let response: RouterModelsResponse = try await get("models")
        return response.data.map { $0.localModel(providerID: id) }
    }

    public func loadedModels() async throws -> [LoadedModel] {
        let response: RouterModelsResponse = try await get("models")
        var loaded: [LoadedModel] = []
        for model in response.data where model.isLoaded {
            loaded.append(model.loadedModel(providerID: id, processor: await slotSummary(model: model.id)))
        }
        return loaded
    }

    public func unloadModel(named name: String) async throws {
        try await post("models/unload", model: name)
    }

    /// "Metal · 3/6 slots busy": how many subagent streams are active on this model instance.
    private func slotSummary(model: String) async -> String {
        guard let slots: [RouterSlot] = try? await get("slots", model: model), slots.isEmpty == false else { return "Metal" }
        let busy = slots.filter(\.isProcessing).count
        return "Metal · \(busy)/\(slots.count) slots busy"
    }

    private func get<Response: Decodable>(_ path: String, model: String? = nil) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let model {
            components.queryItems = [URLQueryItem(name: "model", value: model)]
        }
        let (data, response) = try await session.data(from: components.url!)

        try validate(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func post(_ path: String, model: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["model": model])
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= http.statusCode else {
            throw OllamaError.httpStatus(http.statusCode)
        }
    }
}

private struct RouterModelsResponse: Decodable {
    let data: [RouterModel]
}

private struct RouterModel: Decodable {
    let id: String
    let status: RouterStatus?
    let meta: RouterMeta?

    var isLoaded: Bool { status?.value == "loaded" }

    private var sizeBytes: Int64 { meta?.size ?? 0 }

    /// 26_895_998_464 -> "27B"; "PQ2_0 - 2.13 bpw (group 128)" -> "PQ2_0".
    private var parameterSize: String? {
        guard let params = meta?.nParams else { return nil }
        return "\(Int((Double(params) / 1e9).rounded()))B"
    }

    private var quantization: String? {
        meta?.ftype?.split(separator: " ").first.map(String.init)
    }

    func localModel(providerID: String) -> LocalModel {
        LocalModel(
            providerID: providerID,
            name: id,
            sizeBytes: sizeBytes,
            parameterSize: parameterSize,
            quantization: quantization
        )
    }

    func loadedModel(providerID: String, processor: String) -> LoadedModel {
        LoadedModel(providerID: providerID, name: id, sizeBytes: sizeBytes, processor: processor)
    }
}

private struct RouterMeta: Decodable {
    let size: Int64?
    let nParams: Int64?
    let ftype: String?

    private enum CodingKeys: String, CodingKey {
        case size, ftype
        case nParams = "n_params"
    }
}

private struct RouterStatus: Decodable {
    let value: String
}

private struct RouterSlot: Decodable {
    let isProcessing: Bool

    private enum CodingKeys: String, CodingKey {
        case isProcessing = "is_processing"
    }
}
