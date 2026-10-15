import AppKit
import LocalModelWidgetPanel
import WebKit

/// T3boii's layer: a borderless, transparent window over the whole dashboard
/// screen that hosts the bundled three.js page in a `WKWebView`. The window
/// ignores the mouse everywhere except over the hit rects the page reports,
/// so clicks beside him reach the desktop and the cards.
@MainActor
final class PetLayer: NSObject, WKNavigationDelegate {
    static let messageHandlerName = "t3boii"
    /// `defaults write local.codex.LocalModelWidget petInspectable -bool true` opens the page to Web Inspector.
    static let inspectableDefaultsKey = "petInspectable"
    /// The gear menu's "T3boii sounds" toggle; unset means on.
    static let soundsDefaultsKey = "petSoundsEnabled"
    static func soundsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: soundsDefaultsKey) as? Bool ?? true
    }

    private var panel: PetPanel?
    private var webView: PetWebView?
    private var pageDirectory: URL?
    private var hitRects: [PetHitRect] = []
    private var catchingMouse = false
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var screensAsleep = false
    private var sessionInactive = false
    private var pageReady = false
    /// The last orbit snapshot JSON, resent whenever the page (re)loads.
    private var orbitJSON: String?
    private let defaults = UserDefaults.standard

    func start() {
        guard panel == nil else { return }
        guard let directory = Self.locatePageDirectory() else {
            NSLog("T3boii: no Pet page in the app bundle or the repo's Resources/Pet")
            return
        }
        guard let frame = Self.currentLayerFrame() else {
            NSLog("T3boii: no screen to float on")
            return
        }
        pageDirectory = directory

        let panel = PetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = PetLayerGeometry.windowLevel
        panel.collectionBehavior = PetLayerGeometry.collectionBehavior
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none

        let webView = PetWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: makeConfiguration(layerSize: frame.size))
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = self
        webView.isInspectable = defaults.bool(forKey: Self.inspectableDefaultsKey)
        panel.contentView = webView
        panel.setFrame(frame, display: false)
        self.panel = panel
        self.webView = webView

        observeSystem()
        monitorMouse()
        panel.orderFrontRegardless()
        loadPage()
    }

    // MARK: Page

    private func makeConfiguration(layerSize: CGSize) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // ES modules and the .glb load from file:// only with file access on.
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.suppressesIncrementalRendering = true
        // Mouse input reaches the page through the bridge, not as user gestures, so let his
        // sound effects play without one.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(PetMessageProxy(layer: self), name: Self.messageHandlerName)
        installConfigScript(in: configuration.userContentController, layerSize: layerSize)
        return configuration
    }

    /// Hands the page its starting position before any page script runs.
    private func installConfigScript(in controller: WKUserContentController, layerSize: CGSize) {
        controller.removeAllUserScripts()
        let stored = defaults.dictionary(forKey: PetLayerGeometry.positionDefaultsKey)
        let position = PetLayerGeometry.restoredPosition(stored: stored, layerSize: layerSize)
        let config: [String: Any] = ["position": PetLayerGeometry.encodePosition(position), "reducedMotion": Self.reduceMotion, "muted": !Self.soundsEnabled(defaults)]
        guard let data = try? JSONSerialization.data(withJSONObject: config), let json = String(data: data, encoding: .utf8) else { return }
        controller.addUserScript(WKUserScript(source: "window.__t3boiiConfig = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func loadPage() {
        // The page is bundled; block every network scheme so it can never fetch.
        // Content-blocker regexes take no disjunctions, so one rule per scheme.
        let rules = "[" + ["^https?://", "^wss?://", "^ftp://"].map {
            #"{"trigger":{"url-filter":"\#($0)"},"action":{"type":"block"}}"#
        }.joined(separator: ",") + "]"
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "T3boiiOffline", encodedContentRuleList: rules) { [weak self] list, error in
            MainActor.assumeIsolated {
                guard let self, let webView = self.webView, let directory = self.pageDirectory else { return }
                if let list {
                    webView.configuration.userContentController.add(list)
                } else {
                    NSLog("T3boii: offline rule list failed to compile: \(String(describing: error))")
                }
                webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
            }
        }
    }

    private static func locatePageDirectory() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Pet", isDirectory: true))
        }
        // Unbundled dev runs: the repo's Resources/Pet, three levels above this file.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(repo.appendingPathComponent("Resources/Pet", isDirectory: true))
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }

    private static func currentLayerFrame() -> CGRect? {
        PetLayerGeometry.layerFrame(mainScreen: NSScreen.main?.frame, screens: NSScreen.screens.map(\.frame))
    }

    /// Hands the page a new orbit snapshot (JSON for `window.t3boii.update`).
    func updateOrbit(json: String) {
        orbitJSON = json
        callPage("window.t3boii.update(\(json))")
    }

    /// Plays T3boii's scripted demo (demo.js) with the owner's real projects; nil lets the page
    /// borrow faces from the last real snapshot.
    func startDemo(payloadJSON: String?) {
        callPage("window.t3boii.demo?.(\(payloadJSON ?? "null"))")
    }

    /// macOS Reduce Motion: the page swaps flights for fades and slows the orbit and idle motion.
    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var sentMuted: Bool?

    /// Mirrors the "T3boii sounds" toggle onto the page.
    private func updateMuted(force: Bool = false) {
        let muted = !Self.soundsEnabled(defaults)
        guard force || muted != sentMuted else { return }
        sentMuted = muted
        callPage("window.t3boii.setMuted(\(muted))")
    }

    private func updateReducedMotion() {
        callPage("window.t3boii.setReducedMotion(\(Self.reduceMotion))")
    }

    private func callPage(_ script: String) {
        guard pageReady else { return }
        webView?.evaluateJavaScript("window.t3boii && \(script)") { _, error in
            if let error { NSLog("T3boii: page call failed: \(error.localizedDescription)") }
        }
    }

    // MARK: Messages from the page

    fileprivate func receive(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "hitRegions":
            if let rects = try? PetLayerGeometry.hitRects(fromMessage: body) {
                hitRects = rects
                updateMouseCapture()
            }
        case "position":
            guard let position = PetLayerGeometry.decodePosition(body), let size = panel?.frame.size else { return }
            let clamped = PetLayerGeometry.clampedPosition(position, layerSize: size)
            defaults.set(PetLayerGeometry.encodePosition(clamped), forKey: PetLayerGeometry.positionDefaultsKey)
        case "ready":
            if body["ok"] as? Bool == true {
                pageReady = true
                updatePause()
                updateReducedMotion()
                updateMuted(force: true)
                if let orbitJSON { callPage("window.t3boii.update(\(orbitJSON))") }
            } else {
                NSLog("T3boii: page failed to start: \(body["error"] ?? "unknown error")")
            }
        case "openLink":
            // Only T3's own local web UI; the page never asks for anything else.
            if let link = body["url"] as? String, let url = URL(string: link), PetLayerGeometry.isLocalThreadLink(url) {
                NSWorkspace.shared.open(url)
            }
        case "error":
            NSLog("T3boii: page error: \(body["message"] ?? "unknown")")
        default:
            break
        }
    }

    // MARK: Click-through

    private func monitorMouse() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let releasing = event.type == .leftMouseUp
            let moved = event.type == .mouseMoved
            MainActor.assumeIsolated {
                self?.updateMouseCapture(releasing: releasing)
                if moved { self?.forwardHover(); self?.forwardPointer() }
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let releasing = event.type == .leftMouseUp
            let moved = event.type == .mouseMoved
            MainActor.assumeIsolated {
                self?.updateMouseCapture(releasing: releasing)
                if moved { self?.forwardHover(); self?.forwardPointer() }
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Tells the page where the mouse is while it moves over T3boii, so stroking him pets him.
    /// The panel never becomes key, so the web view cannot be relied on for mouse-moved events.
    private var hoveringPet = false

    private func forwardHover() {
        guard let panel else { return }
        let inside = PetLayerGeometry.catchesMouse(at: NSEvent.mouseLocation, layerFrame: panel.frame, rects: hitRects)
        guard inside || hoveringPet else { return }
        hoveringPet = inside
        if inside {
            let point = PetLayerGeometry.pagePoint(screenPoint: NSEvent.mouseLocation, layerFrame: panel.frame)
            callPage("window.t3boii.hover(\(Double(point.x)), \(Double(point.y)))")
        } else {
            callPage("window.t3boii.hover(null, null)")
        }
    }

    /// Tells the page where the mouse is anywhere on the layer's screen, so his eyes can follow
    /// it while it moves. At most ~20 times a second, and not while he is paused.
    private var lastPointerForward = Date.distantPast

    private func forwardPointer() {
        guard let panel, !screensAsleep, !sessionInactive else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPointerForward) >= 0.05 else { return }
        lastPointerForward = now
        let mouse = NSEvent.mouseLocation
        guard panel.frame.contains(mouse) else { return }
        let point = PetLayerGeometry.pagePoint(screenPoint: mouse, layerFrame: panel.frame)
        callPage("window.t3boii.pointer?.(\(Double(point.x)), \(Double(point.y)))")
    }

    private func updateMouseCapture(releasing: Bool = false) {
        guard let panel else { return }
        let inside = PetLayerGeometry.catchesMouse(at: NSEvent.mouseLocation, layerFrame: panel.frame, rects: hitRects)
        let buttonDown = !releasing && NSEvent.pressedMouseButtons & 1 != 0
        let catches = PetLayerGeometry.catchesMouse(insideHitRegion: inside, buttonDown: buttonDown, catchingNow: catchingMouse)
        guard catches != catchingMouse else { return }
        catchingMouse = catches
        panel.ignoresMouseEvents = !catches
    }

    // MARK: Sleep, session, screens

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true; $0.updatePause() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false; $0.updatePause() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true; $0.updatePause() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false; $0.updatePause() }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { $0.updateReducedMotion() }
        observe(.default, NSWindow.didChangeOcclusionStateNotification) { $0.updatePause() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.refitToScreen() }
        observe(.default, UserDefaults.didChangeNotification) { $0.updateMuted() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (PetLayer) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func updatePause() {
        let visible = panel?.occlusionState.contains(.visible) ?? false
        let paused = screensAsleep || sessionInactive || !visible
        callPage("window.t3boii.setPaused(\(paused))")
    }

    private func refitToScreen() {
        guard let panel, let frame = Self.currentLayerFrame(), frame != panel.frame else { return }
        // The page clamps his position on resize and reports new hit rects.
        panel.setFrame(frame, display: true)
        updateMouseCapture()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("T3boii: web content process ended; reloading")
        pageReady = false
        hitRects = []
        updateMouseCapture()
        installConfigScript(in: webView.configuration.userContentController, layerSize: panel?.frame.size ?? webView.bounds.size)
        webView.reload()
    }
}

/// Never key, never main, and never pulled under the menu bar.
private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Takes the first click while the app is in the background, so a drag on
/// T3boii starts without activating anything first.
private final class PetWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// `WKUserContentController` retains its handlers; this keeps the layer out of that cycle.
private final class PetMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var layer: PetLayer?

    init(layer: PetLayer) {
        self.layer = layer
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { layer?.receive(body) }
    }
}
