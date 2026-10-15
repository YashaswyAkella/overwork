import AppKit
import Metal
import UniformTypeIdentifiers

/// `Overwork --render out.png` renders one frame offscreen so the shader can be checked without showing the overlay.
enum RenderTest {
    static func run(outputPath: String) {
        Task { @MainActor in
            let w = 1920, h = 1080
            var image: CGImage? = nil
            var diag = "preflight=\(ScreenCapture.hasPermission) bundle=\(Bundle.main.bundleIdentifier ?? "-") path=\(Bundle.main.bundlePath)\n"
            if let main = NSScreen.main, let id = ScreenCapture.displayID(of: main) {
                let r = await ScreenCapture.captureDetailed(displayID: id, size: CGSize(width: w, height: h))
                image = r.image
                diag += "capture=\(r.image != nil ? "ok" : "nil") error=\(r.error ?? "none")\n"
            }
            try? diag.write(toFile: outputPath + ".txt", atomically: true, encoding: .utf8)
            if image == nil { image = testImage(width: w, height: h) }
            render(image: image, width: w, height: h, to: outputPath)
            exit(0)
        }
    }

    private static func render(image: CGImage?, width: Int, height: Int, to path: String) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let r = BlackHoleRenderer(device: device, image: image) else { print("renderer unavailable"); return }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td), let cb = r.queue.makeCommandBuffer() else { return }
        r.encode(target: tex, time: 7.5, intensity: 1, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info),
              let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { print("could not encode"); return }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(path)")
    }

    /// A busy fake desktop so the distortion is visible.
    private static func testImage(width: Int, height: Int) -> CGImage? {
        let img = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            rect.fill()
            let colors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink, .systemTeal, .systemYellow]
            var i = 0
            for y in stride(from: 40, to: height - 40, by: 160) {
                for x in stride(from: 40, to: width - 40, by: 240) {
                    colors[i % colors.count].withAlphaComponent(0.85).setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 200, height: 120), xRadius: 12, yRadius: 12).fill()
                    NSColor.white.setFill()
                    for line in 0..<4 {
                        NSRect(x: x + 16, y: y + 20 + line * 22, width: 120 + (line * 37) % 60, height: 8).fill()
                    }
                    i += 1
                }
            }
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSRect(x: 0, y: 0, width: width, height: 28).fill()
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
