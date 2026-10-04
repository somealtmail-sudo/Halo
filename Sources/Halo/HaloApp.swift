import AppKit
import SwiftUI
import Combine
import HaloCore

@main
enum HaloMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private var settings: NSWindow?
    private var terminationSignal: DispatchSourceSignal?
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            // terminateLater can enter an AppKit modal loop. Leave the dispatch
            // callback first so asynchronous shutdown can still reach the UI loop.
            RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
        source.resume()
        terminationSignal = source
        if CommandLine.arguments.contains("--geometry-diagnostics") {
            let controller = IslandController(model: model, present: false, monitorPointer: false)
            print(controller.diagnosticDescription())
            controller.stop()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--waveform-diagnostics") {
            model.waveform.reconcile(active: true, enabled: true, count: 8, reduced: false)
            Task { @MainActor in
                var peak: Float = 0
                var changes = 0
                var previous = model.waveform.levels
                for _ in 0..<120 {
                    try? await Task.sleep(for: .milliseconds(50))
                    let levels = model.waveform.levels
                    peak = max(peak, levels.max() ?? 0)
                    if levels != previous { changes += 1 }
                    previous = levels
                }
                print("Waveform: \(model.waveform.status); peak: \(peak); changed frames: \(changes)")
                model.waveform.stop()
                print("Capture released; flat: \(model.waveform.levels.allSatisfy { $0 == 0 })")
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--media-diagnostics") {
            model.media.start()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let media = model.media
                print("Media: \(media.adapterStatus); backend: \(media.backend.rawValue); session: \(media.hasSession); artwork bytes: \(media.snapshot.artworkData?.count ?? 0); decoded artwork: \(media.artwork != nil); preview: \(model.preview)")
                media.stop()
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            let audio = AudioDetector.read()
            print("CoreAudio available: \(audio.available); active output processes: \(AudioDetector.resolve(audio.processes).map(\.name).joined(separator: ", "))")
            for screen in NSScreen.screens {
                print("Display: \(screen.localizedName); frame: \(screen.frame); safe top: \(screen.safeAreaInsets.top); left: \(String(describing: screen.auxiliaryTopLeftArea)); right: \(String(describing: screen.auxiliaryTopRightArea))")
            }
            NSApp.terminate(nil)
            return
        }
        if !CommandLine.arguments.contains("--hover-diagnostics"), activateExistingInstance() {
            NSApp.terminate(nil)
            return
        }
        model.onSettings = { [weak self] in self?.openSettings() }
        island = IslandController(model: model)
        installMenu()
        model.start()
        if CommandLine.arguments.contains("--preview") { model.preview = true; model.pinned = true; model.setExpanded(true) }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--settings") {
            openSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        model.stop()
        island?.stop()
        // Keep the main run loop alive until helper cleanup has completed. A
        // delayed kill scheduled during willTerminate cannot outlive the app.
        model.media.shutdownForTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop(); island?.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }

    private func activateExistingInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current
        // Launch Services normally reuses an app, but direct execution or a second
        // downloaded copy can bypass it. Prefer the oldest registered instance;
        // ordering also prevents simultaneous launches from dismissing each other.
        let first = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
            .min {
                let left = $0.launchDate ?? .distantFuture
                let right = $1.launchDate ?? .distantFuture
                return left == right ? $0.processIdentifier < $1.processIdentifier : left < right
            }
        guard let first, first.processIdentifier != current.processIdentifier else { return false }
        first.activate(options: [.activateAllWindows])
        return true
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.inset.filled", accessibilityDescription: "Halo")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Halo", action: #selector(openIsland), keyEquivalent: "h").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reconnect Media", action: #selector(reconnectMedia), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Halo", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
        // Accessory apps still need an application menu for standard keyboard actions.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Halo")
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Quit Halo", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }
    @objc private func openIsland() { model.showIsland = true; model.pinned = true; model.setExpanded(true) }
    @objc private func reconnectMedia() { model.media.reconnect() }
    @objc private func quit() { NSApp.terminate(nil) }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settings else { return }
        // Recreate on demand instead of retaining the entire SwiftUI settings tree.
        window.contentView = nil
        settings = nil
    }

    @objc func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.delegate = self
            window.title = "Halo"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.backgroundColor = .windowBackgroundColor
            let hosting = NSHostingView(rootView: SettingsView(model: model).ignoresSafeArea())
            hosting.safeAreaRegions = []
            hosting.sizingOptions = []
            window.contentView = hosting
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // AppKit's usual visible-frame constraint avoids the menu bar/camera safe area.
    // This borderless surface intentionally occupies the physical top screen edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class IslandController {
    private let model: AppModel
    private let panel: IslandPanel
    private let present: Bool
    private let monitorPointer: Bool
    private var fallbackTracking: Timer?
    private var exitTimer: Timer?
    private var scheduledExitDeadline: TimeInterval?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hover = IslandHover()
    private var expansionObserver: AnyCancellable?
    private var pinObservers: Set<AnyCancellable> = []
    private var geometryObserver: AnyCancellable?
    private var geometryRefreshPending = false
    private var stopped = false
    private var sleeping = false
    private var displaySleeping = false
    private let hoverDiagnosticsEnabled = CommandLine.arguments.contains("--hover-diagnostics")
    private var hoverDiagnosticsStartedAt: TimeInterval?
    private var lastHoverDiagnosticState: String?
    private var lastHoverDiagnosticTime: TimeInterval = 0
    private var hoverDiagnosticLines = 0
    private var observers: [NSObjectProtocol] = []
    private var screen: NSScreen?

    init(model: AppModel, present: Bool = true, monitorPointer: Bool = true) {
        self.model = model
        self.present = present
        self.monitorPointer = monitorPointer
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: model.panelWidth, height: model.panelHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if hoverDiagnosticsEnabled { hoverDiagnosticsStartedAt = ProcessInfo.processInfo.systemUptime }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: IslandView(model: model).ignoresSafeArea())
        // NSScreen's physical notch is represented in this window's safe area. Halo deliberately
        // draws behind it: AppKit and SwiftUI must agree that the content begins at screen.maxY.
        hosting.safeAreaRegions = []
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        expansionObserver = model.$expanded.sink { [weak self] expanded in
            guard let self else { return }
            self.hover.expansionChanged(to: expanded, at: ProcessInfo.processInfo.systemUptime)
            self.scheduleExit()
        }
        model.$pinned.merge(with: model.$dropTargeted).sink { [weak self] _ in
            // @Published emits before assignment; evaluate after the updated pin is visible.
            Task { @MainActor in self?.trackPointer(source: "pin") }
        }.store(in: &pinObservers)
        geometryObserver = model.objectWillChange.sink { [weak self] in
            guard let self, !self.geometryRefreshPending else { return }
            self.geometryRefreshPending = true
            Task { @MainActor in
                self.geometryRefreshPending = false
                guard !self.stopped, let screen = self.screen else { return }
                // Media/timer activity can widen the compact wings. Avoid republishing
                // display metadata while responding to an ObservableObject change.
                let frame = self.geometry(on: screen).panel
                if self.panel.frame != frame { self.panel.setFrame(frame, display: true) }
                self.trackPointer(source: "model")
            }
        }
        model.onLayoutChange = { [weak self] in self?.layout() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.layout() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.sleeping = true
                self.reconcileFallbackTracking()
                self.trackPointer(source: "sleep")
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.sleeping = false
                self.layout()
                self.model.media.reconnect()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.displaySleeping = true
                self.reconcileFallbackTracking()
                self.trackPointer(source: "display-sleep")
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.displaySleeping = false
                self.layout()
            }
        })
        layout()
        if monitorPointer { installPointerTracking() }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        fallbackTracking?.invalidate(); exitTimer?.invalidate(); expansionObserver?.cancel(); geometryObserver?.cancel()
        fallbackTracking = nil; exitTimer = nil; scheduledExitDeadline = nil
        pinObservers.removeAll()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil; localMouseMonitor = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        panel.orderOut(nil)
    }

    private func installPointerTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                           .otherMouseDragged, .leftMouseDown, .rightMouseDown,
                                           .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        // Global monitors exclude Halo's own events; the local monitor fills that gap and
        // returns events untouched. Mouse events do not require Accessibility permission.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.trackPointer(source: "global")
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.trackPointer(source: "local")
            return event
        }
        reconcileFallbackTracking()
        trackPointer(source: "startup")
    }

    private func reconcileFallbackTracking() {
        guard !stopped, !sleeping, !displaySleeping, present, monitorPointer, model.showIsland else {
            fallbackTracking?.invalidate(); fallbackTracking = nil
            return
        }
        guard fallbackTracking == nil else { return }
        // Keep the physical notch's passive check at 120 ms for suppressed events,
        // but do not wake up to check an island that is hidden or a sleeping screen.
        let tracking = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackPointer(source: "fallback") }
        }
        tracking.tolerance = 0.025
        fallbackTracking = tracking
        RunLoop.main.add(tracking, forMode: .common)
    }

    private func displayID(_ screen: NSScreen) -> String { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName }

    func layout() {
        guard !stopped else { return }
        let screens = NSScreen.screens
        let names = screens.map { (id: displayID($0), name: $0.localizedName) }
        if !model.screenNames.elementsEqual(names, by: { $0.id == $1.id && $0.name == $1.name }) { model.screenNames = names }
        guard let selected = screens.first(where: { displayID($0) == model.preferredDisplay }) ?? screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screens.first else { return }
        if screen.map(displayID) != displayID(selected) { hover.reset() }
        screen = selected
        if model.notchHeight != selected.safeAreaInsets.top { model.notchHeight = selected.safeAreaInsets.top }
        let notchWidth: CGFloat
        if let left = selected.auxiliaryTopLeftArea, let right = selected.auxiliaryTopRightArea, selected.safeAreaInsets.top > 0 {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 0 }
        if model.notchWidth != notchWidth { model.notchWidth = notchWidth }
        let frame = geometry(on: selected).panel
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if present && model.showIsland { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        reconcileFallbackTracking()
        trackPointer(source: "layout")
    }

    private func geometry(on screen: NSScreen) -> IslandGeometry {
        IslandGeometry(screen: screen.frame,
                       islandSize: CGSize(width: model.width, height: model.height),
                       panelSize: CGSize(width: model.panelWidth, height: model.panelHeight),
                       notchSize: CGSize(width: model.notchWidth, height: model.notchHeight))
    }

    private func trackPointer(source: String = "unspecified") {
        guard !stopped, !sleeping, !displaySleeping, present, model.showIsland, let screen else {
            hover.reset(); exitTimer?.invalidate(); exitTimer = nil
            scheduledExitDeadline = nil
            panel.ignoresMouseEvents = true
            return
        }
        let geometry = geometry(on: screen)
        let point = NSEvent.mouseLocation
        let inside = geometry.containsPointer(point, retainingHover: hover.inside)
        let ignoresMouse = !geometry.acceptsMouse(at: point, expanded: model.expanded)
        if panel.ignoresMouseEvents != ignoresMouse { panel.ignoresMouseEvents = ignoresMouse }
        let uptime = ProcessInfo.processInfo.systemUptime
        let expandedBefore = model.expanded
        let buttons = NSEvent.pressedMouseButtons
        let action = hover.update(inside: inside, expanded: model.expanded, hoverEnabled: model.hoverToExpand,
                                  pinned: model.pinned || model.dropTargeted,
                                  gestureHeld: buttons != 0, at: uptime)
        switch action {
        case .expand:
            // Open the activity shown in the compact wings, only on a fresh hover visit.
            // Already-open navigation and explicit file-drop selection stay under user control.
            if model.focus.isActive { model.selectedTab = .focus }
            else if model.media.hasSession || model.media.isPlaying || model.preview { model.selectedTab = .music }
            model.expandedByHover = true
            model.setExpanded(true)
        case .collapse:
            model.expandedByHover = false
            model.setExpanded(false)
        case nil: break
        }
        tracePointer(source: source, point: point, geometry: geometry, inside: inside,
                     expandedBefore: expandedBefore, buttons: buttons, action: action, at: uptime)
        scheduleExit()
    }

    private func tracePointer(source: String, point: CGPoint, geometry: IslandGeometry, inside: Bool,
                              expandedBefore: Bool, buttons: Int, action: IslandHover.Action?, at time: TimeInterval) {
        guard hoverDiagnosticsEnabled, let start = hoverDiagnosticsStartedAt,
              time - start <= 15, hoverDiagnosticLines < 160 else { return }
        let actionName = action.map { $0 == .expand ? "expand" : "collapse" } ?? "none"
        let state = "inside=\(inside) expanded=\(expandedBefore)->\(model.expanded) hoverEnabled=\(model.hoverToExpand) pinned=\(model.pinned) drop=\(model.dropTargeted) buttons=\(buttons) action=\(actionName) ignoresMouse=\(panel.ignoresMouseEvents) island=\(geometry.island) panel=\(panel.frame)"
        guard state != lastHoverDiagnosticState || time - lastHoverDiagnosticTime >= 1 else { return }
        hoverDiagnosticLines += 1
        lastHoverDiagnosticState = state
        lastHoverDiagnosticTime = time
        print("HOVER t=\(String(format: "%.3f", time - start)) source=\(source) pointer=\(point) \(state) notch=\(String(describing: geometry.hardwareNotch)) deadline=\(String(describing: hover.exitDeadline))")
        fflush(stdout)
    }

    private func scheduleExit() {
        let deadline = !stopped && !sleeping && !displaySleeping ? hover.exitDeadline : nil
        // Mouse movement and the fallback often report the same pending exit.
        // Keep one timer for that deadline rather than continually rearming it.
        if deadline == scheduledExitDeadline, exitTimer != nil { return }
        exitTimer?.invalidate(); exitTimer = nil
        scheduledExitDeadline = nil
        guard let deadline else { return }
        let delay = deadline - ProcessInfo.processInfo.systemUptime
        // Past deadlines are retried by button-up, pin updates, or the passive fallback.
        guard delay > 0 else { return }
        exitTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.scheduledExitDeadline == deadline else { return }
                self.exitTimer = nil
                self.scheduledExitDeadline = nil
                self.trackPointer(source: "exit")
            }
        }
        scheduledExitDeadline = deadline
        if let exitTimer { RunLoop.main.add(exitTimer, forMode: .common) }
    }

    func diagnosticDescription() -> String {
        guard let screen else { return "Island geometry: no display" }
        panel.contentView?.layoutSubtreeIfNeeded()
        let geometry = geometry(on: screen)
        let content = panel.contentView
        let contentTop = content.map { panel.convertToScreen($0.convert($0.bounds, to: nil)).maxY }
        return """
        Island geometry: display=\(screen.localizedName)
        screen=\(screen.frame) hardwareNotch=\(String(describing: geometry.hardwareNotch))
        window=\(panel.frame) windowTopGap=\(screen.frame.maxY - panel.frame.maxY)
        contentBounds=\(String(describing: content?.bounds)) contentTop=\(String(describing: contentTop))
        contentSafeArea=\(String(describing: content?.safeAreaInsets)) hostingSafeAreaRegions=disabled
        island=\(geometry.island) visibleTopGap=\(screen.frame.maxY - geometry.island.maxY)
        hitTopCenter=\(geometry.containsPointer(CGPoint(x: screen.frame.midX, y: screen.frame.maxY))) hitBottomCenter=\(geometry.containsPointer(CGPoint(x: screen.frame.midX, y: geometry.island.minY)))
        hoverEntryDelay=0 exitDelay=\(hover.exitDelay) eventTracking=global+local fallback=0.12
        """
    }
}
