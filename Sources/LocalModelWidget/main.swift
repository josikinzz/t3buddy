import AppKit
import ModelWidgetCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dashboard: DashboardRuntime?
    private var idleHider: IdleAppHider?
    private var petLayer: PetLayer?
    private var orbit: OrbitRuntime?
    private var demoTrigger: PetDemoTrigger?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dashboard = DashboardRuntime(
            model: DesktopPanelRuntime(),
            subscriptions: SubscriptionPanelRuntime(),
            process: ProcessPanelRuntime(),
            tokenUsage: TokenUsageRuntime()
        )
        self.dashboard = dashboard
        dashboard.show()
        dashboard.startRefreshing()

        let idleHider = IdleAppHider()
        self.idleHider = idleHider
        idleHider.start()
        let petLayer = PetLayer()
        self.petLayer = petLayer
        petLayer.start()
        let orbit = OrbitRuntime { [weak petLayer] json in petLayer?.updateOrbit(json: json) }
        self.orbit = orbit
        orbit.start()
        // scripts/demo.sh: T3boii plays his scripted demo with the owner's real projects;
        // `scripts/demo.sh limit [provider]` fakes a rate limit on the real orbit.
        demoTrigger = PetDemoTrigger(action: { [weak orbit, weak petLayer] in
            Task { @MainActor in petLayer?.startDemo(payloadJSON: await orbit?.demoPayload()) }
        }, limit: { [weak petLayer] provider in
            petLayer?.startLimitDemo(provider: provider)
        })
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
