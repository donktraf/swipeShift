//
//  LastLoginMethod.swift
//  swipeShift
//
//  Merkt lokal (UserDefaults, kein Backend), womit sich der User zuletzt angemeldet hat,
//  damit die Landing-/Login-Screens "Last signed in with Google" anzeigen koennen.
//  Bleibt beim Logout bewusst erhalten, wird bei "Delete Account" entfernt.
//

import Foundation

enum LastLoginMethod: String {
    case email, google, apple

    /// Key fuer @AppStorage in Views
    static let storageKey = "lastLoginMethod"

    /// "Last signed in with Google"
    var hintText: String {
        switch self {
        case .email:  return "Last signed in with email"
        case .google: return "Last signed in with Google"
        case .apple:  return "Last signed in with Apple"
        }
    }

    static func save(_ method: LastLoginMethod, defaults: UserDefaults = .standard) {
        defaults.set(method.rawValue, forKey: storageKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    static func current(defaults: UserDefaults = .standard) -> LastLoginMethod? {
        defaults.string(forKey: storageKey).flatMap(LastLoginMethod.init(rawValue:))
    }
}
