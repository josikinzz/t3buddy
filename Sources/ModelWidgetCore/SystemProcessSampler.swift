import AppKit
import Darwin
import Foundation

public struct SystemProcessSampler: ProcessSampling {
    public init() {}

    public func sample() throws -> [RunningProcess] {
        Self.allProcessIDs().compactMap(Self.process(for:)).sorted {
            if $0.residentMemoryBytes == $1.residentMemoryBytes {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.residentMemoryBytes > $1.residentMemoryBytes
        }
    }

    private static func allProcessIDs() -> [pid_t] {
        let initialByteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard initialByteCount > 0 else { return [] }

        let initialPIDCount = Int(initialByteCount) / MemoryLayout<pid_t>.stride
        var processIDs = [pid_t](repeating: 0, count: initialPIDCount + 128)
        let filledByteCount = processIDs.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.stride)
            )
        }
        guard filledByteCount > 0 else { return [] }

        let filledPIDCount = Int(filledByteCount) / MemoryLayout<pid_t>.stride
        return processIDs
            .prefix(filledPIDCount)
            .filter { $0 > 0 }
    }

    private static func process(for processID: pid_t) -> RunningProcess? {
        var taskInfo = proc_taskinfo()
        let taskInfoByteCount = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            proc_pidinfo(
                processID,
                PROC_PIDTASKINFO,
                0,
                pointer,
                Int32(MemoryLayout<proc_taskinfo>.stride)
            )
        }
        guard taskInfoByteCount == Int32(MemoryLayout<proc_taskinfo>.stride),
              taskInfo.pti_resident_size > 0
        else {
            return nil
        }

        let path = executablePath(for: processID)
        guard let name = processName(for: processID, executablePath: path), name.isEmpty == false else {
            return nil
        }

        return RunningProcess(
            processID: processID,
            parentProcessID: parentProcessID(for: processID),
            name: name,
            executablePath: path,
            workingDirectory: workingDirectory(for: processID),
            residentMemoryBytes: UInt64(taskInfo.pti_resident_size)
        )
    }

    private static func parentProcessID(for processID: pid_t) -> pid_t? {
        var bsdInfo = proc_bsdinfo()
        let bsdInfoByteCount = withUnsafeMutablePointer(to: &bsdInfo) { pointer in
            proc_pidinfo(
                processID,
                PROC_PIDTBSDINFO,
                0,
                pointer,
                Int32(MemoryLayout<proc_bsdinfo>.stride)
            )
        }
        guard bsdInfoByteCount == Int32(MemoryLayout<proc_bsdinfo>.stride) else {
            return nil
        }
        return Int32(bsdInfo.pbi_ppid)
    }

    private static func executablePath(for processID: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLength = pathBuffer.withUnsafeMutableBufferPointer { buffer in
            proc_pidpath(processID, buffer.baseAddress, UInt32(buffer.count))
        }
        guard pathLength > 0 else {
            return nil
        }
        return String(cString: pathBuffer)
    }

    private static func workingDirectory(for processID: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let pathInfoByteCount = withUnsafeMutablePointer(to: &pathInfo) { pointer in
            proc_pidinfo(
                processID,
                PROC_PIDVNODEPATHINFO,
                0,
                pointer,
                Int32(MemoryLayout<proc_vnodepathinfo>.stride)
            )
        }
        guard pathInfoByteCount == Int32(MemoryLayout<proc_vnodepathinfo>.stride) else {
            return nil
        }
        let path = withUnsafeBytes(of: pathInfo.pvi_cdir.vip_path) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    private static func processName(for processID: pid_t, executablePath: String?) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: 1024)
        let nameLength = nameBuffer.withUnsafeMutableBufferPointer { buffer in
            proc_name(processID, buffer.baseAddress, UInt32(buffer.count))
        }
        let name = nameLength > 0
            ? String(cString: nameBuffer)
            : executablePath.map { URL(fileURLWithPath: $0).lastPathComponent }
        return name.map { ProcessLabel.processName(name: $0, executablePath: executablePath) }
    }
}

public struct SystemProcessTerminator: ProcessTerminating {
    public init() {}

    public func terminate(processID: Int32) throws {
        guard processID > 1 else {
            throw ProcessTerminatorError.invalidProcessID(processID)
        }

        if let runningApplication = NSRunningApplication(processIdentifier: processID),
           runningApplication.forceTerminate() {
            return
        }

        let result = Darwin.kill(processID, SIGTERM)
        guard result == 0 else {
            throw ProcessTerminatorError.signalFailed(processID: processID, errnoCode: errno)
        }
    }
}

public enum ProcessTerminatorError: Error, LocalizedError, Equatable {
    case invalidProcessID(Int32)
    case signalFailed(processID: Int32, errnoCode: Int32)

    public var errorDescription: String? {
        switch self {
        case let .invalidProcessID(processID):
            return "Cannot force quit system PID \(processID)."
        case let .signalFailed(processID, errnoCode):
            return "Could not force quit PID \(processID): \(String(cString: strerror(errnoCode)))."
        }
    }
}
