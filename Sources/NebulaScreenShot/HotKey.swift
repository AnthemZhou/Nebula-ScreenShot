// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon

@MainActor final class HotKey {
    static let displayString = "⌃⇧⌘5"
    private static let keyCode = UInt32(kVK_ANSI_5)
    private static let modifiers = UInt32(controlKey | shiftKey | cmdKey)
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    private(set) var registrationStatus: OSStatus = noErr

    func register() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
                }
                return noErr
            }, 1, &event, pointer, &handler)
        }
        let identifier = EventHotKeyID(signature: OSType(0x4E425353), id: 1)
        registrationStatus = RegisterEventHotKey(Self.keyCode, Self.modifiers,
                                                 identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    /// nil means the system reservation list could not be read, not a confirmed conflict.
    static var systemConflict: Bool? {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
              let entries = hotKeys?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return entries.contains { entry in
            (entry[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true &&
            (entry[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value == keyCode &&
            (entry[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value == modifiers
        }
    }
}
