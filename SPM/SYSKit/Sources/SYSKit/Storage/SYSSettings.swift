import Foundation

/// Typed access to UserDefaults.
public struct SYSSettingsKey<Value> {
    public let name: String
    let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

extension SYSSettingsKey: Sendable where Value: Sendable {}

public final class SYSSettings: @unchecked Sendable {
    public static let shared = SYSSettings()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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

    public subscript(key: SYSSettingsKey<String?>) -> String? {
        get { defaults.object(forKey: key.name) as? String ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

    public subscript(key: SYSSettingsKey<Date?>) -> Date? {
        get { defaults.object(forKey: key.name) as? Date ?? key.defaultValue }
        set { defaults.set(newValue, forKey: key.name) }
    }

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

    public func value<T: Codable>(for key: SYSSettingsKey<T?>) -> T? {
        guard let data = defaults.data(forKey: key.name) else { return key.defaultValue }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func set<T: Codable>(_ value: T?, for key: SYSSettingsKey<T?>) {
        guard let value else { defaults.removeObject(forKey: key.name); return }
        defaults.set(try? JSONEncoder().encode(value), forKey: key.name)
    }

    func remove<T>(_ key: SYSSettingsKey<T>) {
        defaults.removeObject(forKey: key.name)
    }

    func contains<T>(_ key: SYSSettingsKey<T>) -> Bool {
        defaults.object(forKey: key.name) != nil
    }
}
