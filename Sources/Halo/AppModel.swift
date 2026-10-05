import AppKit
import SwiftUI
import Combine
import IOKit.ps
import HaloCore

enum IslandTab: String, CaseIterable { case music = "Now Playing", focus = "Focus", shelf = "Shelf", notes = "Notes", mirror = "Mirror"
    var symbol: String { switch self { case .music: "waveform"; case .focus: "timer"; case .shelf: "tray"; case .notes: "note.text"; case .mirror: "camera" } }
}

struct ShelfItem: Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

@MainActor
final class AppModel: ObservableObject {
    let media = MediaService()
    let waveform = AudioWaveform()
    let camera = CameraMirror()
    let notes = NoteStore()
    @Published var editingNote = false
    @Published var expanded = false { didSet { reconcileClock() } }
    @Published var expandedByHover = false
    @Published var dropTargeted = false
    @Published var pinned = false
    @Published var selectedTab = IslandTab.music { didSet { reconcileClock() } }
    @Published var now = Date()
    @Published var focus = FocusClock() { didSet { reconcileFocusDeadline(); reconcileClock() } }
    @Published var focusMinutes = 25
    @Published var shelf: [ShelfItem] = []
    @Published var banner: String?
    @Published var preview = false { didSet { reconcileClock() } }
    @Published private(set) var systemAwake = true
    @Published private(set) var displayAwake = true
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 0
    @Published var battery: Int?
    @Published var charging = false
    @Published var screenNames: [(id: String, name: String)] = []
    @Published var showIsland: Bool { didSet { save(showIsland, "showIsland"); reconcileClock(); onLayoutChange?() } }
    @Published var hoverToExpand: Bool { didSet { save(hoverToExpand, "hoverToExpand") } }
    @Published var trackPeeks: Bool { didSet { save(trackPeeks, "trackPeeks") } }
    @Published var reduceMotion: Bool { didSet { save(reduceMotion, "reduceMotion"); reconcileWaveform() } }
    @Published var batteryAlerts: Bool { didSet { save(batteryAlerts, "batteryAlerts") } }
    @Published var directFallback: Bool { didSet { save(directFallback, "directFallback"); media.directFallbackEnabled = directFallback } }
    @Published var preferredDisplay: String { didSet { save(preferredDisplay, "preferredDisplay"); onLayoutChange?() } }
    @Published var customNotchSize: Bool { didSet { save(customNotchSize, "customNotchSize"); onLayoutChange?() } }
    @Published var compactWidthSetting: Double { didSet { save(compactWidthSetting, "compactWidthSetting"); onLayoutChange?() } }
    @Published var compactHeightSetting: Double { didSet { save(compactHeightSetting, "compactHeightSetting"); onLayoutChange?() } }
    @Published var expandedWidthSetting: Double { didSet { save(expandedWidthSetting, "expandedWidthSetting"); onLayoutChange?() } }
    @Published var expandedHeightSetting: Double { didSet { save(expandedHeightSetting, "expandedHeightSetting"); onLayoutChange?() } }
    @Published var liveWaveform: Bool { didSet { save(liveWaveform, "liveWaveform"); reconcileWaveform() } }
    @Published var waveformWidth: Double { didSet { save(waveformWidth, "waveformWidth") } }
    @Published var waveformHeight: Double { didSet { save(waveformHeight, "waveformHeight") } }
    @Published var waveformThickness: Double { didSet { save(waveformThickness, "waveformThickness") } }
    @Published var waveformLineCount: Double { didSet { save(waveformLineCount, "waveformLineCount"); reconcileWaveform() } }
    var onLayoutChange: (() -> Void)?
    var onSettings: (() -> Void)?
    private var timer: Timer?
    private var focusCompletionTimer: Timer?
    private var batteryTimer: Timer?
    private var started = false
    private var clockRefreshPending = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var bannerTask: Task<Void, Never>?
    private var filePanel: NSOpenPanel?
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["showIsland": true, "hoverToExpand": true, "trackPeeks": true, "batteryAlerts": true,
                              "waveformWidth": 28.0, "waveformHeight": 18.0, "waveformThickness": 2.0, "waveformLineCount": 8.0,
                              "compactWidthSetting": 220.0, "compactHeightSetting": 38.0,
                              "expandedWidthSetting": 420.0, "expandedHeightSetting": 240.0])
        liveWaveform = d.bool(forKey: "liveWaveform")
        waveformWidth = d.double(forKey: "waveformWidth")
        waveformHeight = d.double(forKey: "waveformHeight")
        waveformThickness = d.double(forKey: "waveformThickness")
        waveformLineCount = d.double(forKey: "waveformLineCount")
        showIsland = d.bool(forKey: "showIsland")
        hoverToExpand = d.bool(forKey: "hoverToExpand")
        trackPeeks = d.bool(forKey: "trackPeeks")
        reduceMotion = d.bool(forKey: "reduceMotion")
        batteryAlerts = d.bool(forKey: "batteryAlerts")
        directFallback = d.bool(forKey: "directFallback")
        preferredDisplay = d.string(forKey: "preferredDisplay") ?? "automatic"
        customNotchSize = d.bool(forKey: "customNotchSize")
        compactWidthSetting = d.double(forKey: "compactWidthSetting")
        compactHeightSetting = d.double(forKey: "compactHeightSetting")
        expandedWidthSetting = d.double(forKey: "expandedWidthSetting")
        expandedHeightSetting = d.double(forKey: "expandedHeightSetting")
        shelf = (d.stringArray(forKey: "shelfPaths") ?? []).map { ShelfItem(url: URL(fileURLWithPath: $0)) }
        media.directFallbackEnabled = directFallback
        media.objectWillChange.sink { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            // The publisher fires before the new playback state is assigned.
            guard !self.clockRefreshPending else { return }
            self.clockRefreshPending = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.clockRefreshPending = false
                self.reconcileClock()
            }
        }.store(in: &cancellables)
        media.onTrackChange = { [weak self] in
            guard let self, self.trackPeeks, !self.preview else { return }
            self.announce(self.media.snapshot.title ?? self.media.sourceName)
        }
    }

    var motionReduced: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var animationsActive: Bool { showIsland && systemAwake && displayAwake }
    var motion: Animation { motionReduced ? .easeOut(duration: 0.1) : .spring(response: 0.25, dampingFraction: 0.9) }
    var hasNotch: Bool { notchHeight > 0 }
    var compactHasActivity: Bool { playing || focus.isActive }
    private var sizing: NotchSizing {
        NotchSizing(hardwareWidth: notchWidth, hardwareHeight: notchHeight, custom: customNotchSize,
                    closedWidth: compactWidthSetting, closedHeight: compactHeightSetting,
                    expandedWidth: expandedWidthSetting, expandedHeight: expandedHeightSetting,
                    hasActivity: compactHasActivity)
    }
    var headerHeight: CGFloat { sizing.headerHeight }
    var compactWidth: CGFloat { sizing.closedWidth }
    var expandedWidth: CGFloat { sizing.expandedWidth }
    var expandedHeight: CGFloat { sizing.expandedHeight }
    var width: CGFloat { expanded ? expandedWidth : (banner != nil ? max(320, compactWidth) : compactWidth) }
    var height: CGFloat { expanded ? expandedHeight : headerHeight + (banner != nil ? 34 : 0) }
    var panelWidth: CGFloat { max(width, expandedWidth) + 48 }
    var panelHeight: CGFloat { max(height, expandedHeight) + 40 }
    var topInset: CGFloat { 0 }
    var waveformColors: [ArtworkColor] { preview || !media.hasSession ? ArtworkPalette.fallback : media.waveformColors }
    var playing: Bool { preview || media.isPlaying }
    var displayTitle: String { preview ? "Sample track" : media.snapshot.title ?? (media.audioSources.isEmpty ? "No media playing" : "Audio active in \(media.sourceName)") }
    var displayArtist: String { preview ? "Preview" : media.snapshot.artist ?? media.sourceName }

    func start() {
        guard !started else { return }
        started = true
        media.start()
        updateBattery(initial: true)
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setSystemAwake(false) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setSystemAwake(true) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setDisplayAwake(false) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setDisplayAwake(true) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcileWaveform() }
        })
        reconcileClock()
        reconcileFocusDeadline()
        reconcileBatteryTimer()
    }

    func stop() {
        started = false
        timer?.invalidate(); timer = nil
        focusCompletionTimer?.invalidate(); focusCompletionTimer = nil
        batteryTimer?.invalidate(); batteryTimer = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        waveform.stop()
        camera.reconcile(active: false)
        media.stop(); bannerTask?.cancel(); bannerTask = nil
    }

    private func setSystemAwake(_ awake: Bool) {
        guard started, systemAwake != awake else { return }
        systemAwake = awake
        if awake {
            completeFocusIfNeeded(at: Date())
            updateBattery(initial: true)
        }
        reconcileClock()
        reconcileFocusDeadline()
        reconcileBatteryTimer()
    }

    private func setDisplayAwake(_ awake: Bool) {
        guard started, displayAwake != awake else { return }
        displayAwake = awake
        reconcileClock()
    }

    func reconcileWaveform() {
        let count = waveformLineCount.isFinite ? Int(min(16, max(3, waveformLineCount))) : 8
        let visible = expanded ? selectedTab == .music : !focus.isActive
        waveform.reconcile(active: started && animationsActive && media.isPlaying && !preview && visible,
                           enabled: liveWaveform, count: count, reduced: motionReduced)
    }

    private func reconcileClock() {
        reconcileWaveform()
        camera.reconcile(active: started && animationsActive && expanded && selectedTab == .mirror)
        // The compact header displays a running focus clock; playback position is
        // visible only in the expanded Music tab. All other states need no 1 Hz redraw.
        let needsClock = started && systemAwake && displayAwake && showIsland &&
            (focus.isRunning || (expanded && selectedTab == .music && !preview && media.isPlaying && media.snapshot.duration > 0))
        guard needsClock else { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        now = Date()
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started, self.systemAwake, self.displayAwake, self.showIsland else { return }
                self.now = Date()
                self.completeFocusIfNeeded(at: self.now)
            }
        }
        clock.tolerance = 0.1
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    private func reconcileFocusDeadline() {
        focusCompletionTimer?.invalidate(); focusCompletionTimer = nil
        guard started, systemAwake, let deadline = focus.deadline else { return }
        let completion = Timer(timeInterval: max(0.001, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started, self.systemAwake else { return }
                self.completeFocusIfNeeded(at: Date())
                self.reconcileFocusDeadline()
            }
        }
        focusCompletionTimer = completion
        RunLoop.main.add(completion, forMode: .common)
    }

    private func completeFocusIfNeeded(at date: Date) {
        guard let deadline = focus.deadline, date >= deadline else { return }
        // Calling a mutating method through @Published would notify even when
        // nothing changes, so publish only an actual completion.
        var completed = focus
        guard completed.tick(now: date) else { return }
        focus = completed
        announce("Timer finished")
        NSSound(named: "Glass")?.play()
    }

    private func reconcileBatteryTimer() {
        batteryTimer?.invalidate(); batteryTimer = nil
        guard started, systemAwake, battery != nil else { return }
        let batteryCheck = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started, self.systemAwake else { return }
                self.updateBattery(initial: false)
            }
        }
        batteryCheck.tolerance = 5
        batteryTimer = batteryCheck
        RunLoop.main.add(batteryCheck, forMode: .common)
    }
    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        if !value { expandedByHover = false }
        withAnimation(motion) { expanded = value }
    }
    func activateHeader() { expandedByHover = false; setExpanded(true) }
    func dismiss() { pinned = false; setExpanded(false) }
    func resetDimensions() {
        customNotchSize = false
        compactWidthSetting = max(220, notchWidth)
        compactHeightSetting = max(38, notchHeight)
        expandedWidthSetting = 420
        expandedHeightSetting = 240
    }
    func announce(_ text: String) {
        bannerTask?.cancel()
        withAnimation(motion) { banner = text }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            withAnimation(self.motion) { self.banner = nil }
        }
    }
    func startFocus() { now = Date(); focus.start(minutes: focusMinutes, now: now) }
    func toggleFocus() { now = Date(); if focus.isRunning { focus.pause(now: now) } else if focus.isPaused { focus.resume(now: now) } else { startFocus() } }
    func addFocusMinutes() {
        now = Date()
        if focus.isActive {
            focus.add(minutes: 5)
        } else {
            focusMinutes += 5
            if focus.completed { focus.reset() }
        }
    }

    func addFiles(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let clean = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: clean.path), !shelf.contains(where: { $0.url == clean }) else { continue }
            guard shelf.count < 30 else { announce("The shelf holds up to 30 files."); break }
            shelf.append(ShelfItem(url: clean))
        }
        save(shelf.map(\.url.path), "shelfPaths")
    }
    func removeFile(_ item: ShelfItem) { shelf.removeAll { $0.id == item.id }; save(shelf.map(\.url.path), "shelfPaths") }
    func chooseFiles() {
        if let filePanel { NSApp.activate(ignoringOtherApps: true); filePanel.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        filePanel = panel
        panel.title = "Add files to Halo"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Add to Shelf"
        let wasPinned = pinned; pinned = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] result in
            Task { @MainActor in
                if result == .OK { self?.addFiles(panel.urls) }
                self?.pinned = wasPinned
                self?.filePanel = nil
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }
    func reveal(_ item: ShelfItem) {
        guard FileManager.default.fileExists(atPath: item.url.path) else { announce("This file has moved. Add it to the shelf again."); return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func updateBattery(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let percent = Int(Double(current) / Double(max) * 100)
            let onPower = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            if !initial && batteryAlerts {
                if onPower != charging { announce(onPower ? "Power connected · \(percent)%" : "On battery · \(percent)%") }
                else if percent <= 20, let old = battery, old > 20 { announce("Battery is at \(percent)%") }
            }
            if battery != percent { battery = percent }
            if charging != onPower { charging = onPower }
            return
        }
    }
}
