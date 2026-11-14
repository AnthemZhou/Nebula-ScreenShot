// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

MainActor.assumeIsolated {
let app = NSApplication.shared
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
