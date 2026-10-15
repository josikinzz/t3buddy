import Foundation

struct OllamaWireClient {
    private static let providerID = "ollama"
    private static let loadKeepAlive = "1h"
    private static let unloadKeepAlive = "0"

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session
    }

    func installedModels() async throws -> [LocalModel] {
        let response: TagsResponse = try await get(.tags)
        return response.models.compactMap { $0.localModel(providerID: Self.providerID) }
    }

    func loadedModels() async throws -> [LoadedModel] {
        let response: RunningModelsResponse = try await get(.runningModels)
        return response.models.compactMap { $0.loadedModel(providerID: Self.providerID) }
    }

    func loadModel(named name: String) async throws {
        try await generate(modelName: name, keepAlive: Self.loadKeepAlive)
    }

    func unloadModel(named name: String) async throws {
        try await generate(modelName: name, keepAlive: Self.unloadKeepAlive)
    }

    private func get<Response: Decodable>(_ endpoint: OllamaEndpoint) async throws -> Response {
        let (data, response) = try await session.data(from: url(for: endpoint))
        try validate(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func generate(modelName: String, keepAlive: String) async throws {
        var request = URLRequest(url: url(for: .generate))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(modelName: modelName, keepAlive: keepAlive)
        )

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func url(for endpoint: OllamaEndpoint) -> URL {
        endpoint.pathComponents.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= http.statusCode else {
            throw OllamaError.httpStatus(http.statusCode)
        }
    }
}

private enum OllamaEndpoint {
    case tags
    case runningModels
    case generate

    var pathComponents: [String] {
        switch self {
        case .tags:
            return ["api", "tags"]
        case .runningModels:
            return ["api", "ps"]
        case .generate:
            return ["api", "generate"]
        }
    }
}

private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let keepAlive: String

    init(modelName: String, keepAlive: String) {
        self.model = modelName
        self.prompt = ""
        self.stream = false
        self.keepAlive = keepAlive
    }

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case keepAlive = "keep_alive"
    }
}

private struct TagsResponse: Decodable {
    let models: [OllamaTagModel]
}

private struct OllamaTagModel: Decodable {
    let name: String?
    let model: String?
    let size: Int64?
    let details: OllamaModelDetails?

    func localModel(providerID: String) -> LocalModel? {
        guard let name = name ?? model else { return nil }
        return LocalModel(
            providerID: providerID,
            name: name,
            sizeBytes: size ?? 0,
            family: details?.family,
            parameterSize: details?.parameterSize,
            quantization: details?.quantizationLevel
        )
    }
}

private struct OllamaModelDetails: Decodable {
    let family: String?
    let parameterSize: String?
    let quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case family
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

private struct RunningModelsResponse: Decodable {
    let models: [OllamaRunningModel]
}

private struct OllamaRunningModel: Decodable {
    let name: String?
    let model: String?
    let size: Int64?
    let sizeVRAM: Int64?
    let processor: String?
    let expiresAt: String?

    func loadedModel(providerID: String) -> LoadedModel? {
        guard let name = name ?? model else { return nil }
        return LoadedModel(
            providerID: providerID,
            name: name,
            sizeBytes: sizeVRAM ?? size ?? 0,
            processor: processor,
            expiresAt: expiresAt.flatMap(OllamaDateParser.parse)
        )
    }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case size
        case sizeVRAM = "size_vram"
        case processor
        case expiresAt = "expires_at"
    }
}

private enum OllamaDateParser {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) {
            return date
        }

        guard let dot = value.firstIndex(of: ".") else { return nil }
        let prefix = value[..<dot]
        let suffixStart = value[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        guard let suffixStart else { return nil }
        let fraction = value[value.index(after: dot)..<suffixStart].prefix(3)
        let suffix = value[suffixStart...]
        return fractional.date(from: "\(prefix).\(fraction)\(suffix)")
    }
}
