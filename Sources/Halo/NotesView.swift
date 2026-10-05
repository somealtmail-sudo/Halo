import SwiftUI
import AppKit
import HaloCore

struct NotesView: View {
    @ObservedObject var notes: NoteStore
    @Binding var editing: Bool
    @FocusState private var focused: Bool
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes.text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .focused($focused)
                    .accessibilityLabel("Note text")
                if notes.text.isEmpty {
                    Text("Write something to remember…")
                        .font(.system(size: 12)).foregroundStyle(haloSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 12) {
                Text("Saved on this Mac").font(.system(size: 10)).foregroundStyle(haloSecondary)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(notes.text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .help("Copy note").accessibilityLabel("Copy note")
                .disabled(notes.text.isEmpty)
                Button { confirmingClear = true } label: { Image(systemName: "trash") }
                    .help("Clear note").accessibilityLabel("Clear note")
                    .disabled(notes.text.isEmpty)
            }
            .font(.system(size: 12)).buttonStyle(.plain)
        }
        .onChange(of: focused) { _, value in editing = value || confirmingClear }
        .onChange(of: confirmingClear) { _, value in editing = focused || value }
        .onDisappear { editing = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            focused = false
        }
        .alert("Clear this note?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear note", role: .destructive) { notes.text = "" }
        } message: {
            Text("This removes the saved text from Halo on this Mac.")
        }
    }
}
