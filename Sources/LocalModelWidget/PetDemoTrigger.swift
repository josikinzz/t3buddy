import notify
import Foundation
import ModelWidgetCore

/// Listens for the Darwin notification `scripts/demo.sh` posts
/// (`notifyutil -p local.codex.LocalModelWidget.demo`) and runs `action` on the main queue.
/// No network listener: a local notification name is the whole interface.
@MainActor
final class PetDemoTrigger {
    private var token: Int32 = 0

    init(action: @escaping @MainActor () -> Void) {
        let status = notify_register_dispatch(DemoProjects.notificationName, &token, .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        if status != NOTIFY_STATUS_OK { NSLog("T3boii: demo trigger not registered (\(status))") }
    }
}
