import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A button that, when clicked, listens for the next modifier+key combo and
/// stores it into the bound `keyCode` / `modifiers` (Carbon-style flags).
/// Click again to clear.
struct ShortcutRecorder: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 90)
            }

            if keyCode != 0 && !recording {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
            }
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if recording { return "Press shortcut…" }
        if keyCode == 0 { return "Click to set" }
        return HotKeyService.describe(keyCode: keyCode, modifiers: modifiers)
    }

    private func toggleRecording() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Cancel on Escape with no modifiers.
            if event.type == .keyDown,
               event.keyCode == UInt16(kVK_Escape),
               event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
                stopRecording()
                return nil
            }

            guard event.type == .keyDown else { return event }

            let mods = HotKeyService.carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier so we don't capture stray taps.
            guard mods != 0 else { return event }

            keyCode = UInt32(event.keyCode)
            modifiers = mods
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func clear() {
        keyCode = 0
        modifiers = 0
    }
}
