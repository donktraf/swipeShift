//
//  LastLoginHint.swift
//  swipeShift
//
//  Dezenter Hinweis "Last signed in with Google" unter der passenden Login-Option.
//  Liest die lokal gemerkte Methode (siehe Security/LastLoginMethod.swift).
//

import SwiftUI

struct LastLoginHint: View {
    let method: LastLoginMethod
    @AppStorage(LastLoginMethod.storageKey) private var stored: String = ""

    var body: some View {
        if stored == method.rawValue {
            Label(method.hintText, systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(method.hintText)
        }
    }
}
