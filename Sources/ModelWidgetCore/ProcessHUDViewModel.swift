import Combine
import Foundation

public struct RunningProcess: Identifiable, Equatable, Hashable {
    public var id: Int32 { processID }

    public let processID: Int32
    public let parentProcessID: Int32?
    public let name: String
    public let executablePath: String?
    public let workingDirectory: String?
    public let residentMemoryBytes: UInt64

    public init(
        processID: Int32,
        parentProcessID: Int32? = nil,
        name: String,
        executablePath: String? = nil,
        workingDirectory: String? = nil,
        residentMemoryBytes: UInt64
    ) {
        self.processID = processID
        self.parentProcessID = parentProcessID
        self.name = name
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.residentMemoryBytes = residentMemoryBytes
    }
}

public protocol ProcessSampling {
    func sample() throws -> [RunningProcess]
}

public protocol ProcessTerminating {
    func terminate(processID: Int32) throws
}

@MainActor
public final class ProcessHUDViewModel: ObservableObject {
    @Published public private(set) var processes: [RunningProcess] = []
    @Published public private(set) var memory: MemorySnapshot = .init(totalBytes: 1, usedBytes: 0)
    @Published public private(set) var statusText: String = "Idle"
    @Published public private(set) var terminatingProcessIDs: Set<Int32> = []

    public let currentProcessID: Int32

    private let processSampler: ProcessSampling
    private let memorySampler: MemorySampling
    private let terminator: ProcessTerminating

    public init(
        processSampler: ProcessSampling,
        memorySampler: MemorySampling,
        terminator: ProcessTerminating,
        currentProcessID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.processSampler = processSampler
        self.memorySampler = memorySampler
        self.terminator = terminator
        self.currentProcessID = currentProcessID
    }

    public func refresh() async {
        do {
            memory = try memorySampler.sample()
            processes = try processSampler.sample().sorted {
                if $0.residentMemoryBytes == $1.residentMemoryBytes {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.residentMemoryBytes > $1.residentMemoryBytes
            }
            statusText = updatedStatus()
        } catch {
            statusText = error.localizedDescription
        }
    }

    public func forceQuit(processID: Int32) async {
        guard processID != currentProcessID else {
            statusText = "The widget cannot force quit itself."
            return
        }
        guard terminatingProcessIDs.contains(processID) == false else { return }
        let processName = processes.first(where: { $0.processID == processID })?.name ?? "PID \(processID)"

        terminatingProcessIDs.insert(processID)
        defer {
            terminatingProcessIDs.remove(processID)
        }

        do {
            try terminator.terminate(processID: processID)
            await refresh()
            statusText = "Force quit requested for \(processName)"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func updatedStatus(at date: Date = Date()) -> String {
        "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}

extension RunningProcess {
    /// Row label for the process memory card, e.g. `node · docs-site`.
    public var displayLabel: String {
        ProcessLabel.label(name: name, cwd: workingDirectory)
    }
}
