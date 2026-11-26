//
//  DSColor.swift
//  swipeShift
//
//  Design-System Etappe 1: Farb-Tokens (hell/dunkel als dynamische Farben).
//

import SwiftUI
import UIKit

/// Namespace des neuen Design-Systems. Tokens liegen in DSColor/DSFont/DSMetrics/DSHaptics.
enum DS {}

/// Markenfarbe an EINER Stelle austauschbar. Zum Umfaerben nur diese Werte aendern.
enum Brand {
    static let primaryLight: UInt32 = 0x2563EB
    static let primaryDark: UInt32 = 0x5B8DEF
    static let onPrimaryLight: UInt32 = 0xFFFFFF
    static let onPrimaryDark: UInt32 = 0x0B1020
    static let primarySoftLight: UInt32 = 0xE8EFFD
    static let primarySoftDark: UInt32 = 0x1B2A4F
    static let primaryTextLight: UInt32 = 0x1D4ED8
    static let primaryTextDark: UInt32 = 0x93B4F5
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Dynamische Farbe, die auf Hell/Dunkel reagiert.
    static func ds(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension DS {
    enum Color {
        private static func dyn(_ light: UInt32, _ dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(uiColor: .ds(light: light, dark: dark))
        }

        // Grund und Flaechen
        static let bg = dyn(0xF5F6F8, 0x0B1020)
        static let surface = dyn(0xFFFFFF, 0x151B2E)
        static let surface2 = dyn(0xEEF1F5, 0x1E263D)
        static let border = dyn(0xE2E8F0, 0x263049)

        // Text
        static let text = dyn(0x0F172A, 0xF1F5F9)
        static let text2 = dyn(0x475569, 0xCBD5E1)
        static let muted = dyn(0x64748B, 0x94A3B8)

        // Marke (ueber Brand austauschbar)
        static let primary = dyn(Brand.primaryLight, Brand.primaryDark)
        static let onPrimary = dyn(Brand.onPrimaryLight, Brand.onPrimaryDark)
        static let primarySoft = dyn(Brand.primarySoftLight, Brand.primarySoftDark)
        static let primaryText = dyn(Brand.primaryTextLight, Brand.primaryTextDark)

        // Semantik
        static let success = dyn(0x15803D, 0x4ADE80)
        static let successSoft = dyn(0xDCFCE7, 0x123222)
        static let warning = dyn(0xB45309, 0xFBBF24)
        static let warningSoft = dyn(0xFEF3C7, 0x3A2C0B)
        static let danger = dyn(0xB91C1C, 0xF87171)
        static let dangerSoft = dyn(0xFEE2E2, 0x3B1517)

        /// Schattenfarbe der Karten (hell: slate, dunkel: schwarz).
        static let shadowKey = SwiftUI.Color(uiColor: .ds(light: 0x0F172A, dark: 0x000000))
    }

    /// Ton fuer Kacheln, Badges, Icon-Kacheln.
    enum Tone {
        case primary, success, warning, danger, neutral

        var foreground: SwiftUI.Color {
            switch self {
            case .primary: return DS.Color.primaryText
            case .success: return DS.Color.success
            case .warning: return DS.Color.warning
            case .danger: return DS.Color.danger
            case .neutral: return DS.Color.text2
            }
        }

        var soft: SwiftUI.Color {
            switch self {
            case .primary: return DS.Color.primarySoft
            case .success: return DS.Color.successSoft
            case .warning: return DS.Color.warningSoft
            case .danger: return DS.Color.dangerSoft
            case .neutral: return DS.Color.surface2
            }
        }
    }
}

extension View {
    /// Vollflaechiger DS-Hintergrund (einheitlicher Screen-Hintergrund).
    func dsBackground() -> some View {
        background(DS.Color.bg.ignoresSafeArea())
    }
}
