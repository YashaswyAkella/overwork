import Foundation

struct Settings: Codable, Equatable {
    var workMinutes = 50
    var breakMinutes = 2
    var idleMinutes = 5
    var launchAtLogin = false
    var respectCalls = true

    init() {}

    // Tolerant decoding so settings saved by an older version keep working when keys are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workMinutes = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 50
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 2
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 5
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        respectCalls = try c.decodeIfPresent(Bool.self, forKey: .respectCalls) ?? true
    }

    var workInterval: TimeInterval { Double(workMinutes) * 60 }
    var breakLength: TimeInterval { Double(breakMinutes) * 60 }
    var idleThreshold: TimeInterval { Double(idleMinutes) * 60 }

    private static let key = "overwork.settings"
    static var exists: Bool { UserDefaults.standard.data(forKey: key) != nil }

    static func load() -> Settings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(d, forKey: Settings.key)
        }
    }
}
