import Foundation

/// Magnitude local inference service. The loaded model is read from its OpenAI-compatible
/// `/inference/v1/models`; installed models and stop go through the `magnitude` CLI,
/// which has no JSON output, so `models status` is parsed by header column offsets.
public final class MagnitudeClient: ModelProvider {
    public let id = "magnitude"
    public let displayName = "Magnitude"

    private let baseURL: URL
    private let session: URLSession
    private let executable: URL?

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:10100")!,
        session: URLSession = .shared,
        executable: URL? = MagnitudeClient.locateExecutable()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.executable = executable
    }

    public func installedModels() async throws -> [LocalModel] {
        guard let executable else { return [] }
        let output = try await run(executable, ["models", "status"])
        return MagnitudeStatusTable.parse(output).map { row in
            LocalModel(
                providerID: id,
                name: row.modelID,
                sizeBytes: row.memoryBytes,
                quantization: row.quantization,
                isLoaded: row.isReady
            )
        }
    }

    public func loadedModels() async throws -> [LoadedModel] {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("inference/v1/models"))
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return [] }
        let served = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data).data.map(\.id)
        guard served.isEmpty == false else { return [] }

        let installed = try await installedModels()
        return served.map { modelID in
            LoadedModel(
                providerID: id,
                name: modelID,
                sizeBytes: installed.first { $0.name == modelID }?.sizeBytes ?? 0,
                processor: "Metal"
            )
        }
    }

    public func unloadModel(named name: String) async throws {
        guard let executable else { throw MagnitudeError.cliMissing }
        _ = try await run(executable, ["models", "stop"])
    }

    private func run(_ executable: URL, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = stdout
            process.terminationHandler = { process in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: MagnitudeError.cliFailed(status: process.terminationStatus, output: text))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public static func locateExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/npm-global/bin/magnitude",
            "\(home)/.local/bin/magnitude",
            "/opt/homebrew/bin/magnitude",
            "/usr/local/bin/magnitude",
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

public enum MagnitudeError: Error, LocalizedError, Equatable {
    case cliMissing
    case cliFailed(status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .cliMissing:
            return "The magnitude CLI was not found."
        case let .cliFailed(status, output):
            return "magnitude exited with status \(status): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

public struct MagnitudeStatusRow: Equatable {
    public let modelID: String
    public let memoryBytes: Int64
    public let quantization: String?
    public let isReady: Bool

    public init(modelID: String, memoryBytes: Int64, quantization: String?, isReady: Bool) {
        self.modelID = modelID
        self.memoryBytes = memoryBytes
        self.quantization = quantization
        self.isReady = isReady
    }
}

/// Parses the `magnitude models status` table:
///
///     Local models
///
///     MODEL             MEMORY   CONTEXT  STATUS  MODEL ID
///     Qwen3.8 27B (Q8)  36.9 GB  100K     Ready   qwen3.8-27b:gguf:q8
public enum MagnitudeStatusTable {
    public static func parse(_ output: String) -> [MagnitudeStatusRow] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let headerIndex = lines.firstIndex(where: { $0.hasPrefix("MODEL") && $0.contains("MODEL ID") }) else {
            return []
        }
        let header = lines[headerIndex]
        guard let memoryRange = header.range(of: "MEMORY"),
              let contextRange = header.range(of: "CONTEXT"),
              let statusRange = header.range(of: "STATUS"),
              let idRange = header.range(of: "MODEL ID")
        else { return [] }

        let memoryStart = header.distance(from: header.startIndex, to: memoryRange.lowerBound)
        let contextStart = header.distance(from: header.startIndex, to: contextRange.lowerBound)
        let statusStart = header.distance(from: header.startIndex, to: statusRange.lowerBound)
        let idStart = header.distance(from: header.startIndex, to: idRange.lowerBound)

        return lines[(headerIndex + 1)...].compactMap { line in
            let chars = Array(line)
            guard chars.count > idStart else { return nil }
            let modelID = String(chars[idStart...]).trimmingCharacters(in: .whitespaces)
            guard modelID.isEmpty == false else { return nil }
            let memory = String(chars[memoryStart..<min(contextStart, chars.count)]).trimmingCharacters(in: .whitespaces)
            let status = String(chars[statusStart..<min(idStart, chars.count)]).trimmingCharacters(in: .whitespaces)
            let name = String(chars[..<min(memoryStart, chars.count)])
            return MagnitudeStatusRow(
                modelID: modelID,
                memoryBytes: parseMemory(memory),
                quantization: quantization(in: name),
                isReady: status == "Ready"
            )
        }
    }

    private static func parseMemory(_ text: String) -> Int64 {
        let parts = text.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return 0 }
        let multiplier: Double
        switch parts[1] {
        case "GB": multiplier = 1_000_000_000
        case "MB": multiplier = 1_000_000
        default: return 0
        }
        return Int64(value * multiplier)
    }

    private static func quantization(in name: String) -> String? {
        guard let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close else { return nil }
        return String(name[name.index(after: open)..<close])
    }
}

private struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    let id: String
}
