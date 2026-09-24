#if canImport(Combine)
import Combine
import Foundation

/// A value that can live in `UserDefaults` in its native form.
///
/// Native matters: these keys are usually inherited from an older version of the
/// app, where a `Bool` was written as a `Bool`. Encoding it as JSON would read as
/// "no value" on every existing install and silently reset the user's settings on
/// upgrade.
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

/// A preference backed by `UserDefaults` that publishes when it changes.
///
/// The pattern it replaces was four steps per setting — declare a key, register a
/// default, read it in `init`, write it back in `didSet` — repeated for every
/// toggle in every app. Twenty-odd lines that do nothing but move a bool, and
/// four separate chances to typo a key or forget the default.
///
/// ```swift
/// final class SettingsStore: ObservableObject {
///     @SYSStored("IS_MUSIC_ON", default: true) var isMusicOn: Bool
/// }
/// ```
///
/// Reads and writes the key in its native form, so keys inherited from an older
/// build keep working and an upgrade does not quietly reset anyone's settings.
/// The default applies only when the key is absent — a stored `false` is a real
/// value, not a missing one, which is the bug `defaults.bool(forKey:)` invites.
@propertyWrapper
public struct SYSStored<Value: SYSDefaultsStorable> {
    private let key: String
    private let defaultValue: Value
    private let defaults: UserDefaults

    public init(_ key: String, default defaultValue: Value, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    /// Unused, but required: the enclosing-instance subscript below is what
    /// actually runs when the wrapper is a property of an `ObservableObject`.
    public var wrappedValue: Value {
        get { Value.sysRead(from: defaults, key: key) ?? defaultValue }
        set { newValue.sysWrite(to: defaults, key: key) }
    }

    /// Publishes on the enclosing object before writing, so SwiftUI redraws.
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
