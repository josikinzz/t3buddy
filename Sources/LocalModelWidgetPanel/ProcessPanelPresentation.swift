import Foundation
import ModelWidgetCore

public struct ProcessPanelPresentation: Equatable {
    public struct Button: Equatable {
        public let title: String
        public let isEnabled: Bool
    }

    public struct Memory: Equatable {
        public let title: String
        public let summary: String
        public let usedFraction: Double
    }

    public struct ProportionSegment: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let fraction: Double
        public let colorIndex: Int?
        public let accessibilityLabel: String
    }

    public struct ProcessRow: Identifiable, Equatable {
        public let id: Int32
        public let title: String
        public let subtitle: String
        public let memoryText: String
        public let percentText: String
        public let colorIndex: Int
        public let isTerminating: Bool
        public let forceQuitButton: Button
        public let accessibilityLabel: String
        public let accessibilityHint: String
    }

    public let title: String
    public let memory: Memory
    public let proportionSegments: [ProportionSegment]
    public let processRows: [ProcessRow]
    public let statusText: String
    public let quitButton: Button

    @MainActor
    public static func make(
        from viewModel: ProcessHUDViewModel
    ) -> ProcessPanelPresentation {
        let displayedProcesses = Array(viewModel.processes.prefix(12))
        let rows = displayedProcesses.enumerated().map { index, process in
            let isCurrentProcess = process.processID == viewModel.currentProcessID
            let isTerminating = viewModel.terminatingProcessIDs.contains(process.processID)
            let percentText = percent(process.residentMemoryBytes, of: viewModel.memory.totalBytes)
            let label = process.displayLabel

            return ProcessRow(
                id: process.processID,
                title: label,
                subtitle: subtitle(for: process),
                memoryText: byteCount(process.residentMemoryBytes),
                percentText: percentText,
                colorIndex: index,
                isTerminating: isTerminating,
                forceQuitButton: Button(
                    title: isTerminating ? "Quitting" : "Force Quit",
                    isEnabled: isCurrentProcess == false && isTerminating == false
                ),
                accessibilityLabel: "\(label), \(percentText) of unified memory",
                accessibilityHint: isCurrentProcess ? "The widget cannot force quit itself." : "Force quits \(label)."
            )
        }

        return ProcessPanelPresentation(
            title: "Process Memory",
            memory: Memory(
                title: "Unified Memory",
                summary: memorySummary(viewModel.memory),
                usedFraction: viewModel.memory.usedFraction
            ),
            proportionSegments: segments(for: displayedProcesses, rows: rows, memory: viewModel.memory),
            processRows: rows,
            statusText: viewModel.statusText,
            quitButton: Button(title: "Quit", isEnabled: true)
        )
    }

    private static func segments(
        for processes: [RunningProcess],
        rows: [ProcessRow],
        memory: MemorySnapshot
    ) -> [ProportionSegment] {
        var topBytes: UInt64 = 0
        let processSegments = zip(processes, rows).map { process, row -> ProportionSegment in
            let bytes = process.residentMemoryBytes
            topBytes = topBytes.addingReportingOverflow(bytes).overflow ? memory.usedBytes : min(memory.usedBytes, topBytes + bytes)
            return ProportionSegment(
                id: "process-\(row.id)",
                title: row.title,
                fraction: fraction(bytes, of: memory.totalBytes),
                colorIndex: row.colorIndex,
                accessibilityLabel: "\(row.title), \(row.percentText) of unified memory"
            )
        }

        let otherUsedBytes = memory.usedBytes > topBytes ? memory.usedBytes - topBytes : 0
        guard otherUsedBytes > 0 else {
            return processSegments
        }

        return processSegments + [
            ProportionSegment(
                id: "other-used",
                title: "Other used",
                fraction: fraction(otherUsedBytes, of: memory.totalBytes),
                colorIndex: nil,
                accessibilityLabel: "Other used memory, \(percent(otherUsedBytes, of: memory.totalBytes)) of unified memory"
            )
        ]
    }

    private static func subtitle(for process: RunningProcess) -> String {
        if let executablePath = process.executablePath, executablePath.isEmpty == false {
            return "PID \(process.processID) - \(executablePath)"
        }
        return "PID \(process.processID)"
    }

    private static func memorySummary(_ memory: MemorySnapshot) -> String {
        // The view model's placeholder snapshot (1 byte total) reads "0% Zero KB / 1 byte"; show nothing until sampled.
        guard memory.totalBytes > 1 else { return "" }
        return "\(percent(memory.usedBytes, of: memory.totalBytes)) \(byteCount(memory.usedBytes)) / \(byteCount(memory.totalBytes))"
    }

    private static func fraction(_ bytes: UInt64, of totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(bytes) / Double(totalBytes)))
    }

    private static func percent(_ bytes: UInt64, of totalBytes: UInt64) -> String {
        fraction(bytes, of: totalBytes).formatted(.percent.precision(.fractionLength(0)))
    }

    private static func byteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(min(bytes, UInt64(Int64.max))),
            countStyle: .memory
        )
    }
}
