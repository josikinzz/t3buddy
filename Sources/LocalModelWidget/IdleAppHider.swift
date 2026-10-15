import AppKit
import CoreGraphics
import Darwin
import IOKit.pwr_mgt
import ModelWidgetCore
import OSLog

/// Hides regular apps after the Mac has had no keyboard or mouse input for the chosen minutes,
/// leaving the desktop panels as a dashboard. Hiding needs no Accessibility permission.
@MainActor
final class IdleAppHider {
    private var policy = IdleHidePolicy(minutes: IdleHidePolicy.defaultMinutes)
    private var timer: Timer?
    private let logger = Logger(subsystem: "local.codex.LocalModelWidget", category: "IdleHide")
    private var loggedMinutes: Int?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        policy.minutes = IdleHidePolicy.minutes(fromDefaults: UserDefaults.standard.object(forKey: IdleHidePolicy.defaultsKey))
        if policy.minutes != loggedMinutes {
            logger.notice("Idle hide threshold: \(self.policy.minutes) min (0 = never)")
            loggedMinutes = policy.minutes
        }
        // ~0 is kCGAnyInputEventType: the most recent keyboard, mouse, or trackpad event.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        switch policy.evaluate(idleSeconds: idle, displayHeldBy: Self.displayAssertionOwners()) {
        case .wait:
            break
        case .skip(let reason):
            if policy.shouldReportSkip(reason) { logger.notice("Idle hide skipped after \(Int(idle))s idle: \(reason, privacy: .public)") }
        case .hide:
            let own = NSRunningApplication.current.processIdentifier
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isHidden }
            for app in apps { app.hide() }
            logger.notice("Idle hide: hid \(apps.count) apps after \(Int(idle))s idle")
            let record = IdleHideRecord(date: Date(), appCount: apps.count)
            UserDefaults.standard.set(record.encodedString(), forKey: IdleHideRecord.defaultsKey)
        }
    }

    /// Process names holding a "keep the display awake" power assertion, e.g. a video player or Zoom.
    private static func displayAssertionOwners() -> [String] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        let displayTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        return byProcess.compactMap { pid, assertions in
            guard assertions.contains(where: { displayTypes.contains($0["AssertType"] as? String ?? "") }) else { return nil }
            var name = [CChar](repeating: 0, count: 256)
            return proc_name(pid.int32Value, &name, UInt32(name.count)) > 0 ? String(cString: name) : nil
        }
    }
}
