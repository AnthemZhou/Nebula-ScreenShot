// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon

@MainActor final class HotKey {
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
        registrationStatus = RegisterEventHotKey(UInt32(kVK_ANSI_4), UInt32(controlKey | shiftKey | cmdKey),
                                                 identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    static var systemScreenshotConflict: Bool {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
              let entries = hotKeys?.takeRetainedValue() as? [[String: Any]] else { return true }
        return entries.contains { entry in
            (entry[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true &&
            (entry[kHISymbolicHotKeyCode] as? NSNumber)?.intValue == kVK_ANSI_4 &&
            (entry[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value == UInt32(controlKey | shiftKey | cmdKey)
        }
    }
}
