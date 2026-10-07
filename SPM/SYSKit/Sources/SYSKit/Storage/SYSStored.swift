#if canImport(Combine)
import Combine
import Foundation

/// A value that can live in UserDefaults in its native form.
public protocol SYSDefaultsStorable {
    static func sysRead(from defaults: UserDefaults, key: String) -> Self?
    func sysWrite(to defaults: UserDefaults, key: String)
}

extension Bool: SYSDefaultsStorable {
    public static func sysRead(from defaults: UserDefaults, key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }
    public func sysWrite(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension Int: SYSDefaultsStorable {
    public static func sysRead(from defaults: UserDefaults, key: String) -> Int? {
        defaults.object(forKey: key) as? Int
    }
    public func sysWrite(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension Double: SYSDefaultsStorable {
    public static func sysRead(from defaults: UserDefaults, key: String) -> Double? {
        defaults.object(forKey: key) as? Double
    }
    public func sysWrite(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension String: SYSDefaultsStorable {
    public static func sysRead(from defaults: UserDefaults, key: String) -> String? {
        defaults.object(forKey: key) as? String
    }
    public func sysWrite(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

@propertyWrapper
/// A preference backed by UserDefaults that publishes when it changes.
public struct SYSStored<Value: SYSDefaultsStorable> {
    private let key: String
    private let defaultValue: Value
    private let defaults: UserDefaults

    public init(_ key: String, default defaultValue: Value, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    /// A preference named and defaulted by a shared settings key, so the key and its default are written once.
    public init(_ key: SYSSettingsKey<Value>, defaults: UserDefaults = .standard) {
        self.init(key.name, default: key.defaultValue, defaults: defaults)
    }

    public var wrappedValue: Value {
        get { Value.sysRead(from: defaults, key: key) ?? defaultValue }
        set { newValue.sysWrite(to: defaults, key: key) }
    }

    public static subscript<Enclosing: ObservableObject>(
        _enclosingInstance instance: Enclosing,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Enclosing, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Self>
    ) -> Value where Enclosing.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let wrapper = instance[keyPath: storageKeyPath]
            return Value.sysRead(from: wrapper.defaults, key: wrapper.key) ?? wrapper.defaultValue
        }
        set {
            let wrapper = instance[keyPath: storageKeyPath]
            instance.objectWillChange.send()
            newValue.sysWrite(to: wrapper.defaults, key: wrapper.key)
        }
    }
}
#endif
