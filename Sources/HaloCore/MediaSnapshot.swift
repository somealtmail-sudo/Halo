import Foundation

/// Full snapshots from the adapter (`stream --no-diff --micros`).
public struct MediaSnapshot: Codable, Equatable, Sendable {
    public var bundleIdentifier: String?
    public var parentApplicationBundleIdentifier: String?
    public var playing: Bool?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var artworkData: String?
    public var durationMicros: Double?
    public var elapsedTimeMicros: Double?
    public var timestampEpochMicros: Double?
    public var playbackRate: Double?
    public var prohibitsSkip: Bool?

    public init(bundleIdentifier: String? = nil, playing: Bool = false,
                title: String? = nil, artist: String? = nil, duration: Double = 0,
                elapsed: Double = 0, timestamp: Date = Date()) {
        self.bundleIdentifier = bundleIdentifier
        self.playing = playing
        self.title = title
        self.artist = artist
        durationMicros = duration * 1_000_000
        elapsedTimeMicros = elapsed * 1_000_000
        timestampEpochMicros = timestamp.timeIntervalSince1970 * 1_000_000
    }

    public var sourceID: String? { parentApplicationBundleIdentifier ?? bundleIdentifier }
    public var isPlaying: Bool { playing == true }
    public var duration: Double { max(0, finite(durationMicros) / 1_000_000) }
    public var identity: String { "\(sourceID ?? "")|\(title ?? "")|\(artist ?? "")|\(album ?? "")" }
    public var hasSession: Bool { sourceID?.isEmpty == false }
    public func shouldShowMetadata(activeAudioSources: Set<String>) -> Bool {
        hasSession && (isPlaying || !activeAudioSources.contains { $0 != sourceID })
    }
    /// Players may publish the pause flag before their new elapsed-time anchor.
    /// Hold the just-reached position until the follow-up timing snapshot arrives.
    public func reconciled(after previous: MediaSnapshot, displayed previousDisplayed: MediaSnapshot? = nil, at date: Date) -> MediaSnapshot {
        guard identity == previous.identity, !isPlaying,
              elapsedTimeMicros == previous.elapsedTimeMicros,
              timestampEpochMicros == previous.timestampEpochMicros else { return self }
        var result = self
        if previous.isPlaying {
            result.elapsedTimeMicros = previous.position(at: date) * 1_000_000
            result.timestampEpochMicros = date.timeIntervalSince1970 * 1_000_000
        } else if let previousDisplayed, previousDisplayed.identity == identity, !previousDisplayed.isPlaying {
            // Artwork and other fields may change while the player's raw time anchor stays stale.
            result.elapsedTimeMicros = previousDisplayed.elapsedTimeMicros
            result.timestampEpochMicros = previousDisplayed.timestampEpochMicros
        }
        return result
    }
    public func position(at date: Date) -> Double {
        let elapsed = finite(elapsedTimeMicros) / 1_000_000
        let timestamp = timestampEpochMicros.flatMap { $0.isFinite ? $0 / 1_000_000 : nil } ?? date.timeIntervalSince1970
        let rate = playbackRate.flatMap { $0.isFinite ? $0 : nil } ?? 1
        let delta = isPlaying ? max(0, date.timeIntervalSince1970 - timestamp) * max(0, rate) : 0
        let value = max(0, elapsed + delta)
        guard value.isFinite else { return duration > 0 ? duration : max(0, elapsed) }
        return duration > 0 ? min(value, duration) : value
    }
    private func finite(_ value: Double?) -> Double { guard let value, value.isFinite else { return 0 }; return value }
}

public struct MediaEnvelope: Decodable {
    public let type: String
    public let diff: Bool
    public let payload: MediaSnapshot
}

/// Pipe reads need not align with JSON lines. Cap the buffer to bound malformed output.
public struct LineBuffer {
    private var pending = Data()
    private let maximumLineBytes: Int
    private var discardingOversizedLine = false
    public init(maximumLineBytes: Int = 16 * 1024 * 1024) {
        self.maximumLineBytes = max(0, maximumLineBytes)
    }
    public mutating func append(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 10) ?? data.endIndex
            let segment = data[start..<end]
            if !discardingOversizedLine {
                if segment.count <= maximumLineBytes - pending.count {
                    pending.append(contentsOf: segment)
                } else {
                    pending.removeAll(keepingCapacity: false)
                    discardingOversizedLine = true
                }
            }
            guard end < data.endIndex else { break }
            if !discardingOversizedLine { lines.append(pending) }
            pending.removeAll(keepingCapacity: true)
            discardingOversizedLine = false
            start = data.index(after: end)
        }
        return lines
    }
}
