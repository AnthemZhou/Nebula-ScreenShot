// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

MainActor.assumeIsolated {
if CommandLine.arguments.contains("--permission-relaunch-helper") {
    exit(AppRelauncher.runHelper(arguments: CommandLine.arguments))
}
let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-toolbar"), CommandLine.arguments.count > index + 1 {
    let preview = ToolbarPreview(availableWidth: CommandLine.arguments.contains("--compact") ? 372 : AnnotationToolbar.preferredWidth)
    let previewWindow = NSWindow(contentRect: preview.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    previewWindow.contentView = preview
    preview.layoutSubtreeIfNeeded()
    if let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds) {
        preview.cacheDisplay(in: preview.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
    }
    exit(1)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-welcome"), CommandLine.arguments.count > index + 1 {
    // Render our own view offscreen; this does not capture the user's desktop.
    let welcome = WelcomeWindow()
    if let view = welcome.window?.contentView {
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
                catch { fputs("\(error)\n", stderr); exit(1) }
            }
        }
    }
    exit(1)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-demo"), CommandLine.arguments.count > index + 1 {
    let size = CGSize(width: 1120, height: 700)
    if let image = DemoArtwork.image(size: size, scale: 2),
       let bitmap = AnnotationRenderer.export(image: image, canvasSize: size,
                                               selection: CGRect(origin: .zero, size: size), annotations: DemoArtwork.annotations),
       let data = bitmap.representation(using: .png, properties: [:]) {
        do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
        catch { fputs("\(error)\n", stderr); exit(1) }
    }
    exit(1)
}
let delegate = AppDelegate()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
}
