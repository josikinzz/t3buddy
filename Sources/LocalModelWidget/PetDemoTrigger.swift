import notify
import Foundation
import ModelWidgetCore

/// Listens for the Darwin notifications `scripts/demo.sh` posts and runs the matching action on the
/// main queue: `local.codex.LocalModelWidget.demo` plays the demo; `….demo.limit[.<provider>]`
/// fakes a rate limit (nil provider: the page picks one).
/// No network listener: local notification names are the whole interface.
@MainActor
final class PetDemoTrigger {
    private var tokens: [Int32] = []

    init(action: @escaping @MainActor () -> Void, limit: @escaping @MainActor (String?) -> Void) {
        register(DemoProjects.notificationName, action)
        register(DemoProjects.limitNotificationName) { limit(nil) }
        for provider in DemoProjects.limitProviders {
            register(DemoProjects.limitNotificationName + "." + provider) { limit(provider) }
        }
    }

    private func register(_ name: String, _ action: @escaping @MainActor () -> Void) {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        if status == NOTIFY_STATUS_OK { tokens.append(token) } else { NSLog("T3boii: demo trigger \(name) not registered (\(status))") }
    }
}
