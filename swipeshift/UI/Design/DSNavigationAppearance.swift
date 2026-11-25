//
//  DSNavigationAppearance.swift
//  swipeShift
//
//  Navigationsleisten app-weit auf Plus Jakarta Sans + DS-Textfarbe (Large- und Inline-Titel).
//  Aufruf einmalig beim App-Start: `DS.configureAppearance()`.
//

import SwiftUI
import UIKit

extension DS {
    /// UIKit-Appearance ist hier bewusst erlaubt (kein SwiftUI-Aequivalent fuer die Titelschrift unter iOS 17).
    @MainActor
    static func configureAppearance() {
        func font(_ weight: Font.Weight, _ size: CGFloat, fallback: UIFont.Weight) -> UIFont {
            UIFont(name: weight.postScriptName, size: size) ?? .systemFont(ofSize: size, weight: fallback)
        }
        let text = UIColor(Color.text)

        let large: [NSAttributedString.Key: Any] = [
            .font: font(.extrabold, 32, fallback: .heavy), .foregroundColor: text,
        ]
        let inline: [NSAttributedString.Key: Any] = [
            .font: font(.bold, 17, fallback: .bold), .foregroundColor: text,
        ]

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.titleTextAttributes = inline
        standard.largeTitleTextAttributes = large

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = inline
        edge.largeTitleTextAttributes = large

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
    }
}
