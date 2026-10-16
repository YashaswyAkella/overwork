import MetalKit

struct HoleUniforms {
    var time: Float
    var aspect: Float
    var intensity: Float
    var hasImage: Float
    var center: SIMD2<Float>
    var pad: SIMD2<Float> = .zero
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
            let lib = try device.makeLibrary(source: blackHoleShaderSource, options: nil)
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
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: td) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: &bytes, bytesPerRow: w * 4)
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

    init(frame: CGRect, image: CGImage?, variant: HoleVariant) {
        let dev = MTLCreateSystemDefaultDevice()
        super.init(frame: frame, device: dev)
        if let dev { renderer = BlackHoleRenderer(device: dev, image: image); renderer?.variant = variant }
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        autoResizeDrawable = false
        drawableSize = CGSize(width: max(frame.width, 1), height: max(frame.height, 1)) // render at 1x; the blur hides it
        preferredFramesPerSecond = 60
        isPaused = false
        enableSetNeedsDisplay = false
        layer?.isOpaque = true
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        drawableSize = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
    }

    override func draw(_ dirtyRect: NSRect) {
        let now = CACurrentMediaTime()
        let dt = Float(now - last)
        last = now
        frames += 1
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

struct Uniforms { float time; float aspect; float intensity; float hasImage; float2 center; float2 pad;
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

float3 world(float2 uv, float t, float hasImage, texture2d<float> tex, sampler s) {
    if (hasImage > 0.5) return tex.sample(s, uv).rgb;
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

fragment float4 blackhole_fragment(VOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]],
                                   texture2d<float> tex [[texture(0)]],
                                   sampler s [[sampler(0)]]) {
    float k = clamp(u.intensity, 0.0, 1.0);
    float ease = k * k * (3.0 - 2.0 * k);
    float grow = max(ease, 0.01);
    float2 uv = in.uv;

    // Camera, elevated slightly above the disk plane and pulled far away while the hole "grows".
    float D = CAM_DIST / grow;
    float3 camPos = float3(0.0, D * sin(u.elev), -D * cos(u.elev));
    float3 fwd = normalize(-camPos);
    float3 right0 = normalize(cross(float3(0.0, 1.0, 0.0), fwd));
    float3 up0 = cross(fwd, right0);
    float cr = cos(u.roll), sr = sin(u.roll);
    float3 right = right0 * cr + up0 * sr;
    float3 up = -right0 * sr + up0 * cr;

    float2 ndc = float2((uv.x - u.center.x) * 2.0 * u.aspect, -(uv.y - u.center.y) * 2.0);
    float3 dir = normalize(fwd * FOCAL + right * ndc.x + up * ndc.y);

    float3 p = camPos;
    float3 v = dir;
    float3 col = float3(0.0);
    float trans = 1.0;
    bool captured = false;

    // Only rays that pass near the hole are marched; the rest go straight to the background.
    float b = dot(p, v);
    float c = dot(p, p) - R_INFLUENCE * R_INFLUENCE;
    float disc = b * b - c;
    if (disc > 0.0) {
        p += v * (-b - sqrt(disc));
        float3 h = cross(p, v);
        float h2 = dot(h, h);
        for (int i = 0; i < 160; i++) {
            float r2 = dot(p, p);
            if (r2 < 1.0) { captured = true; break; }
            if (r2 > R_INFLUENCE * R_INFLUENCE + 1.0 && dot(p, v) > 0.0) break;
            float r = sqrt(r2);
            float step = clamp(r * 0.07, 0.035, 0.35);
            float3 a = -1.5 * h2 * p / (r2 * r2 * r);
            float3 vn = v + a * step;
            float3 pn = p + vn * step;
            if (u.disk > 0.5 && p.y * pn.y < 0.0) {
                float f = p.y / (p.y - pn.y);
                float3 hit = mix(p, pn, f);
                float rh = length(hit.xz);
                if (rh > DISK_IN && rh < u.diskOut) {
                    float phi = atan2(hit.z, hit.x);
                    float3 e = diskEmission(rh, phi, normalize(vn), u.time, u);
                    float al = diskAlpha(rh, u.diskOut);
                    col += trans * e * al;
                    trans *= (1.0 - al);
                    if (trans < 0.01) break;
                }
            }
            p = pn;
            v = vn;
        }
    }
    col *= ease;

    // Background: the screen itself, seen through the bent ray.
    float3 bg = float3(0.0);
    if (!captured && trans > 0.01) {
        float3 vd = normalize(v);
        float z = max(dot(vd, fwd), 0.05);
        float2 ndcOut = float2(dot(vd, right), dot(vd, up)) / z * FOCAL;
        // Full lensing near the hole, gentler toward the screen edges so the desktop stays readable there.
        float gain = mix(0.25, 1.0, smoothstep(1.6, 0.55, length(ndc)));
        ndcOut = ndc + (ndcOut - ndc) * gain;
        float2 uvOut = u.center + float2(ndcOut.x / u.aspect, -ndcOut.y) * 0.5;
        // Spaghettification: smear the sample along the radial direction by how much the ray was bent.
        float2 radial = normalize(uv - u.center + 1e-5);
        float defl = length(ndcOut - ndc);
        float streak = min(defl * defl * 0.6, 0.06) + 0.004 * ease; // grows fast only where the bending is strong
        const int N = 8;
        float seed = hash21(uv * 1337.0);
        for (int i = 0; i < N; i++) {
            float f = (float(i) + seed) / float(N) - 0.5;
            float2 off = radial * (f * streak);
            bg += world(uvOut + off, u.time, u.hasImage, tex, s);
        }
        bg /= float(N);
        // Rays that land far beyond the screen edge see a mirrored, dimmer copy of it.
        float outside = max(max(-uvOut.x, uvOut.x - 1.0), max(-uvOut.y, uvOut.y - 1.0));
        bg *= 1.0 - 0.8 * smoothstep(0.0, 0.3, outside);
        bg *= mix(1.0, mix(0.55, 0.32, u.disk), ease); // the void keeps the screen brighter: it's the show
        float2 vc = (uv - 0.5) * float2(u.aspect, 1.0);
        bg *= 1.0 - 0.55 * ease * smoothstep(0.35, 1.1, length(vc));
    }
    col += trans * bg;

    // Photon ring and halo in screen space: softens the shadow edge and adds the glow a single pass can't bloom.
    float rShadow = 2.6 / D * FOCAL;
    float rScreen = length(ndc);
    float3 ringCol = mix(float3(1.0, 0.85, 0.6), float3(1.0, 0.55, 0.2), u.warmth);
    float ring = exp(-pow((rScreen - rShadow) / (rShadow * 0.06 + 1e-4), 2.0));
    float halo = exp(-max(rScreen - rShadow, 0.0) / (rShadow * 0.35 + 1e-4)) * step(rShadow, rScreen);
    float ringStrength = mix(0.0, 1.1, 1.0 - u.disk);    // disk variants get their ring from the physics
    float haloStrength = mix(0.08, 0.22, 1.0 - u.disk);
    float flicker = 0.9 + 0.1 * sin(u.time * 3.0 + rScreen * 40.0);
    col += ringCol * (ring * ringStrength + halo * haloStrength) * flicker * ease;

    // Filmic-ish tone map so the disk glows white without clipping harshly.
    col = 1.0 - exp(-col * 1.15);
    return float4(col, 1.0);
}
"""
