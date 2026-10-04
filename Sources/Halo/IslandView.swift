import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HaloCore
import Combine

let haloSecondary = Color.white.opacity(0.55)

/// The shoulders flare into the screen edge; the lower corners curve inward.
struct NotchShape: Shape {
    var expanded: Bool
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = 8
        let radius = min(expanded ? 22.0 : 12.0, max(0, rect.height - shoulder))
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + shoulder), control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - radius), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    @State private var dropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.expanded {
                VStack(spacing: 0) {
                    toolbar
                    Group {
                        switch model.selectedTab {
                        case .music: PlayerView(model: model)
                        case .focus: FocusView(model: model)
                        case .shelf: ShelfView(model: model)
                        case .mirror: CameraMirrorView(camera: model.camera)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let banner = model.banner, model.selectedTab != .music {
                        Text(banner).font(.system(size: 10)).foregroundStyle(haloSecondary)
                            .lineLimit(1).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 12)
                .transition(.opacity)
            } else if let banner = model.banner {
                Text(banner).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 22).frame(maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .frame(width: model.width, height: model.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .overlay(shape.stroke(dropTarget ? .white.opacity(0.7) : .clear, lineWidth: 1.5))
        .shadow(color: .black.opacity(model.expanded ? 0.35 : 0.12), radius: model.expanded ? 14 : 3, x: 0, y: 5)
        .animation(model.motionReduced ? .easeOut(duration: 0.1) : .spring(response: 0.38, dampingFraction: 0.86), value: model.compactHasActivity)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.addFiles([url]) }
                }
            }
            model.selectedTab = .shelf
            model.setExpanded(true)
            return !providers.isEmpty
        }
        .onChange(of: dropTarget) { _, value in
            model.dropTargeted = value
            if value { model.selectedTab = .shelf; model.setExpanded(true) }
        }
        .onExitCommand { model.dismiss() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all)
    }

    private var shape: NotchShape { NotchShape(expanded: model.expanded) }

    private var header: some View {
        Group {
            if model.expanded {
                Color.clear
            } else {
                compactHeader
                    .transition(.identity)
            }
        }
        .frame(height: model.headerHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.activateHeader() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open controls")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.activateHeader() }
    }

    private var compactHeader: some View {
        HStack(spacing: 0) {
            Group {
                if model.compactHasActivity {
                    if model.focus.isActive {
                        Image(systemName: "timer").font(.system(size: 14))
                    } else if model.playing {
                        ArtworkView(model: model, size: 21)
                            .transition(compactMediaTransition)
                    }
                }
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: model.hasNotch ? model.notchWidth : 0)
            Group {
                if model.compactHasActivity {
                    if model.focus.isActive {
                        Text(clockText(model.focus.remaining(at: model.now)))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    } else if model.playing {
                        ActivityBars(waveform: model.waveform, width: min(model.waveformWidth, (model.compactWidth - model.notchWidth - 30) / 2), height: min(model.waveformHeight, model.headerHeight - 8), thickness: model.waveformThickness, colors: model.waveformColors)
                            .transition(compactMediaTransition)
                    }
                }
            }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, model.compactHasActivity ? 15 : 0)
    }

    private var compactMediaTransition: AnyTransition {
        model.motionReduced ? .opacity : .opacity.combined(with: .scale(scale: 0.75))
    }

    private var toolbar: some View {
        HStack(spacing: 3) {
            ForEach(IslandTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(model.motionReduced ? .linear(duration: 0.1) : .easeInOut(duration: 0.15)) { model.selectedTab = tab }
                } label: {
                    Text(tab == .music ? "Music" : tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).frame(height: 27)
                        .foregroundStyle(model.selectedTab == tab ? .white : haloSecondary)
                        .background(model.selectedTab == tab ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityLabel(tab.rawValue)
            }
            Spacer(minLength: 4)
            if model.preview {
                Button("End preview") { model.preview = false }
                    .font(.system(size: 9)).buttonStyle(.plain).foregroundStyle(haloSecondary)
            }
            iconButton(model.pinned ? "pin.fill" : "pin", label: model.pinned ? "Unpin controls" : "Keep controls open") { model.pinned.toggle() }
                .foregroundStyle(model.pinned ? .white : haloSecondary)
            iconButton("gearshape", label: "Settings") { model.onSettings?() }
            iconButton("xmark", label: "Close controls") { model.dismiss() }
        }.frame(height: 34)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 25, height: 27)
        }.buttonStyle(.plain).foregroundStyle(haloSecondary).help(label).accessibilityLabel(label)
    }
}

struct ArtworkView: View {
    @ObservedObject var model: AppModel
    var size: CGFloat
    var body: some View {
        ZStack {
            if let image = model.media.artwork, !model.preview {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let icon = model.media.sourceIcon, !model.preview {
                Color.white.opacity(0.08)
                Image(nsImage: icon).resizable().scaledToFit().padding(size * 0.12)
            } else {
                Color.white.opacity(0.09)
                Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(haloSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? 8 : 4))
        .accessibilityHidden(true)
    }
}

struct ActivityBars: View {
    let waveform: AudioWaveform
    var width: Double
    var height: Double
    var thickness: Double
    var colors: [ArtworkColor]

    private func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }

    var body: some View {
        WaveformDrawing(waveform: waveform, thickness: bounded(thickness, 0.5...4), colors: colors)
            .frame(width: bounded(width, 16...40), height: bounded(height, 8...28))
            .accessibilityLabel("Live system audio waveform")
    }
}

/// Samples invalidate only this tiny native view, not SwiftUI layout or Canvas textures.
private struct WaveformDrawing: NSViewRepresentable {
    let waveform: AudioWaveform
    let thickness: Double
    let colors: [ArtworkColor]
    func makeNSView(context: Context) -> WaveformDrawingView {
        let view = WaveformDrawingView()
        view.subscription = waveform.$levels.sink { [weak view] levels in
            if view?.levels.count != levels.count { view?.rebuildColors(count: levels.count) }
            view?.levels = levels
            view?.needsDisplay = true
        }
        return view
    }
    func updateNSView(_ view: WaveformDrawingView, context: Context) {
        if view.colors != colors { view.colors = colors; view.rebuildColors(count: view.levels.count); view.needsDisplay = true }
        if view.thickness != thickness { view.thickness = thickness; view.needsDisplay = true }
    }
    static func dismantleNSView(_ view: WaveformDrawingView, coordinator: ()) {
        view.subscription = nil
    }
}

private final class WaveformDrawingView: NSView {
    var subscription: AnyCancellable?
    var levels: [Float] = []
    var thickness: Double = 2
    var colors = ArtworkPalette.fallback
    private var lineColors: [CGColor] = []
    func rebuildColors(count: Int) {
        let first = colors.first ?? ArtworkPalette.fallback[0]
        let last = colors.last ?? first
        lineColors = (0..<count).map { index in
            let color = first.blended(with: last, amount: Double(index) / Double(max(1, count - 1)))
            return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).cgColor
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, !levels.isEmpty else { return }
        let pitch = bounds.width / Double(levels.count)
        let stroke = min(thickness, pitch * 0.8)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        for (index, level) in levels.enumerated() {
            let length = max(0.01, Double(level) * bounds.height - stroke)
            let x = bounds.minX + (Double(index) + 0.5) * pitch
            context.setStrokeColor(lineColors[index])
            context.beginPath()
            context.move(to: CGPoint(x: x, y: bounds.midY - length / 2))
            context.addLine(to: CGPoint(x: x, y: bounds.midY + length / 2))
            context.strokePath()
        }
    }
}

struct PlayerView: View {
    @ObservedObject var model: AppModel
    @State private var scrubbing = false
    @State private var position = 0.0

    var body: some View {
        GeometryReader { geometry in
            Group {
                if model.media.hasSession || model.preview { player(compact: geometry.size.height < 145) }
                else if !model.media.audioSources.isEmpty { audioActivity }
                else { empty }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func player(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 11) {
            HStack(spacing: 12) {
                ArtworkView(model: model, size: compact ? 40 : 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayTitle).font(.system(size: compact ? 13 : 15, weight: .semibold)).lineLimit(1)
                    if let error = model.media.commandError {
                        Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
                            .help(error)
                    } else {
                        Text(model.displayArtist).font(.system(size: 11)).foregroundStyle(haloSecondary).lineLimit(1)
                    }
                    if !compact && !model.preview {
                        Text(model.media.sourceName)
                            .font(.system(size: 10)).foregroundStyle(haloSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                Slider(value: Binding(get: { scrubbing ? position : (model.preview ? 67 : model.media.snapshot.position(at: model.now)) }, set: { position = $0 }),
                       in: 0...max(1, model.preview ? 214 : model.media.snapshot.duration), onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { model.media.seek(position) }
                })
                .controlSize(.mini).tint(.white)
                .disabled(model.preview || !model.media.canControl || model.media.snapshot.duration <= 0)
                .accessibilityLabel("Playback position")
                HStack {
                    Text(clockText(floor(model.preview ? 67 : (scrubbing ? position : model.media.snapshot.position(at: model.now)))))
                    Spacer()
                    Text(model.preview ? "3:34" : (model.media.snapshot.duration > 0 ? clockText(floor(model.media.snapshot.duration)) : "Live"))
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(haloSecondary)
            }
            HStack(spacing: 20) {
                Button { model.media.openSource() } label: { Image(systemName: "arrow.up.forward.app").font(.system(size: 13)).frame(width: 28, height: 28) }
                    .help("Open media app").accessibilityLabel("Open media app").disabled(model.preview)
                Spacer(minLength: 0)
                transport("backward.end.fill", label: "Previous track", command: 5)
                Button { model.media.command(2) } label: {
                    Image(systemName: model.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: compact ? 29 : 34, height: compact ? 29 : 34).background(.white, in: Circle())
                }.accessibilityLabel(model.playing ? "Pause" : "Play").disabled(model.preview || !model.media.canControl)
                transport("forward.end.fill", label: "Next track", command: 4)
                Spacer(minLength: 0)
                ActivityBars(waveform: model.waveform, width: model.waveformWidth, height: model.waveformHeight, thickness: model.waveformThickness, colors: model.waveformColors)
            }.buttonStyle(.plain).foregroundStyle(haloSecondary)
        }
    }

    private func transport(_ symbol: String, label: String, command: Int) -> some View {
        Button { model.media.command(command) } label: { Image(systemName: symbol).font(.system(size: 15)).frame(width: 28, height: 29) }
            .accessibilityLabel(label).help(label).disabled(model.preview || !model.media.canControl || model.media.snapshot.prohibitsSkip == true)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("No media playing").font(.system(size: 13, weight: .medium))
            HStack(spacing: 9) {
                appButton("Music", id: "com.apple.Music", symbol: "music.note")
                appButton("Spotify", id: "com.spotify.client", symbol: "play.circle")
            }
        }
    }

    private func appButton(_ title: String, id: String, symbol: String) -> some View {
        Button { model.media.openSource(id) } label: {
            Label(title, systemImage: symbol).font(.system(size: 11)).padding(.horizontal, 11).padding(.vertical, 7)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel("Open \(title)")
    }

    private var audioActivity: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                ArtworkView(model: model, size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Audio in \(model.media.sourceName)").font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("Track details unavailable").font(.system(size: 11)).foregroundStyle(haloSecondary)
                }
                Spacer(minLength: 0)
                ActivityBars(waveform: model.waveform, width: model.waveformWidth, height: model.waveformHeight, thickness: model.waveformThickness, colors: model.waveformColors)
            }
            HStack {
                Text("\(model.media.audioSources.count) active \(model.media.audioSources.count == 1 ? "app" : "apps")").font(.system(size: 10)).foregroundStyle(haloSecondary)
                Spacer()
                Menu("Open app") {
                    ForEach(model.media.audioSources) { source in Button(source.name) { model.media.openSource(source.id) } }
                }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
            }
        }
    }
}

struct FocusView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 22) {
            VStack(spacing: 5) {
                Text(clockText(model.focus.isActive || model.focus.completed ? model.focus.remaining(at: model.now) : Double(model.focusMinutes * 60)))
                    .font(.system(size: 30, weight: .light)).monospacedDigit()
                Text(model.focus.completed ? "Complete" : (model.focus.isPaused ? "Paused" : "Timer"))
                    .font(.system(size: 10)).foregroundStyle(haloSecondary)
                if model.focus.isActive {
                    ProgressView(value: min(1, model.focus.remaining(at: model.now) / model.focus.duration))
                        .tint(.white).frame(width: 90).accessibilityLabel("Time remaining")
                }
            }.frame(width: 112)
            VStack(alignment: .leading, spacing: 11) {
                if !model.focus.isActive {
                    HStack(spacing: 5) {
                        ForEach([5, 15, 25, 50], id: \.self) { minutes in
                            Button("\(minutes)m") {
                                model.focusMinutes = minutes
                                if model.focus.completed { model.focus.reset() }
                            }
                                .font(.system(size: 11)).buttonStyle(.plain).padding(.horizontal, 7).padding(.vertical, 6)
                                .foregroundStyle(model.focusMinutes == minutes ? .white : haloSecondary)
                                .background(model.focusMinutes == minutes ? .white.opacity(0.18) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel("\(minutes) minute timer")
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { model.toggleFocus() } label: {
                        Label(model.focus.isRunning ? "Pause" : (model.focus.isPaused ? "Resume" : "Start"), systemImage: model.focus.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 8)
                            .foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                    if model.focus.isActive || model.focus.completed {
                        Button { model.focus.reset() } label: { Image(systemName: "arrow.counterclockwise").frame(width: 28, height: 29) }
                            .buttonStyle(.plain).foregroundStyle(haloSecondary).help("Reset timer").accessibilityLabel("Reset timer")
                    }
                }
                Button("+5 minutes") { model.addFocusMinutes() }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Add five minutes to the focus timer")
            }
            Spacer(minLength: 0)
        }
    }
}

struct ShelfView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.shelf.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 23, weight: .light)).foregroundStyle(haloSecondary)
                Text("Drop files here").font(.system(size: 13, weight: .medium))
                Button("Choose files…") { model.chooseFiles() }
                    .buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 11).padding(.vertical, 7)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 5) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.shelf) { item in
                            HStack(spacing: 9) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 25, height: 25)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                                    Text(item.url.deletingLastPathComponent().lastPathComponent).font(.system(size: 9)).foregroundStyle(haloSecondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Button { model.reveal(item) } label: { Image(systemName: "magnifyingglass").frame(width: 24, height: 25) }.help("Show in Finder").accessibilityLabel("Show \(item.name) in Finder")
                                Button { model.removeFile(item) } label: { Image(systemName: "xmark").frame(width: 24, height: 25) }.help("Remove from shelf").accessibilityLabel("Remove \(item.name) from shelf")
                            }
                            .buttonStyle(.plain).foregroundStyle(haloSecondary)
                            .padding(6).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                        }
                    }
                }
                HStack {
                    Text("\(model.shelf.count) \(model.shelf.count == 1 ? "file" : "files")").font(.system(size: 10)).foregroundStyle(haloSecondary)
                    Spacer()
                    Button { model.chooseFiles() } label: { Image(systemName: "plus").font(.system(size: 12)).frame(width: 25, height: 24) }
                        .buttonStyle(.plain).help("Add files").accessibilityLabel("Add files")
                }
            }
        }
    }
}
