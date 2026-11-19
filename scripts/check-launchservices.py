#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Optional Aqua-session integration check: isolated fixture, no screen access or system input.
from pathlib import Path
import os, plistlib, shutil, subprocess, tempfile, time, uuid
repo = Path(__file__).resolve().parent.parent
root = Path(tempfile.mkdtemp(prefix='nebula-launchservices-'))
identifier = 'io.github.anthemzhou.NebulaRelaunchFixture.' + uuid.uuid4().hex
app = root / 'Nebula Relaunch Fixture.app'
(app / 'Contents/MacOS').mkdir(parents=True)
state = root / 'launches.txt'
source = (repo / 'Sources/NebulaScreenShot/AppRelauncher.swift').read_text().replace('io.github.anthemzhou.NebulaScreenShot', identifier)
# Warm the helper's LaunchServices snapshot while its parent is still alive, matching a delayed update.
source = source.replace('let status: Int', 'let cachedParent = NSRunningApplication(processIdentifier: pid)\n        _ = NSWorkspace.shared.runningApplications\n        defer { withExtendedLifetime(cachedParent) {} }\n        let status: Int')
# Exercise a windowless/background relaunch, like resume mode, without asking for
# the test bundle's screen permission. All test events stay inside that process.
source = source.replace('configuration.activates = mode == .requestPermission', 'configuration.activates = false')
(root / 'AppRelauncher.swift').write_text(source)
shutil.copy2(repo / 'Sources/NebulaScreenShot/HotKey.swift', root / 'HotKey.swift')
main = '''import AppKit
import Carbon
import Darwin
@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hotKey: HotKey?
    var received = false
    let identifier = EventHotKeyID(signature: 0x4E425354, id: 201)
    func applicationWillFinishLaunching(_ notification: Notification) {
        for code in [kVK_F19, kVK_F18, kVK_F20] {
            let key = HotKey(keyCode: UInt32(code), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), identifier: identifier)
            key.register()
            if key.isRegistered { hotKey = key; break }
        }
        guard let hotKey else { exit(3) }
        hotKey.onPress = { [weak self] in self?.firstShortcutReceived() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard !NSApp.isActive, NSApp.keyWindow == nil else { exit(4) }
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(),
                          EventAttributes(kEventAttributeUserEvent), &event) == noErr, let event else { exit(5) }
        defer { ReleaseEvent(event) }
        var id = identifier, target = GetEventDispatcherTarget()
        guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                MemoryLayout<EventHotKeyID>.size, &id) == noErr,
              SetEventParameter(event, EventParamName(kEventParamPostTarget), EventParamType(typeEventTargetRef),
                                MemoryLayout<EventTargetRef?>.size, &target) == noErr,
              PostEventToQueue(GetMainEventQueue(), event, EventPriority(kEventPriorityStandard)) == noErr else { exit(6) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(7) }
    }
    func firstShortcutReceived() {
        guard !received, !NSApp.isActive, NSApp.keyWindow == nil else { exit(8) }
        received = true
        let state = URL(fileURLWithPath: "STATE_PATH")
        var records = (try? String(contentsOf: state, encoding: .utf8)) ?? ""
        records += "\\(getpid()) \\(CommandLine.arguments.contains(\"--request-screen-permission\") ? \"reopened\" : \"initial\")\\n"
        try! records.write(to: state, atomically: true, encoding: .utf8)
        if CommandLine.arguments.contains("--request-screen-permission") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        } else {
            Task { @MainActor in
                do {
                    let session = try AppRelauncher.prepare(.requestPermission)
                    try await session.waitUntilReady()
                    NSApp.terminate(nil)
                } catch { fputs("\\(error)\\n", stderr); exit(2) }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { hotKey?.unregister() }
}
MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--permission-relaunch-helper") {
        exit(AppRelauncher.runHelper(arguments: CommandLine.arguments))
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = FixtureDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
'''.replace('STATE_PATH', str(state))
(root / 'main.swift').write_text(main)
with (app / 'Contents/Info.plist').open('wb') as file:
    plistlib.dump({'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'RelaunchFixture', 'CFBundleName': 'Nebula Relaunch Fixture', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSUIElement': True, 'LSMinimumSystemVersion': '14.0'}, file)
try:
    subprocess.run(['swiftc', '-swift-version', '5', '-emit-library', '-emit-module', '-module-name', 'NebulaCore', str(repo / 'Sources/NebulaCore/PermissionRelaunchPolicy.swift'), str(repo / 'Sources/NebulaCore/L10n.swift'), '-emit-module-path', str(root / 'NebulaCore.swiftmodule'), '-o', str(root / 'libNebulaCore.dylib')], check=True)
    subprocess.run(['swiftc', '-swift-version', '5', '-I', str(root), '-L', str(root), '-lNebulaCore', '-Xlinker', '-rpath', '-Xlinker', str(root), str(root / 'AppRelauncher.swift'), str(root / 'HotKey.swift'), str(root / 'main.swift'), '-o', str(app / 'Contents/MacOS/RelaunchFixture')], check=True)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
    for iteration in range(10):
        state.unlink(missing_ok=True)
        subprocess.run(['/usr/bin/open', '-g', '-n', str(app)], check=True)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            records = state.read_text().splitlines() if state.exists() else []
            if len(records) >= 2:
                break
            time.sleep(0.1)
        if len(records) != 2 or not records[0].endswith('initial') or not records[1].endswith('reopened') or records[0].split()[0] == records[1].split()[0]:
            raise RuntimeError(f'LaunchServices handoff failed: {records}; fixture {root}')
        time.sleep(1)
        assert state.read_text().splitlines() == records, 'Unexpected extra launch'
        print(f'PASS: background LaunchServices relaunch + first queued hotkey {iteration + 1}: {records}', flush=True)
finally:
    # Remove only this temporary test bundle from LaunchServices; real Nebula is untouched.
    subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)], capture_output=True)
    shutil.rmtree(root)
