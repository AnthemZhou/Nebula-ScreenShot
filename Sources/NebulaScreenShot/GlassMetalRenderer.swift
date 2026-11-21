// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import MetalKit
import OSLog

/// Geometry only. Equality skips work for hover, ink and annotation changes.
struct GlassFrame: Equatable {
    var size: CGSize
    var scale: CGFloat
    var origin: CGPoint
    var canvasSize: CGSize
    var selection: CGRect
    var selectionRadius: CGFloat
    var row: CGRect
    var hint: CGRect
    var refraction: Float = 1

    var isValid: Bool {
        let values = [size.width, size.height, scale, origin.x, origin.y,
                      canvasSize.width, canvasSize.height, selection.minX, selection.minY,
                      selection.width, selection.height, selectionRadius,
                      row.minX, row.minY, row.width, row.height,
                      hint.minX, hint.minY, hint.width, hint.height]
        return values.allSatisfy(\.isFinite) && size.width > 0 && size.height > 0 &&
            canvasSize.width > 0 && canvasSize.height > 0 && scale >= 1 && scale <= 4 &&
            size.width * scale <= 4096 && size.height * scale <= 512 &&
            row.width > 0 && row.height > 0 && hint.width > 0 && hint.height > 0 && refraction.isFinite
    }
}

private struct GlassUniforms {
    var viewport: SIMD4<Float>
    var canvas: SIMD4<Float>
    var crop: SIMD4<Float>
    var row: SIMD4<Float>
    var hint: SIMD4<Float>
    var radii: SIMD4<Float>

    init(_ frame: GlassFrame) {
        func vector(_ rect: CGRect) -> SIMD4<Float> {
            SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height))
        }
        viewport = SIMD4(Float(frame.size.width), Float(frame.size.height), Float(frame.scale), 0.48)
        canvas = SIMD4(Float(frame.origin.x), Float(frame.origin.y), Float(frame.canvasSize.width), Float(frame.canvasSize.height))
        crop = vector(frame.selection)
        row = vector(frame.row)
        hint = vector(frame.hint)
        radii = SIMD4(14, 12, Float(frame.selectionRadius), frame.refraction)
    }
}

/// The immutable capture is retained without copying. Its texture is created
/// once, on the render queue, and released with this capture's toolbar.
private final class GlassBackdrop {
    let image: CGImage
    var uploadFailed = false
    var texture: MTLTexture? // Accessed only on GlassMetalBackend.queue.
    init(_ image: CGImage) { self.image = image }
}

private final class GlassMetalBackend {
    static let shared = GlassMetalBackend()
    private let queue = DispatchQueue(label: "Nebula.glass.render", qos: .userInitiated)
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Glass")
    private var context: Context?
    private var unavailable = false

    private struct Context {
        let device: MTLDevice
        let commands: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
    }

    // Reused between frames; serialized access means no resource races or
    // unbounded allocation during a long crop drag.
    private var target: MTLTexture?
    private var readback: MTLBuffer?
    private var targetWidth = 0
    private var targetHeight = 0

    func prewarm() { queue.async { _ = self.prepare() } }

    func prepareBackdrop(_ backdrop: GlassBackdrop) {
        // A canceled capture must not leave large uploads queued behind it.
        queue.async { [weak backdrop] in
            autoreleasepool {
                guard let backdrop, let context = self.prepare() else { return }
                do { _ = try self.texture(for: backdrop, context: context) }
                catch { backdrop.uploadFailed = true }
            }
        }
    }

    private func prepare() -> Context? {
        if let context { return context }
        guard !unavailable else { return nil }
        let start = ProcessInfo.processInfo.systemUptime
        do {
            guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue() else {
                unavailable = true; return nil
            }
            let library = try device.makeLibrary(source: GlassShader.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "nebulaGlassVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "nebulaGlassFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let context = Context(device: device, commands: commands, pipeline: pipeline)
            self.context = context
            logger.notice("Metal glass ready; preparation \(Int((ProcessInfo.processInfo.systemUptime - start) * 1000), privacy: .public) ms off main thread")
            return context
        } catch {
            unavailable = true
            logger.error("Metal glass unavailable; using dark fallback: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func texture(for backdrop: GlassBackdrop, context: Context) throws -> MTLTexture? {
        if let texture = backdrop.texture { return texture }
        guard !backdrop.uploadFailed else { return nil }
        var image = backdrop.image
        // Bound texture memory on large/multiple displays. The small glass
        // surfaces need no more than a 4096 px source; exports use the original.
        let ratio = min(1, 4096 / CGFloat(max(image.width, image.height)))
        if ratio < 1 {
            let width = max(1, Int(CGFloat(image.width) * ratio))
            let height = max(1, Int(CGFloat(image.height) * ratio))
            guard let bitmap = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let _ = bitmap.data else { return nil }
            bitmap.interpolationQuality = .medium
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let reduced = bitmap.makeImage() else { return nil }
            image = reduced
        }
        let texture = try MTKTextureLoader(device: context.device).newTexture(cgImage: image, options: [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ])
        backdrop.texture = texture
        return texture
    }

    func render(_ frame: GlassFrame, backdrop: GlassBackdrop,
                completion: @escaping (CGImage?, Double) -> Void) {
        queue.async { [weak backdrop] in
            autoreleasepool {
                let started = ProcessInfo.processInfo.systemUptime
                let image = backdrop.flatMap { self.renderNow(frame, backdrop: $0) }
                let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
                DispatchQueue.main.async { completion(image, elapsed) }
            }
        }
    }

    private func renderNow(_ frame: GlassFrame, backdrop: GlassBackdrop) -> CGImage? {
        guard frame.isValid, let context = prepare() else { return nil }
        do {
            guard let source = try texture(for: backdrop, context: context) else { return nil }
            let width = Int(ceil(frame.size.width * frame.scale))
            let height = Int(ceil(frame.size.height * frame.scale))
            let rowBytes = ((width * 4 + 255) / 256) * 256
            if width != targetWidth || height != targetHeight || target == nil || readback == nil {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                    width: width, height: height, mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = .renderTarget
                target = context.device.makeTexture(descriptor: descriptor)
                readback = context.device.makeBuffer(length: rowBytes * height, options: .storageModeShared)
                targetWidth = width; targetHeight = height
            }
            guard let target, let readback, let command = context.commands.makeCommandBuffer() else { return nil }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
            var uniforms = GlassUniforms(frame)
            encoder.setRenderPipelineState(context.pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlassUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
            guard let blit = command.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1), to: readback,
                      destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
            blit.endEncoding()
            command.commit()
            // Only the dedicated render queue waits. Neither event handling nor
            // capture presentation ever waits for Metal or readback.
            command.waitUntilCompleted()
            guard command.status == .completed else { return nil }
            let data = Data(bytes: readback.contents(), count: rowBytes * height)
            guard let provider = CGDataProvider(data: data as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little), provider: provider, decode: nil,
                shouldInterpolate: true, intent: .defaultIntent)
        } catch {
            backdrop.uploadFailed = true
            logger.error("Glass frame failed; retaining dark fallback: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// At most one render plus one replacement request per toolbar. Stale results
/// never repaint a different screenshot or a newer crop position.
@MainActor final class GlassMetalRenderer {
    private var backdrop: GlassBackdrop?
    private var latest: GlassFrame?
    private var completed: GlassFrame?
    private var generation = 0
    private var inFlight = false
    var onImage: ((CGImage, GlassFrame, Double) -> Void)?

    static func prewarm() { GlassMetalBackend.shared.prewarm() }

    /// Start the one-time upload at pointer-down, while the user is selecting.
    func prepare(image: CGImage) {
        guard backdrop?.image !== image else { return }
        generation += 1
        let backdrop = GlassBackdrop(image)
        self.backdrop = backdrop
        completed = nil
        GlassMetalBackend.shared.prepareBackdrop(backdrop)
    }

    func update(image: CGImage, frame: GlassFrame) {
        guard frame.isValid else { cancel(); return }
        if backdrop?.image !== image {
            generation += 1
            backdrop = GlassBackdrop(image)
            completed = nil
        }
        latest = frame
        submitIfNeeded()
    }

    func suspend() {
        generation += 1
        latest = nil; completed = nil
    }

    func cancel() {
        suspend()
        backdrop = nil
    }

    private func submitIfNeeded() {
        guard !inFlight, let frame = latest, frame != completed, let backdrop else { return }
        inFlight = true
        let submittedGeneration = generation
        GlassMetalBackend.shared.render(frame, backdrop: backdrop) { [weak self] image, elapsed in
            guard let self else { return }
            self.inFlight = false
            if self.generation == submittedGeneration && self.latest == frame {
                // Cache failures too: never repeatedly compile/upload on hover.
                self.completed = frame
                if let image { self.onImage?(image, frame, elapsed) }
            }
            self.submitIfNeeded()
        }
    }
}
