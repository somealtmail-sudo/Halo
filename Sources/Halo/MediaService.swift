import AppKit
import CoreAudio
import Combine
import HaloCore
import Darwin
import ImageIO

struct AudioSource: Identifiable, Equatable {
    let id: String
    let name: String
    let pid: pid_t
}

@MainActor
final class MediaService: ObservableObject {
    enum Backend: String { case system = "System Now Playing", direct = "Direct player", none = "Waiting for playback" }
    @Published private(set) var snapshot = MediaSnapshot()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var audioSources: [AudioSource] = []
    @Published private(set) var adapterStatus = "Connecting…"
    @Published private(set) var backend = Backend.none
    @Published private(set) var commandError: String?
    @Published private(set) var audioAvailable = true
    var onTrackChange: (() -> Void)?
    var directFallbackEnabled = false {
        didSet {
            if !directFallbackEnabled, backend == .direct { apply(MediaSnapshot(), backend: .none) }
        }
    }
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var poll: Timer?
    private var fallbackBusy = false
    private var audioBusy = false
    private var stopped = true
    private var terminating = false
    private let readerQueue = DispatchQueue(label: "dev.kevin.halo.media", qos: .utility)
    private let scriptQueue = DispatchQueue(label: "dev.kevin.halo.automation", qos: .utility)
    private let audioQueue = DispatchQueue(label: "dev.kevin.halo.audio", qos: .utility)
    private let artworkQueue = DispatchQueue(label: "dev.kevin.halo.artwork", qos: .utility)
    private var generation = UUID()
    private var artworkRevision = UUID()
    private var pendingCommands: [[String]] = []
    private var commandProcess: Process?
    private var retiringProcesses: [Process] = []
    private var commandTimeout: DispatchWorkItem?
    private var pendingDirectCommands = 0
    private var scriptSession = ScriptSession()
    private var rawSnapshot = MediaSnapshot()
    private var observer: NSObjectProtocol?

    // A paused session must not hide a different app that is actively producing audio.
    var hasSession: Bool {
        snapshot.shouldShowMetadata(activeAudioSources: Set(audioSources.map(\.id)))
    }
    var isPlaying: Bool { snapshot.isPlaying || (!hasSession && !audioSources.isEmpty) }
    var canControl: Bool { hasSession && backend != .none }
    var sourceName: String {
        guard hasSession, let id = snapshot.sourceID else { return audioSources.first?.name ?? "Now Playing" }
        return Self.appName(id)
    }
    var sourceIcon: NSImage? {
        let id = hasSession ? snapshot.sourceID : audioSources.first?.id
        guard let id, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    static func appName(_ id: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return app.localizedName ?? id }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url.deletingPathExtension().lastPathComponent }
        return id.split(separator: ".").last.map(String.init) ?? id
    }

    func start() {
        guard stopped, !terminating else { return }
        stopped = false
        startAdapter()
        refreshAudio()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAudio(); self?.pollDirectPlayers() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                if app.bundleIdentifier == self?.snapshot.sourceID { self?.apply(MediaSnapshot(), backend: .none) }
            }
        }
    }

    func stop() {
        stopped = true
        generation = UUID()
        artworkRevision = UUID()
        fallbackBusy = false
        audioBusy = false
        scriptSession.cancel()
        scriptSession = ScriptSession()
        pendingDirectCommands = 0
        poll?.invalidate()
        poll = nil
        closeAdapterPipes()
        if let process { retire(process) }
        commandTimeout?.cancel()
        commandTimeout = nil
        pendingCommands.removeAll()
        if let commandProcess { retire(commandProcess) }
        commandProcess = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        process = nil
    }

    private func closeAdapterPipes() {
        for pipe in [outputPipe, errorPipe].compactMap({ $0 }) {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        outputPipe = nil
        errorPipe = nil
    }

    private nonisolated static func terminate(_ child: Process) {
        guard child.isRunning else { return }
        child.terminate()
        // A wedged private-framework call must not leave an orphan after reconnect/quit.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    private func retire(_ child: Process) {
        retiringProcesses.removeAll { !$0.isRunning }
        guard child.isRunning else { return }
        if !retiringProcesses.contains(where: { $0 === child }) { retiringProcesses.append(child) }
        Self.terminate(child)
    }

    /// The application delegate keeps AppKit alive until this completion. Reconnect
    /// remains immediate, but quitting must also collect helpers retired by a recent reconnect.
    func shutdownForTermination(completion: @escaping @MainActor () -> Void) {
        terminating = true
        stop()
        let children = retiringProcesses
        DispatchQueue.global(qos: .utility).async {
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while children.contains(where: { $0.isRunning }), ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            for child in children where child.isRunning { kill(child.processIdentifier, SIGKILL) }
            // Allow Foundation to reap killed children without an unbounded waitUntilExit.
            let reapDeadline = ProcessInfo.processInfo.systemUptime + 0.25
            while children.contains(where: { $0.isRunning }), ProcessInfo.processInfo.systemUptime < reapDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            // terminateLater can run a nested AppKit modal loop. A completion
            // enqueued on the main dispatch queue cannot reenter an in-flight
            // main-queue signal handler that initiated that loop.
            RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) {
                MainActor.assumeIsolated { completion() }
            }
        }
    }

    func reconnect() {
        stop()
        apply(MediaSnapshot(), backend: .none)
        start()
    }

    private var adapterArguments: [String]? {
        guard let resources = Bundle.main.resourceURL,
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl").path
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework").path
        guard FileManager.default.fileExists(atPath: script), FileManager.default.fileExists(atPath: framework) else { return nil }
        return [script, framework]
    }

    private func startAdapter() {
        guard let arguments = adapterArguments else { adapterStatus = "Adapter missing — use the bundled Halo.app"; return }
        let child = Process()
        let output = Pipe(), errors = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = arguments + ["stream", "--no-diff", "--micros", "--debounce=100", "--allow-missing-title"]
        child.standardOutput = output
        child.standardError = errors
        let decoder = StreamDecoder()
        let token = generation
        let queue = readerQueue
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let data = try? handle.read(upToCount: 64 * 1024), !data.isEmpty else { handle.readabilityHandler = nil; return }
            queue.async {
                for snapshot in decoder.decode(data) {
                    DispatchQueue.main.async { [weak self] in
                        guard self?.stopped == false, self?.generation == token, self?.process?.isRunning == true else { return }
                        if self?.adapterStatus != "Connected" { self?.adapterStatus = "Connected" }
                        self?.apply(snapshot, backend: snapshot.hasSession ? .system : .none)
                    }
                }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            if (try? handle.read(upToCount: 64 * 1024))?.isEmpty != false { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard self?.stopped == false, self?.generation == token else { return }
                self?.closeAdapterPipes()
                self?.process = nil
                self?.adapterStatus = "Disconnected (\(child.terminationStatus)) — reconnect in Settings"
                if self?.backend == .system { self?.apply(MediaSnapshot(), backend: .none) }
            }
        }
        do {
            try child.run()
            process = child; outputPipe = output; errorPipe = errors
            adapterStatus = "Listening"
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            adapterStatus = "Couldn’t start media detection"
        }
    }

    private func apply(_ next: MediaSnapshot, backend: Backend) {
        let resolved = next.reconciled(after: rawSnapshot, displayed: snapshot, at: Date())
        rawSnapshot = next
        let next = resolved
        let changed = next.identity != snapshot.identity
        if next.artworkData != snapshot.artworkData { updateArtwork(next.artworkData) }
        if snapshot != next { snapshot = next }
        if self.backend != backend { self.backend = backend }
        if changed && next.isPlaying { onTrackChange?() }
    }

    private func updateArtwork(_ encoded: String?) {
        artworkRevision = UUID()
        let revision = artworkRevision
        artwork = nil
        guard let encoded else { return }
        artworkQueue.async { [weak self] in
            // Artwork is displayed at small sizes; decode one bounded thumbnail off the UI thread.
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceThumbnailMaxPixelSize: 256,
                           kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            let image = Data(base64Encoded: encoded)
                .flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
                .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options) }
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.artworkRevision == revision else { return }
                self.artwork = image.map { NSImage(cgImage: $0, size: .zero) }
            }
        }
    }

    func command(_ number: Int) {
        guard canControl else { return }
        commandError = nil
        if backend == .direct, let id = snapshot.sourceID {
            let actions = [2: "playpause", 4: "next track", 5: "previous track"]
            guard let action = actions[number] else { return }
            directCommand(id: id, action: action)
        } else { runAdapter(["send", String(number)]) }
    }

    func seek(_ seconds: Double) {
        guard canControl, snapshot.duration > 0, seconds.isFinite else { return }
        let position = min(max(0, seconds), snapshot.duration)
        if backend == .direct, let id = snapshot.sourceID {
            directCommand(id: id, action: "set player position to \(position)")
        } else {
            let micros = min(position * 1_000_000, Double(Int64.max).nextDown)
            runAdapter(["seek", String(Int64(micros))])
        }
    }

    private func runAdapter(_ command: [String]) {
        guard !stopped, pendingCommands.count < 16 else { return }
        pendingCommands.append(command)
        sendNextAdapterCommand()
    }

    private func sendNextAdapterCommand() {
        guard !stopped, commandProcess == nil, !pendingCommands.isEmpty, let arguments = adapterArguments else { return }
        let command = pendingCommands.removeFirst()
        let token = generation
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = arguments + command
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.generation == token, self.commandProcess === child else { return }
                self.commandTimeout?.cancel()
                self.commandTimeout = nil
                self.commandProcess = nil
                if child.terminationStatus != 0 { self.commandError = "The player didn’t accept that command." }
                self.sendNextAdapterCommand()
            }
        }
        do {
            try child.run()
            commandProcess = child
            let timeout = DispatchWorkItem { Self.terminate(child) }
            commandTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        } catch {
            commandError = "Couldn’t reach the media player."
            pendingCommands.removeAll()
        }
    }

    func openSource(_ id: String? = nil) {
        guard let id = id ?? (hasSession ? snapshot.sourceID : audioSources.first?.id),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func refreshAudio() {
        guard !stopped, !audioBusy else { return }
        audioBusy = true
        let token = generation
        audioQueue.async { [weak self] in
            let result = AudioDetector.read()
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.generation == token else { return }
                self.audioBusy = false
                if self.audioAvailable != result.available { self.audioAvailable = result.available }
                let sources = AudioDetector.resolve(result.processes)
                if sources != self.audioSources { self.audioSources = sources }
            }
        }
    }

    private func pollDirectPlayers() {
        guard !stopped, directFallbackEnabled, backend != .system, !fallbackBusy else { return }
        let ids = ["com.apple.Music", "com.spotify.client"].filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard !ids.isEmpty else { if backend == .direct { apply(MediaSnapshot(), backend: .none) }; return }
        fallbackBusy = true
        let token = generation
        let session = scriptSession
        scriptQueue.async { [weak self] in
            var candidates: [MediaSnapshot] = []
            for id in ids {
                guard !session.isCancelled else { return }
                let script = """
                with timeout of 2 seconds
                    tell application id "\(id)"
                        if player state is stopped then return {}
                        return {name of current track, artist of current track, album of current track, player state as string, duration of current track, player position}
                    end tell
                end timeout
                """
                var error: NSDictionary?
                guard let value = NSAppleScript(source: script)?.executeAndReturnError(&error), error == nil, value.numberOfItems == 6 else { continue }
                let duration = value.atIndex(5)?.doubleValue ?? 0
                var snapshot = MediaSnapshot(bundleIdentifier: id, playing: value.atIndex(4)?.stringValue == "playing",
                                             title: value.atIndex(1)?.stringValue, artist: value.atIndex(2)?.stringValue,
                                             duration: id == "com.spotify.client" ? duration / 1000 : duration,
                                             elapsed: value.atIndex(6)?.doubleValue ?? 0)
                snapshot.album = value.atIndex(3)?.stringValue
                candidates.append(snapshot)
            }
            let selected = candidates.first(where: \.isPlaying) ?? candidates.first ?? MediaSnapshot()
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.fallbackBusy = false
                guard !self.stopped, self.directFallbackEnabled, self.backend != .system else { return }
                self.apply(selected, backend: selected.hasSession ? .direct : .none)
            }
        }
    }

    private func directCommand(id: String, action: String) {
        guard !stopped, pendingDirectCommands < 16, ["com.apple.Music", "com.spotify.client"].contains(id) else { return }
        pendingDirectCommands += 1
        let token = generation
        let session = scriptSession
        scriptQueue.async { [weak self] in
            guard !session.isCancelled else { return }
            var error: NSDictionary?
            NSAppleScript(source: "with timeout of 2 seconds\ntell application id \"\(id)\" to \(action)\nend timeout")?.executeAndReturnError(&error)
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.generation == token else { return }
                self.pendingDirectCommands -= 1
                if error != nil { self.commandError = "Allow Halo to control this player in System Settings → Privacy & Security → Automation." }
                self.pollDirectPlayers()
            }
        }
    }
}

private final class ScriptSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class StreamDecoder: @unchecked Sendable {
    private var buffer = LineBuffer()
    func decode(_ data: Data) -> [MediaSnapshot] {
        buffer.append(data).compactMap { line in
            guard let envelope = try? JSONDecoder().decode(MediaEnvelope.self, from: line), envelope.type == "data", !envelope.diff else { return nil }
            return envelope.payload
        }
    }
}

enum AudioDetector {
    struct AudioProcess {
        let pid: pid_t
        let bundleID: String?
    }

    static func read() -> (available: Bool, processes: [AudioProcess]) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return (false, []) }
        guard Int(size) >= MemoryLayout<AudioObjectID>.size, Int(size) % MemoryLayout<AudioObjectID>.size == 0 else { return (true, []) }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let capacity = size
        let status = objects.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr, size <= capacity, Int(size) % MemoryLayout<AudioObjectID>.size == 0 else { return (false, []) }
        var processes: [AudioProcess] = []
        for object in objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
            guard uint(object, kAudioProcessPropertyIsRunningOutput) == 1 else { continue }
            guard let rawPID = uint(object, kAudioProcessPropertyPID) else { continue }
            let pid = pid_t(bitPattern: rawPID)
            guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { continue }
            var property = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var bundle: Unmanaged<CFString>?
            var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let result = AudioObjectGetPropertyData(object, &property, 0, nil, &length, &bundle)
            let rawID = result == noErr ? bundle?.takeRetainedValue() as String? : nil
            processes.append(AudioProcess(pid: pid, bundleID: rawID))
        }
        return (true, processes)
    }

    @MainActor
    static func resolve(_ processes: [AudioProcess]) -> [AudioSource] {
        let applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var sources: [String: AudioSource] = [:]
        for process in processes {
            let pid = process.pid
            let rawID = process.bundleID
            let app = NSRunningApplication(processIdentifier: pid)
            let id = app?.bundleIdentifier ?? rawID ?? "pid.\(pid)"
            if id == "com.apple.audio.coreaudiod" { continue }
            // WebKit/Chromium helpers can publish their parent application's prefix.
            let parent = applications
                .filter { $0.bundleIdentifier.map { id == $0 || id.hasPrefix($0 + ".") } == true }
                .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
            let resolved = parent?.bundleIdentifier ?? id
            let name = parent?.localizedName ?? app?.localizedName ?? rawID?.split(separator: ".").last.map(String.init) ?? "Audio process \(pid)"
            sources[resolved] = AudioSource(id: resolved, name: name, pid: parent?.processIdentifier ?? pid)
        }
        return sources.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }
    private static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
