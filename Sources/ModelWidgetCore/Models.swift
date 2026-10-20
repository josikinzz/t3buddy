import Foundation

public struct LocalModel: Identifiable, Equatable, Hashable {
    public var id: String { identity.rawValue }
    public var identity: LocalModelIdentity { LocalModelIdentity(providerID: providerID, name: name) }

    public let providerID: String
    public let name: String
    public let sizeBytes: Int64
    public let family: String?
    public let parameterSize: String?
    public let quantization: String?
    public var isLoaded: Bool
    public var loadedSizeBytes: Int64?
    public var processor: String?
    public var expiresAt: Date?

    public init(
        providerID: String,
        name: String,
        sizeBytes: Int64,
        family: String? = nil,
        parameterSize: String? = nil,
        quantization: String? = nil,
        isLoaded: Bool = false,
        loadedSizeBytes: Int64? = nil,
        processor: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.providerID = providerID
        self.name = name
        self.sizeBytes = sizeBytes
        self.family = family
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.isLoaded = isLoaded
        self.loadedSizeBytes = loadedSizeBytes
        self.processor = processor
        self.expiresAt = expiresAt
    }
}

public struct LoadedModel: Equatable, Hashable {
    public var identity: LocalModelIdentity { LocalModelIdentity(providerID: providerID, name: name) }

    public let providerID: String
    public let name: String
    public let sizeBytes: Int64
    public let processor: String?
    public let expiresAt: Date?

    public init(
        providerID: String,
        name: String,
        sizeBytes: Int64,
        processor: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.providerID = providerID
        self.name = name
        self.sizeBytes = sizeBytes
        self.processor = processor
        self.expiresAt = expiresAt
    }
}

public struct LocalModelIdentity: Equatable, Hashable, CustomStringConvertible {
    public let providerID: String
    public let name: String

    public var rawValue: String { "\(providerID):\(name)" }
    public var description: String { rawValue }

    public init(providerID: String, name: String) {
        self.providerID = providerID
        self.name = name
    }
}

public struct MemorySnapshot: Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    public init(totalBytes: UInt64, usedBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
    }
}

public protocol ModelProvider {
    var id: String { get }
    var displayName: String { get }

    func installedModels() async throws -> [LocalModel]
    func loadedModels() async throws -> [LoadedModel]
    func unloadModel(named name: String) async throws
}

public protocol MemorySampling {
    func sample() throws -> MemorySnapshot
}
