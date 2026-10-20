import AppKit
import ModelWidgetCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dashboard: DashboardRuntime?
    private var idleHider: IdleAppHider?
    private var petLayer: PetLayer?
    private var feed: FeedSupervisor?
    private var feedClient: FeedClient?
    private var connectObserver: NSObjectProtocol?
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
        let feed = FeedSupervisor()
        self.feed = feed
        feed.start()
        let feedClient = FeedClient(deliver: { [weak petLayer] json, state in petLayer?.feed(json: json, state: state) }, helperHung: { [weak feed] in feed?.replaceHung() })
        self.feedClient = feedClient
        Task { await feedClient.start() }
        connectObserver = NotificationCenter.default.addObserver(forName: FeedClient.connectT3Notification, object: nil, queue: .main) { _ in
            Task { NSLog("T3boii: Connect T3 \(await feedClient.connectT3() ? "succeeded" : "failed")") }
        }
        // scripts/demo.sh: T3boii plays his scripted demo with the owner's real projects;
        // `scripts/demo.sh limit [provider]` fakes a rate limit on the real orbit.
        demoTrigger = PetDemoTrigger(action: { [weak petLayer] in
            Task { @MainActor in petLayer?.startDemo(payloadJSON: await feedClient.demoPayload()) }
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
