import Foundation

/// Removing the last sheep empties the current session; opening the app starts a flock again.
public struct FlockPreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["sheepCount": 1, "sheepScale": 1.0, "statusIconStyle": StatusIconStyle.emoji.rawValue])
    }
    public var startingCount: Int { max(1, min(100, defaults.integer(forKey: "sheepCount"))) }
    public var scale: Double {
        let value = defaults.double(forKey: "sheepScale")
        return value.isFinite ? max(0.5, min(3, value)) : 1
    }
    public var statusIconStyle: StatusIconStyle { StatusIconStyle(rawValue: defaults.string(forKey: "statusIconStyle") ?? "") ?? .emoji }
    public func save(count: Int, scale: Double) {
        defaults.set(max(0, min(100, count)), forKey: "sheepCount")
        defaults.set(scale, forKey: "sheepScale")
    }
    public func save(statusIconStyle: StatusIconStyle) { defaults.set(statusIconStyle.rawValue, forKey: "statusIconStyle") }
}
