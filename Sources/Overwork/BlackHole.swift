import MetalKit

struct HoleUniforms {
    var time: Float
    var aspect: Float
    var intensity: Float
    var hasImage: Float
    var center: SIMD2<Float>
    var pixel: SIMD2<Float> = .zero  // x: one pixel in NDC units (2 / height); y: screenshot height in texels
    var elev: Float      // camera elevation above the disk plane, radians
    var roll: Float      // camera roll, radians
    var disk: Float      // 1 = accretion disk present, 0 = bare lensing void
    var warmth: Float    // 0 = white-gold, 1 = deep orange
    var diskOut: Float   // outer disk radius in Schwarzschild radii
    var knots: Float     // strength of the three bright knots seen in Sgr A*
    var speed: Float     // orbital motion multiplier for the gas texture
    var hot: Float       // 1 = blue-white quasar core, 0 = gold
}

/// One of the looks the hole can take, each modelled on a real black hole. A random one is picked for every break.
struct HoleVariant {
    let name: String
    let elev: Float      // camera elevation above the disk plane (0 = edge on, pi/2 = face on)
    let roll: Float
    let disk: Float
    let warmth: Float
    let diskOut: Float
    let knots: Float
    let speed: Float
    let hot: Float
    /// Vertical offset of the timer as a fraction of screen height, so it sits in the dark part of the shadow.
    let hudOffset: CGFloat

    static let all: [HoleVariant] = [
        // TON 618: a hyperluminous quasar 66 billion solar masses heavy. Only simulations exist, so: edge on, enormous, white hot.
        HoleVariant(name: "TON 618", elev: 0.10, roll: -0.10, disk: 1, warmth: 0.35, diskOut: 9.5, knots: 0, speed: 0.6, hot: 1, hudOffset: -0.07),
        // M87*: the 2019 Event Horizon Telescope image. Viewed 17 degrees from the pole, thick orange ring, brighter to the south.
        HoleVariant(name: "M87*", elev: 1.27, roll: 3.95, disk: 1, warmth: 0.9, diskOut: 5.5, knots: 0.15, speed: 0.5, hot: 0, hudOffset: 0),
        // Sagittarius A*: the 2022 EHT image. Thinner ring with three bright knots, yellower, and gas that moves in minutes.
        HoleVariant(name: "Sagittarius A*", elev: 1.05, roll: 0.6, disk: 1, warmth: 0.7, diskOut: 4.6, knots: 1, speed: 2.5, hot: 0, hudOffset: 0),
    ]
    static func random() -> HoleVariant { all.randomElement()! }
}

/// Owns the Metal pipeline and the screenshot texture. Used by the live view and the offscreen test.
final class BlackHoleRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let sampler: MTLSamplerState
    let texture: MTLTexture?
    var variant: HoleVariant = .all[0]

    init?(device: MTLDevice, image: CGImage?, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            var source = blackHoleShaderSource
            // Test-only: OVERWORK_TRUTH renders a slow, very fine-stepped reference for accuracy checks.
            if ProcessInfo.processInfo.environment["OVERWORK_TRUTH"] != nil {
                source = source.replacingOccurrences(of: "constant int MAX_STEPS = 220;", with: "constant int MAX_STEPS = 6000;")
                    .replacingOccurrences(of: "* 0.09, 0.025, 1.0);", with: "* 0.09, 0.025, 1.0) / 7.0;")
            }
            let lib = try device.makeLibrary(source: source, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "blackhole_vertex")
            desc.fragmentFunction = lib.makeFunction(name: "blackhole_fragment")
            desc.colorAttachments[0].pixelFormat = pixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("Overwork: shader build failed: \(error)")
            return nil
        }
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear   // smooth, grain-free blur when the smear samples coarser mip levels
        sd.sAddressMode = .mirrorRepeat
        sd.tAddressMode = .mirrorRepeat
        guard let s = device.makeSamplerState(descriptor: sd) else { return nil }
        sampler = s
        texture = image.flatMap { BlackHoleRenderer.makeTexture(device: device, image: $0) }
    }

    /// Re-draws the image into a BGRA8 buffer and uploads it, which works for any CGImage source.
    static func makeTexture(device: MTLDevice, image: CGImage) -> MTLTexture? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: true)
        td.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: td) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: &bytes, bytesPerRow: w * 4)
        // Build the mip chain on the GPU so blurred lookups are filtered instead of noisy.
        if let q = device.makeCommandQueue(), let cb = q.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: tex)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        return tex
    }

    func encode(target: MTLTexture, time: Float, intensity: Float, commandBuffer: MTLCommandBuffer) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pipeline)
        var u = HoleUniforms(
            time: time,
            aspect: Float(target.width) / Float(target.height),
            intensity: intensity,
            hasImage: texture == nil ? 0 : 1,
            center: SIMD2(0.5 + 0.02 * sin(time * 0.31), 0.5 + 0.015 * cos(time * 0.23)),
            pixel: SIMD2(2 / Float(max(target.height, 1)), Float(texture?.height ?? 1)),
            elev: variant.elev, roll: variant.roll, disk: variant.disk, warmth: variant.warmth, diskOut: variant.diskOut,
            knots: variant.knots, speed: variant.speed, hot: variant.hot
        )
        enc.setFragmentBytes(&u, length: MemoryLayout<HoleUniforms>.stride, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }
}

/// Full-screen Metal view that animates the black hole over the captured screenshot.
final class BlackHoleView: MTKView {
    private var renderer: BlackHoleRenderer?
    private let start = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var intensity: Float = 0
    private var frames = 0
    /// Pixels per point of the display (2 on Retina). The hole is rendered at full native resolution.
    private var backingScale: CGFloat
    /// Drops below 1 only if a slow GPU can't keep up at native resolution.
    private var quality: CGFloat = 1
    private var avgDt: Float = 1.0 / 60.0
    private var settle = 0
    /// 1 = fully open, 0 = closed. The view eases toward this every frame.
    var targetIntensity: Float = 1 {
        didSet {
            if targetIntensity == 0, frames > 0 {
                let secs = CACurrentMediaTime() - start
                let line = String(format: "%d frames in %.1fs = %.1f fps at %dx%d\n", frames, secs, Double(frames) / secs,
                                  Int(drawableSize.width), Int(drawableSize.height))
                NSLog("Overwork: %@", line)
                if let path = ProcessInfo.processInfo.environment["OVERWORK_FPS_LOG"] {
                    try? line.write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    init(frame: CGRect, image: CGImage?, variant: HoleVariant, backingScale: CGFloat) {
        let dev = MTLCreateSystemDefaultDevice()
        self.backingScale = max(backingScale, 1)
        super.init(frame: frame, device: dev)
        if let dev { renderer = BlackHoleRenderer(device: dev, image: image); renderer?.variant = variant }
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        autoResizeDrawable = false
        layer?.contentsScale = self.backingScale
        updateDrawableSize()
        preferredFramesPerSecond = 60
        isPaused = false
        enableSetNeedsDisplay = false
        layer?.isOpaque = true
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    private func updateDrawableSize() {
        let s = backingScale * quality
        drawableSize = CGSize(width: max(bounds.width * s, 1), height: max(bounds.height * s, 1))
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let w = window { backingScale = w.backingScaleFactor; layer?.contentsScale = backingScale; updateDrawableSize() }
    }

    /// Native resolution when the GPU keeps up; if the average frame rate stays under 60,
    /// render slightly below native until it does, rather than stutter.
    private func adaptQuality(dt: Float) {
        avgDt += (min(dt, 0.1) - avgDt) * 0.08
        settle += 1
        guard settle > 90, quality > 0.6 else { return }
        if avgDt > 1.0 / 52.0 {
            quality = max(0.6, quality * 0.85)
            avgDt = 1.0 / 60.0
            settle = 15
            updateDrawableSize()
            NSLog("Overwork: rendering at %.0f%% of native resolution to keep 60 fps", quality * 100)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let now = CACurrentMediaTime()
        let dt = Float(now - last)
        last = now
        frames += 1
        adaptQuality(dt: dt)
        let speed: Float = targetIntensity > intensity ? 1 / 2.8 : 1 / 0.9
        if intensity < targetIntensity {
            intensity = min(targetIntensity, intensity + dt * speed)
        } else {
            intensity = max(targetIntensity, intensity - dt * speed)
        }
        guard let renderer, let drawable = currentDrawable, let cb = renderer.queue.makeCommandBuffer() else { return }
        renderer.encode(target: drawable.texture, time: Float(now - start), intensity: intensity, commandBuffer: cb)
        cb.present(drawable)
        cb.commit()
    }
}

let blackHoleShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut blackhole_vertex(uint vid [[vertex_id]]) {
    float2 p[6] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(-1,1), float2(1,-1), float2(1,1) };
    VOut o;
    o.pos = float4(p[vid], 0, 1);
    o.uv = float2(p[vid].x * 0.5 + 0.5, 0.5 - p[vid].y * 0.5);
    return o;
}

struct Uniforms { float time; float aspect; float intensity; float hasImage; float2 center; float2 pixel;
                  float elev; float roll; float disk; float warmth; float diskOut; float knots; float speed; float hot; };

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1,0)), c = hash21(i + float2(0,1)), d = hash21(i + float2(1,1));
    float2 u = f*f*(3.0-2.0*f);
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.1 + 7.3; a *= 0.5; }
    return v;
}

float3 world(float2 uv, float lod, float t, float hasImage, texture2d<float> tex, sampler s) {
    if (hasImage > 0.5) return tex.sample(s, uv, level(lod)).rgb;
    uv = abs(fract(uv * 0.5) * 2.0 - 1.0); // mirror, like the sampler does
    float2 g = uv * float2(180.0, 100.0);
    float2 cell = floor(g);
    float h = hash21(cell);
    float3 col = float3(0.012, 0.012, 0.025);
    if (h > 0.965) {
        float2 c = fract(g) - 0.5;
        float d = length(c);
        float tw = 0.55 + 0.45 * sin(t * 2.0 + h * 60.0);
        col += tw * smoothstep(0.28, 0.0, d) * float3(0.8, 0.85, 1.0);
    }
    return col;
}

// Units: Schwarzschild radius = 1. Horizon at r = 1, photon sphere at 1.5, shadow edge ~2.6.
constant float DISK_IN  = 2.4;
constant float R_INFLUENCE = 15.0;
constant float CAM_DIST = 20.0;
constant float FOCAL = 2.6;
constant float B_CRIT = 2.598076;   // critical impact parameter, 3*sqrt(3)/2: rays below it fall in
constant int MAX_STEPS = 220;

// Thin disk emission at radius r, azimuth phi, seen along photon direction v (unit, pointing away from camera).
float3 diskEmission(float r, float phi, float3 v, float t, constant Uniforms& u) {
    float warmth = u.warmth, diskOut = u.diskOut;
    float x = saturate((r - DISK_IN) / (diskOut - DISK_IN));
    // Keplerian differential rotation of the gas bands: slow enough to drift, not flicker.
    float omega = 0.55 * pow(r, -1.5);
    float a = phi + t * omega * 1.3 * u.speed;
    // Noise sampled on a circle so it is periodic in angle: no seam where the angle wraps.
    float2 q = float2(cos(a), sin(a));
    float band = fbm(float2(r * 1.6 - t * 0.03, 0.0) + q * 1.6);
    float fine = vnoise(float2(r * 9.0, 0.0) + q * 5.0);
    float tex = 0.15 + 1.4 * pow(band, 1.6) + 0.35 * fine * band;
    // Three bright knots drifting around the ring, as in the Sgr A* image.
    float lobe = pow(0.5 + 0.5 * cos(3.0 * (phi + t * 0.12 * u.speed) + 0.8), 2.5);
    tex *= 1.0 + u.knots * (2.2 * lobe - 0.45);
    // Ragged outer edge: the disk thins out unevenly instead of ending in a clean line.
    float edge = smoothstep(1.0, 0.55 + 0.25 * band, x);
    // Brightness falls off outward, with a bright hot inner rim that fades in softly.
    float bright = tex * (0.3 + 1.7 * pow(1.0 - x, 1.6)) * smoothstep(0.0, 0.12, x) * edge;
    // Colour: white-gold to amber, pushed toward orange by warmth.
    float3 colIn = mix(float3(1.0, 0.95, 0.85), float3(1.0, 0.82, 0.55), warmth);
    colIn = mix(colIn, float3(0.82, 0.9, 1.0), u.hot * (1.0 - x) * 0.9);   // quasar core runs blue-white
    float3 colOut = mix(float3(1.0, 0.60, 0.28), float3(1.0, 0.40, 0.08), warmth);
    float3 col = mix(colIn, colOut, pow(x, 0.7));
    bright *= 1.0 + 0.5 * u.hot * (1.0 - x);
    // Relativistic Doppler beaming: gas moves tangentially, approaching side is brighter and hotter.
    float3 tangent = float3(-sin(phi), 0.0, cos(phi));
    float speed = sqrt(0.5 / r);
    float gamma = rsqrt(1.0 - speed * speed);
    float delta = 1.0 / (gamma * (1.0 + speed * dot(tangent, v)));
    float beam = pow(delta, 3.0);
    float3 hot = mix(float3(0.9, 0.93, 1.0), float3(1.0, 0.9, 0.75), warmth);
    col = mix(col, hot, saturate((delta - 1.0) * 1.0));
    return col * bright * beam;
}

float diskAlpha(float r, float diskOut) {
    float x = saturate((r - DISK_IN) / (diskOut - DISK_IN));
    // Opacity follows the emission falloff, so the faint outer disk never shows as a band.
    return 0.97 * smoothstep(0.0, 0.1, x) * smoothstep(1.0, 0.6, x);
}

struct Camera { float3 pos; float3 fwd; float3 right; float3 up; float D; };

// What one ray found: disk light in front of everything, how much of the background still shows,
// and where on the screenshot the background comes from.
struct Hit { float3 disk; float trans; float bgWeight; float2 ndcOut; };

Hit traceRay(float2 ndc, Camera cam, constant Uniforms& u, float edgeSoftness) {
    float3 dir = normalize(cam.fwd * FOCAL + cam.right * ndc.x + cam.up * ndc.y);
    float3 p = cam.pos;
    float3 v = dir;
    Hit h;
    h.disk = float3(0.0);
    h.trans = 1.0;
    bool captured = false;

    // The impact parameter is conserved along the ray, so the shadow edge is known exactly.
    float impact = length(cross(cam.pos, dir));

    float b = dot(p, v);
    float c = dot(p, p) - R_INFLUENCE * R_INFLUENCE;
    float disc = b * b - c;
    if (disc > 0.0) {
        p += v * (-b - sqrt(disc));
        float3 hv = cross(p, v);
        float h2 = dot(hv, hv);
        // Leapfrog (kick-drift-kick): second-order accurate, one force evaluation per step,
        // so long strides far from the hole stay on the true light path.
        float r2a = dot(p, p);
        float3 acc = -1.5 * h2 * p / (r2a * r2a * sqrt(r2a));
        for (int i = 0; i < MAX_STEPS; i++) {
            float r2 = dot(p, p);
            if (r2 < 1.0) { captured = true; break; }
            if (r2 > R_INFLUENCE * R_INFLUENCE + 1.0 && dot(p, v) > 0.0) break;
            float r = sqrt(r2);
            // Finer steps near the photon sphere, where paths are most sensitive; long strides far out.
            float step = clamp(r * 0.06 * smoothstep(1.2, 3.0, r) + 0.025 + max(r - 5.0, 0.0) * 0.09, 0.025, 1.0);
            float3 vh = v + acc * (0.5 * step);
            float3 pn = p + vh * step;
            float rn2 = dot(pn, pn);
            float3 accn = -1.5 * h2 * pn / (rn2 * rn2 * sqrt(rn2));
            float3 vn = vh + accn * (0.5 * step);
            acc = accn;
            if (u.disk > 0.5 && p.y * pn.y < 0.0) {
                float f = p.y / (p.y - pn.y);
                float3 hit = mix(p, pn, f);
                float rh = length(hit.xz);
                if (rh > DISK_IN && rh < u.diskOut) {
                    float phi = atan2(hit.z, hit.x);
                    float3 e = diskEmission(rh, phi, normalize(vn), u.time, u);
                    float al = diskAlpha(rh, u.diskOut);
                    h.disk += h.trans * e * al;
                    h.trans *= (1.0 - al);
                    if (h.trans < 0.01) break;
                }
            }
            p = pn;
            v = vn;
        }
    }

    // Anti-aliased shadow edge: fade the background out across a pixel at the critical impact parameter.
    h.bgWeight = captured ? 0.0 : smoothstep(B_CRIT - edgeSoftness, B_CRIT + edgeSoftness, impact);
    float3 vd = normalize(v);
    float z = max(dot(vd, cam.fwd), 0.05);
    h.ndcOut = float2(dot(vd, cam.right), dot(vd, cam.up)) / z * FOCAL;
    return h;
}

// The screenshot seen along a bent ray, smeared radially (spaghettification).
// `footprintUV` is how much screenshot one output pixel covers; it picks a mip level so nothing aliases.
float3 background(float2 uv, float2 ndc, float2 ndcOut, float footprintUV, float ease, int N,
                  constant Uniforms& u, texture2d<float> tex, sampler s) {
    // Full lensing near the hole, gentler toward the screen edges so the desktop stays readable there.
    float gain = mix(0.25, 1.0, smoothstep(1.6, 0.55, length(ndc)));
    float2 bent = ndc + (ndcOut - ndc) * gain;
    float2 uvOut = u.center + float2(bent.x / u.aspect, -bent.y) * 0.5;
    float2 radial = normalize(uv - u.center + 1e-5);
    float defl = length(bent - ndc);
    float streak = min(defl * defl * 0.6, 0.06) + 0.004 * ease;
    // Each tap is blurred enough to overlap its neighbours, so the smear is smooth rather than grainy.
    float texH = u.pixel.y;
    float spacing = max(streak / float(N), footprintUV * gain);
    float lod = clamp(log2(max(spacing * texH, 1.0)), 0.0, 9.0);
    float3 bg = float3(0.0);
    for (int i = 0; i < N; i++) {
        float f = (float(i) + 0.5) / float(N) - 0.5;
        bg += world(uvOut + radial * (f * streak), lod, u.time, u.hasImage, tex, s);
    }
    bg /= float(N);
    // Rays that land far beyond the screen edge see a mirrored, dimmer copy of it.
    float outside = max(max(-uvOut.x, uvOut.x - 1.0), max(-uvOut.y, uvOut.y - 1.0));
    bg *= 1.0 - 0.8 * smoothstep(0.0, 0.3, outside);
    bg *= mix(1.0, mix(0.55, 0.32, u.disk), ease);
    float2 vc = (uv - 0.5) * float2(u.aspect, 1.0);
    bg *= 1.0 - 0.55 * ease * smoothstep(0.35, 1.1, length(vc));
    return bg;
}

fragment float4 blackhole_fragment(VOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]],
                                   texture2d<float> tex [[texture(0)]],
                                   sampler s [[sampler(0)]]) {
    float k = clamp(u.intensity, 0.0, 1.0);
    float ease = k * k * (3.0 - 2.0 * k);
    float grow = max(ease, 0.01);
    float2 uv = in.uv;

    // Camera, elevated above the disk plane and pulled far away while the hole "grows".
    Camera cam;
    cam.D = CAM_DIST / grow;
    cam.pos = float3(0.0, cam.D * sin(u.elev), -cam.D * cos(u.elev));
    cam.fwd = normalize(-cam.pos);
    float3 right0 = normalize(cross(float3(0.0, 1.0, 0.0), cam.fwd));
    float3 up0 = cross(cam.fwd, right0);
    float cr = cos(u.roll), sr = sin(u.roll);
    cam.right = right0 * cr + up0 * sr;
    cam.up = -right0 * sr + up0 * cr;

    float pix = u.pixel.x;                         // one output pixel in NDC units
    float2 ndc = float2((uv.x - u.center.x) * 2.0 * u.aspect, -(uv.y - u.center.y) * 2.0);
    float bPerPixel = pix * cam.D / FOCAL;         // how much impact parameter one pixel spans
    float3 dir0 = normalize(cam.fwd * FOCAL + cam.right * ndc.x + cam.up * ndc.y);
    float impact = length(cross(cam.pos, dir0));

    float3 col;
    // Near the shadow edge light paths change wildly between neighbouring pixels, so use several rays:
    // 16 in the few pixels around the critical edge (the photon ring is thinner than a pixel), 4 in the band around it.
    float fromEdge = abs(impact - B_CRIT);
    int g = fromEdge < 5.0 * bPerPixel ? 4 : (impact > B_CRIT - 0.2 && impact < B_CRIT + 0.7 ? 2 : 1);
    if (g > 1) {
        // A rotated regular grid: good coverage of both horizontal and vertical edges.
        const float ca = 0.894427, sa = 0.447214;  // rotation by atan(1/2)
        Hit hits[16];
        int n = g * g;
        float2 mean = float2(0.0);
        for (int j = 0; j < n; j++) {
            float2 o = (float2(float(j % g), float(j / g)) + 0.5) / float(g) - 0.5;
            o = float2(ca * o.x - sa * o.y, sa * o.x + ca * o.y);
            hits[j] = traceRay(ndc + o * pix, cam, u, 0.5 * bPerPixel / float(g));
            mean += hits[j].ndcOut;
        }
        mean /= float(n);
        // How far apart the rays land on the screenshot tells how blurred each lookup must be.
        float spread = 0.0;
        for (int j = 0; j < n; j++) spread = max(spread, length(hits[j].ndcOut - mean));
        float footprintUV = max(spread, pix) * 0.5;
        col = float3(0.0);
        for (int j = 0; j < n; j++) {
            float3 bg = hits[j].bgWeight > 0.0 && hits[j].trans > 0.01
                ? background(uv, ndc, hits[j].ndcOut, footprintUV, ease, g == 4 ? 2 : 4, u, tex, s) : float3(0.0);
            col += hits[j].disk * ease + hits[j].trans * hits[j].bgWeight * bg;
        }
        col /= float(n);
    } else {
        Hit h = traceRay(ndc, cam, u, bPerPixel);
        float3 bg = h.bgWeight > 0.0 && h.trans > 0.01
            ? background(uv, ndc, h.ndcOut, pix * 0.5, ease, 8, u, tex, s) : float3(0.0);
        col = h.disk * ease + h.trans * h.bgWeight * bg;
    }

    // Photon ring and halo in screen space, for the glow a single pass can't bloom.
    float rShadow = 2.6 / cam.D * FOCAL;
    float rScreen = length(ndc);
    float3 ringCol = mix(float3(1.0, 0.85, 0.6), float3(1.0, 0.55, 0.2), u.warmth);
    float ringW = rShadow * 0.06 + pix;
    float ring = exp(-((rScreen - rShadow) / ringW) * ((rScreen - rShadow) / ringW));
    float halo = exp(-max(rScreen - rShadow, 0.0) / (rShadow * 0.35 + 1e-4)) * smoothstep(rShadow - pix, rShadow + pix, rScreen);
    float ringStrength = mix(0.0, 1.1, 1.0 - u.disk);    // disk variants get their ring from the physics
    float haloStrength = mix(0.08, 0.22, 1.0 - u.disk);
    float flicker = 0.9 + 0.1 * sin(u.time * 3.0 + rScreen * 40.0);
    col += ringCol * (ring * ringStrength + halo * haloStrength) * flicker * ease;

    // Filmic-ish tone map so the disk glows white without clipping harshly.
    col = 1.0 - exp(-col * 1.15);
    return float4(col, 1.0);
}
"""
