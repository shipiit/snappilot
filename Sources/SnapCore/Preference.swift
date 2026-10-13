import Foundation

/// Typed reads/writes of user preferences, falling back to a default when the stored value
/// is missing or has the wrong type (e.g. after a type change between versions).
public enum Preference {
    public static func value<T>(_ key: String, default fallback: T, in store: UserDefaults = .standard) -> T {
        store.object(forKey: key) as? T ?? fallback
    }

    public static func value<E: RawRepresentable>(_ key: String, default fallback: E,
                                                  in store: UserDefaults = .standard) -> E where E.RawValue == String {
        store.string(forKey: key).flatMap(E.init(rawValue:)) ?? fallback
    }

    public static func set<T>(_ value: T, for key: String, in store: UserDefaults = .standard) {
        store.set(value, forKey: key)
    }

    public static func set<E: RawRepresentable>(_ value: E, for key: String,
                                                in store: UserDefaults = .standard) where E.RawValue == String {
        store.set(value.rawValue, forKey: key)
    }
}
