import AppKit
import Metal
import UniformTypeIdentifiers

/// `Overwork --render out.png` renders one frame offscreen so the shader can be checked without showing the overlay.
enum RenderTest {
    static func run(outputPath: String) {
        Task { @MainActor in
            // --size WxH (pixels), --scale n (layout scale of the fake desktop), --test-image (skip capture),
            // --upscale n (render small, then stretch like the window server does, to show the old 1x look)
            let args = CommandLine.arguments
            func arg(_ f: String) -> String? { args.firstIndex(of: f).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            let size = arg("--size")?.split(separator: "x").compactMap { Int($0) }
            let w = size?.first ?? 1920, h = size?.last ?? 1080
            let scale = CGFloat(Double(arg("--scale") ?? "1") ?? 1)
            let upscale = Int(arg("--upscale") ?? "1") ?? 1
            var image: CGImage? = nil
            var diag = "preflight=\(ScreenCapture.hasPermission) bundle=\(Bundle.main.bundleIdentifier ?? "-") path=\(Bundle.main.bundlePath)\n"
            if !args.contains("--test-image"), let main = NSScreen.main, let id = ScreenCapture.displayID(of: main) {
                let r = await ScreenCapture.captureDetailed(displayID: id, size: CGSize(width: w, height: h))
                image = r.image
                diag += "capture=\(r.image != nil ? "ok" : "nil") error=\(r.error ?? "none")\n"
            }
            try? diag.write(toFile: outputPath + ".txt", atomically: true, encoding: .utf8)
            if image == nil { image = testImage(width: w, height: h, scale: scale) }
            render(image: image, width: w, height: h, upscale: upscale, to: outputPath)
            exit(0)
        }
    }

    private static func render(image: CGImage?, width: Int, height: Int, upscale: Int, to path: String) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let r = BlackHoleRenderer(device: device, image: image) else { print("renderer unavailable"); return }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--variant"), i + 1 < args.count, let n = Int(args[i + 1]) {
            r.variant = HoleVariant.all[n % HoleVariant.all.count]
        }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td), let cb = r.queue.makeCommandBuffer() else { return }
        r.encode(target: tex, time: 7.5, intensity: 1, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        // --bench n: time n full-resolution frames on the GPU.
        if let i = args.firstIndex(of: "--bench"), i + 1 < args.count, let n = Int(args[i + 1]) {
            let t0 = CACurrentMediaTime()
            for f in 0..<n {
                guard let c = r.queue.makeCommandBuffer() else { break }
                r.encode(target: tex, time: 7.5 + Float(f) / 60, intensity: 1, commandBuffer: c)
                c.commit()
                if f == n - 1 { c.waitUntilCompleted() }
            }
            let ms = (CACurrentMediaTime() - t0) * 1000 / Double(n)
            print(String(format: "bench %@: %.2f ms per frame at %dx%d (%.0f fps max)", r.variant.name, ms, width, height, 1000 / ms))
            // Redraw the saved frame at the reference time; the benchmark left a later frame in the texture.
            if let c = r.queue.makeCommandBuffer() {
                r.encode(target: tex, time: 7.5, intensity: 1, commandBuffer: c)
                c.commit()
                c.waitUntilCompleted()
            }
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info),
              var out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { print("could not encode"); return }
        if upscale > 1, let big = CGContext(data: nil, width: width * upscale, height: height * upscale, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            big.interpolationQuality = .low // bilinear, like a layer stretched by the compositor
            big.draw(out, in: CGRect(x: 0, y: 0, width: width * upscale, height: height * upscale))
            if let o = big.makeImage() { out = o }
        }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(path)")
    }

    /// A busy fake desktop so the distortion is visible. Laid out in points, drawn at `scale` pixels per point.
    private static func testImage(width: Int, height: Int, scale: CGFloat) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        let pw = Int(CGFloat(width) / scale), ph = Int(CGFloat(height) / scale)
        rep.size = NSSize(width: pw, height: ph)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: CGFloat(ph))
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: pw, height: ph).fill()
        let colors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink, .systemTeal, .systemYellow]
        var i = 0
        for y in stride(from: 40, to: ph - 40, by: 110) {
            for x in stride(from: 40, to: pw - 40, by: 170) {
                colors[i % colors.count].withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 140, height: 84), xRadius: 9, yRadius: 9).fill()
                NSColor.white.setFill()
                let font = NSFont.systemFont(ofSize: 11)
                ("Quarterly notes \(i)" as NSString).draw(at: NSPoint(x: x + 10, y: y + 10), withAttributes: [.font: font, .foregroundColor: NSColor.white])
                for line in 0..<3 {
                    NSRect(x: x + 10, y: y + 34 + line * 14, width: 80 + (line * 29) % 40, height: 5).fill()
                }
                i += 1
            }
        }
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSRect(x: 0, y: 0, width: pw, height: 24).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
