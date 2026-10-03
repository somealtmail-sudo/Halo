import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Show controls") {
                    model.showIsland = true
                    model.pinned = true
                    model.setExpanded(true)
                }.controlSize(.small)
            }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 12)
            Form {
                Section("General") {
                    Toggle("Show notch", isOn: $model.showIsland)
                    Toggle("Open on hover", isOn: $model.hoverToExpand)
                    Toggle("Reduce motion", isOn: $model.reduceMotion)
                    Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
                    Picker("Display", selection: $model.preferredDisplay) {
                        Text("Automatic").tag("automatic")
                        ForEach(model.screenNames, id: \.id) { screen in Text(screen.name).tag(screen.id) }
                    }
                    if let loginError { Text(loginError).font(.system(size: 11)).foregroundStyle(.orange) }
                }
                Section {
                    Toggle("Custom closed size", isOn: $model.customNotchSize)
                    dimension("Closed width", value: $model.compactWidthSetting, range: closedWidthRange,
                              automaticValue: model.customNotchSize ? nil : model.compactWidth)
                        .disabled(!model.customNotchSize)
                    dimension("Closed height", value: $model.compactHeightSetting, range: closedHeightRange,
                              automaticValue: model.customNotchSize ? nil : model.headerHeight)
                        .disabled(!model.customNotchSize)
                    dimension("Open width", value: $model.expandedWidthSetting, range: openWidthRange)
                    dimension("Open height", value: $model.expandedHeightSetting, range: openHeightRange)
                    HStack {
                        Text("Camera and active controls set minimum sizes.").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset sizes") { model.resetDimensions() }.controlSize(.small)
                    }
                } header: { Text("Size · points") }
                Section("Waveform") {
                    Toggle("Live system audio waveform", isOn: $model.liveWaveform)
                    dimension("Width", value: $model.waveformWidth, range: 16...40)
                    dimension("Height", value: $model.waveformHeight, range: 8...28)
                    dimension("Line thickness", value: $model.waveformThickness, range: 0.5...4, step: 0.5)
                    dimension("Lines", value: $model.waveformLineCount, range: 3...16, unit: "")
                    WaveformStatus(waveform: model.waveform) {
                        model.waveform.retry()
                        model.reconcileWaveform()
                    }
                    Text("Shows the amplitude of all system audio. Audio is never saved. Thickness fits the available width; Reduce motion pauses capture.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Section("Alerts") {
                    Toggle("Track changes", isOn: $model.trackPeeks)
                    Toggle("Battery updates", isOn: $model.batteryAlerts)
                }
                Section("Media") {
                    Toggle("Music & Spotify Automation fallback", isOn: $model.directFallback)
                    HStack {
                        Text(model.media.adapterStatus).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Button("Reconnect") { model.media.reconnect() }.controlSize(.small)
                    }
                }
            }.formStyle(.grouped).controlSize(.small)
            HStack {
                Spacer()
                Button(model.preview ? "End preview" : "Preview controls") {
                    model.preview.toggle()
                    model.showIsland = true
                    model.selectedTab = .music
                    model.pinned = true
                    model.setExpanded(true)
                }.controlSize(.small)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(width: 520, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: refreshLoginStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshLoginStatus() }
    }

    private var closedWidthRange: ClosedRange<Double> {
        let activitySpace = model.compactHasActivity ? 112.0 : 0
        let minimum = max(160, Double(model.notchWidth) + activitySpace)
        return minimum...max(400, minimum)
    }
    private var closedHeightRange: ClosedRange<Double> {
        let minimum = max(24, Double(model.notchHeight))
        return minimum...max(56, minimum)
    }
    private var openWidthRange: ClosedRange<Double> {
        let minimum = max(380, Double(model.compactWidth))
        return minimum...max(600, minimum)
    }
    private var openHeightRange: ClosedRange<Double> {
        let minimum = max(200, Double(model.headerHeight) + 160)
        return minimum...max(360, minimum)
    }

    private func dimension(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, automaticValue: CGFloat? = nil, step: Double = 1, unit: String = " pt") -> some View {
        let bounded = Binding(get: {
            let stored = value.wrappedValue
            return stored.isFinite ? min(range.upperBound, max(range.lowerBound, stored)) : range.lowerBound
        }, set: { proposed in
            value.wrappedValue = proposed.isFinite ? min(range.upperBound, max(range.lowerBound, (proposed / step).rounded() * step)) : range.lowerBound
        })
        let actual = automaticValue.map { Double($0) } ?? bounded.wrappedValue
        let displayed = actual.isFinite ? actual : range.lowerBound
        return HStack(spacing: 10) {
            Text(title).frame(width: 92, alignment: .leading)
            Slider(value: bounded, in: range).accessibilityLabel(title)
            Text((step < 1 ? String(format: "%.1f", displayed) : "\(Int(displayed))") + unit)
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Allow Halo in System Settings → General → Login Items." : nil
        } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled
        loginError = status == .requiresApproval ? "Allow Halo in System Settings → General → Login Items." : nil
    }
}

private struct WaveformStatus: View {
    @ObservedObject var waveform: AudioWaveform
    let retry: () -> Void
    var body: some View {
        HStack {
            Text(waveform.status).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button("Retry", action: retry).controlSize(.small)
        }
    }
}
