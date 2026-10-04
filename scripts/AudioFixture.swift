// Integration fixture only; never included in Halo.app.
import AppKit
import AVFoundation
import MediaPlayer

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
buffer.frameLength = 44100
for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating: 0, count: 44100) }
// Opt-in audible test: a quiet 440 Hz tone with alternating amplitude and silence.
if CommandLine.arguments.contains("--waveform-tone") {
    for frame in 0..<44100 {
        let time = Double(frame) / 44100
        let amplitude = time < 0.3 ? 0.08 : (time < 0.6 ? 0.02 : 0)
        let value = Float(amplitude * sin(2 * Double.pi * 440 * time))
        for channel in 0..<2 { buffer.floatChannelData![channel][frame] = value }
    }
}
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: format)
player.scheduleBuffer(buffer, at: nil, options: .loops)
try engine.start()
player.play()

let metadataEnabled = CommandLine.arguments.contains("--metadata")
let center = MPNowPlayingInfoCenter.default()
let commands = MPRemoteCommandCenter.shared()
var isPlaying = true
var position = 30.0
var anchor = Date()
var title = "Halo Integration Test"
func currentPosition() -> Double { min(240, position + (isPlaying ? Date().timeIntervalSince(anchor) : 0)) }
func publish() {
    guard metadataEnabled else { return }
    center.nowPlayingInfo = [
        MPMediaItemPropertyTitle: title,
        MPMediaItemPropertyArtist: "Local fixture",
        MPMediaItemPropertyAlbumTitle: "Halo verification",
        MPMediaItemPropertyPlaybackDuration: 240.0,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition(),
        MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
    ]
    center.playbackState = isPlaying ? .playing : .paused
}
func setPlaying(_ playing: Bool) {
    position = currentPosition(); anchor = Date(); isPlaying = playing
    if playing { player.play() } else { player.pause() }
    publish()
}
if metadataEnabled {
    commands.playCommand.addTarget { _ in setPlaying(true); return .success }
    commands.pauseCommand.addTarget { _ in setPlaying(false); return .success }
    commands.togglePlayPauseCommand.addTarget { _ in setPlaying(!isPlaying); return .success }
    commands.nextTrackCommand.addTarget { _ in title = "Halo Next Track"; position = 0; anchor = Date(); publish(); return .success }
    commands.previousTrackCommand.addTarget { _ in title = "Halo Integration Test"; position = 0; anchor = Date(); publish(); return .success }
    commands.changePlaybackPositionCommand.addTarget { event in
        guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
        position = event.positionTime; anchor = Date(); publish(); return .success
    }
    publish()
}
print("ready")
fflush(stdout)
// Bound fixture lifetime even if its runner is interrupted.
Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in
    center.nowPlayingInfo = nil; player.stop(); engine.stop(); NSApp.terminate(nil)
}
app.run()
