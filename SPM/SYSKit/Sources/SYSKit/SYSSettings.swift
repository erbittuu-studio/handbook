import Foundation

/// Typed access to UserDefaults.
///
/// Exists because raw `UserDefaults` appears in 16 files across our apps, each
/// with its own hand-written key string. A typo in one of those compiles, runs,
/// and silently reads nothing — you lose the value and never see an error.
/// Declaring keys once makes that a compile error instead.
///
///     extension SYSSettingsKey {
///         static let hasSeenTutorial = SYSSettingsKey<Bool>("hasSeenTutorial", default: false)
///     }
///
///     SYSSettings.shared[.hasSeenTutorial] = true
public struct SYSSettingsKey<Value> {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public final class SYSSettings {
    public static let shared = SYSSettings()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Property-list types

    public subscript(key: SYSSettingsKey<Bool>) -> Bool {
        get { defaults.object(forKey: key.name) as? Bool ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<Int>) -> Int {
        get { defaults.object(forKey: key.name) as? Int ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<Double>) -> Double {
        get { defaults.object(forKey: key.name) as? Double ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<String>) -> String {
        get { defaults.object(forKey: key.name) as? String ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<Date>) -> Date {
        get { defaults.object(forKey: key.name) as? Date ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    /// Optionals, so "never set" stays distinguishable from "set to a default".
    public subscript(key: SYSSettingsKey<String?>) -> String? {
        get { defaults.object(forKey: key.name) as? String ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<Date?>) -> Date? {
        get { defaults.object(forKey: key.name) as? Date ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    // MARK: Native arrays and dictionaries
    //
    // UserDefaults stores these as plain plist arrays/dictionaries, not JSON —
    // a different wire format from the Codable path below. That distinction
    // is why these exist: an app that already holds one of these natively
    // (most apps had at least one before adopting SYSSettings) can move it
    // here and keep reading exactly what it already wrote. Routing it through
    // the Codable path instead would read back nil on the first launch after
    // the change, since a native array isn't the JSON `Data` that path expects.

    public subscript(key: SYSSettingsKey<[String]>) -> [String] {
        get { defaults.stringArray(forKey: key.name) ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<[Int]>) -> [Int] {
        get { defaults.array(forKey: key.name) as? [Int] ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<[String: String]>) -> [String: String] {
        get { defaults.dictionary(forKey: key.name) as? [String: String] ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<[String: Int]>) -> [String: Int] {
        get { defaults.dictionary(forKey: key.name) as? [String: Int] ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    // MARK: Codable

    /// For anything that isn't a plist type. Stored as JSON.
    public func value<T: Codable>(for key: SYSSettingsKey<T?>) -> T? {
        guard let data = defaults.data(forKey: key.name) else { return key.defaultValue }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func set<T: Codable>(_ value: T?, for key: SYSSettingsKey<T?>) {
        guard let value else { defaults.removeObject(forKey: key.name); return }
        defaults.set(try? JSONEncoder().encode(value), forKey: key.name)
    }

    public func remove<T>(_ key: SYSSettingsKey<T>) {
        defaults.removeObject(forKey: key.name)
    }

    public func contains<T>(_ key: SYSSettingsKey<T>) -> Bool {
        defaults.object(forKey: key.name) != nil
    }
}
