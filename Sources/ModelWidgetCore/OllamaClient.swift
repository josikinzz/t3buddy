import Foundation
import Darwin.Mach

public final class OllamaClient: ModelProvider {
    public let id = "ollama"
    public let displayName = "Ollama"
    private let wireClient: OllamaWireClient

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        session: URLSession = .shared
    ) {
        self.wireClient = OllamaWireClient(baseURL: baseURL, session: session)
    }

    public func installedModels() async throws -> [LocalModel] {
        try await wireClient.installedModels()
    }

    public func loadedModels() async throws -> [LoadedModel] {
        try await wireClient.loadedModels()
    }

    public func loadModel(named name: String) async throws {
        try await wireClient.loadModel(named: name)
    }

    public func unloadModel(named name: String) async throws {
        try await wireClient.unloadModel(named: name)
    }
}

public struct SystemMemorySampler: MemorySampling {
    public init() {}

    public func sample() throws -> MemorySnapshot {
        let total = ProcessInfo.processInfo.physicalMemory
        var pageSize: vm_size_t = 0
        let pageSizeResult = host_page_size(mach_host_self(), &pageSize)
        guard pageSizeResult == KERN_SUCCESS else {
            throw MemorySamplerError.hostPageSizeFailed(pageSizeResult)
        }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MemorySamplerError.hostStatisticsFailed(result)
        }

        let usedBytes = Self.activityMonitorUsedBytes(
            totalBytes: total,
            pageSize: UInt64(pageSize),
            internalPages: UInt64(stats.internal_page_count),
            wiredPages: UInt64(stats.wire_count),
            compressorPages: UInt64(stats.compressor_page_count)
        )
        return MemorySnapshot(totalBytes: total, usedBytes: usedBytes)
    }

    public static func activityMonitorUsedBytes(
        totalBytes: UInt64,
        pageSize: UInt64,
        internalPages: UInt64,
        wiredPages: UInt64,
        compressorPages: UInt64
    ) -> UInt64 {
        let usedPages = internalPages + wiredPages + compressorPages
        let (usedBytes, overflowed) = usedPages.multipliedReportingOverflow(by: pageSize)
        guard overflowed == false else { return totalBytes }
        return min(totalBytes, usedBytes)
    }
}

public enum OllamaError: Error, LocalizedError, Equatable {
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case let .httpStatus(status):
            return "Ollama returned HTTP \(status)."
        }
    }
}

public enum MemorySamplerError: Error, LocalizedError, Equatable {
    case hostPageSizeFailed(kern_return_t)
    case hostStatisticsFailed(kern_return_t)

    public var errorDescription: String? {
        switch self {
        case let .hostPageSizeFailed(code):
            return "Could not read memory page size (\(code))."
        case let .hostStatisticsFailed(code):
            return "Could not read memory statistics (\(code))."
        }
    }
}
