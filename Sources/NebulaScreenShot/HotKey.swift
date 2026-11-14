// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon
import OSLog

@MainActor final class HotKey {
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Shortcut")
    static let displayString = "⌃⇧⌘5"
    private static let keyCode = UInt32(kVK_ANSI_5)
    private static let modifiers = UInt32(controlKey | shiftKey | cmdKey)
    private static let identifier = EventHotKeyID(signature: OSType(0x4E425353), id: 1)
    private let bindingCode: UInt32
    private let bindingModifiers: UInt32
    private let bindingIdentifier: EventHotKeyID
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    private(set) var registrationStatus: OSStatus = noErr
    var isRegistered: Bool { hotKey != nil && handler != nil }

    init(keyCode: UInt32? = nil, modifiers: UInt32? = nil, identifier: EventHotKeyID? = nil) {
        bindingCode = keyCode ?? Self.keyCode
        bindingModifiers = modifiers ?? Self.modifiers
        bindingIdentifier = identifier ?? Self.identifier
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    func register() {
        // Activation can retry a failed registration without briefly releasing a working one.
        guard !isRegistered else { return }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            registrationStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                    guard identifier.signature == owner.bindingIdentifier.signature,
                          identifier.id == owner.bindingIdentifier.id else { return OSStatus(eventNotHandledErr) }
                    guard owner.isRegistered else { return OSStatus(eventNotHandledErr) }
                    owner.logger.notice("Capture shortcut received")
                    owner.onPress?()
                    return noErr
                }
            }, 1, &event, pointer, &handler)
            guard registrationStatus == noErr else { return }
            guard handler != nil else {
                registrationStatus = OSStatus(eventInternalErr)
                return
            }
        }
        // Exclusive delivery prevents other Carbon registrants from responding too.
        // It does not guarantee that macOS's symbolic shortcut has been disabled.
        registrationStatus = RegisterEventHotKey(bindingCode, bindingModifiers,
                                                 bindingIdentifier, GetApplicationEventTarget(),
                                                 OptionBits(kEventHotKeyExclusive), &hotKey)
        if registrationStatus == noErr && hotKey == nil { registrationStatus = OSStatus(eventInternalErr) }
        logger.notice("Shortcut registration result: \(self.registrationStatus, privacy: .public)")
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    /// An enabled system reservation, not proof that Carbon registration will fail.
    /// nil means the system reservation list could not be read.
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
