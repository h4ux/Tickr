import Foundation
import AppKit
import Carbon.HIToolbox

/// Thin wrapper around Carbon's `RegisterEventHotKey` so the app can listen
/// to global keyboard shortcuts even while another app has focus.
/// Sandbox-safe (no extra entitlements required).
class HotKeyService {
    static let shared = HotKeyService()

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registrations: [String: Registration] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    /// Register a global hotkey under a stable name. Re-registering the same
    /// `name` swaps the binding.
    func register(name: String, keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        unregister(name: name)
        guard keyCode != 0 else { return }

        let myID = nextID
        nextID += 1
        let hkID = EventHotKeyID(signature: fourCharCode("TKHK"), id: myID)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref = ref else { return }

        registrations[name] = Registration(ref: ref, handler: onPress)
        idToKey[myID] = name

        installEventHandlerIfNeeded()
    }

    func unregister(name: String) {
        if let reg = registrations[name] {
            UnregisterEventHotKey(reg.ref)
            registrations.removeValue(forKey: name)
            idToKey = idToKey.filter { $1 != name }
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, ctx -> OSStatus in
            guard let ctx = ctx, let eventRef = eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            let svc = Unmanaged<HotKeyService>.fromOpaque(ctx).takeUnretainedValue()
            if let name = svc.idToKey[hkID.id], let reg = svc.registrations[name] {
                DispatchQueue.main.async { reg.handler() }
            }
            return noErr
        }, 1, &eventType, ctx, &eventHandlerRef)
    }

    // MARK: - Helpers

    private func fourCharCode(_ s: String) -> OSType {
        var result: UInt32 = 0
        for char in s.utf8.prefix(4) {
            result = (result << 8) + UInt32(char)
        }
        return result
    }

    /// Default ⌘⇧V — what the clipboard shortcut falls back to.
    static var defaultClipboardCombo: (keyCode: UInt32, modifiers: UInt32) {
        (UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey))
    }

    /// Default ⌘⇧T — what the todo shortcut falls back to.
    static var defaultTodoCombo: (keyCode: UInt32, modifiers: UInt32) {
        (UInt32(kVK_ANSI_T), UInt32(cmdKey | shiftKey))
    }

    // MARK: - Formatting / parsing

    /// Convert Carbon modifier flags into the macOS-standard glyph string,
    /// e.g. (cmdKey | shiftKey, kVK_ANSI_V) → "⇧⌘V".
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s.isEmpty ? "Unbound" : s
    }

    /// Carbon modifier mask from an `NSEvent.ModifierFlags`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space:     return "␣"
        case kVK_Return:    return "↩"
        case kVK_Escape:    return "⎋"
        case kVK_Tab:       return "⇥"
        case kVK_Delete:    return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow:return "→"
        case kVK_UpArrow:   return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote:     return "'"
        case kVK_ANSI_Comma:     return ","
        case kVK_ANSI_Period:    return "."
        case kVK_ANSI_Slash:     return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Minus:     return "-"
        case kVK_ANSI_Equal:     return "="
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Grave:     return "`"
        default: return "?"
        }
    }
}
