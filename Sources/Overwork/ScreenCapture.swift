import AppKit
import ScreenCaptureKit

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the macOS Screen Recording prompt (once per app identity).
    static func request() { _ = CGRequestScreenCaptureAccess() }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Captures one display at 1x point resolution, excluding this app's own windows.
    static func capture(displayID: CGDirectDisplayID, size: CGSize) async -> CGImage? {
        guard hasPermission else { return nil }
        return await captureDetailed(displayID: displayID, size: size).image
    }

    static func captureDetailed(displayID: CGDirectDisplayID, size: CGSize) async -> (image: CGImage?, error: String?) {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return (nil, "display not found") }
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.width = max(Int(size.width), 1)
            cfg.height = max(Int(size.height), 1)
            cfg.showsCursor = false
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg), nil)
        } catch {
            NSLog("Overwork: screen capture failed: \(error)")
            return (nil, "\(error)")
        }
    }
}
