//
//  DSMetrics.swift
//  swipeShift
//
//  Spacing, Radius, Shadow, Motion.
//

import SwiftUI

extension DS {
    /// 4er-Raster.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        /// Bildschirmrand.
        static let screenEdge: CGFloat = 20
        /// Innenabstand in Karten/Feldern.
        static let inset: CGFloat = 16
    }

    enum Radius {
        static let control: CGFloat = 12
        static let button: CGFloat = 14
        static let card: CGFloat = 16
        static let tile: CGFloat = 16
        static let sheet: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum Motion {
        case standard, snappy

        var animation: Animation {
            switch self {
            case .standard: return .spring(response: 0.35, dampingFraction: 0.85)
            case .snappy: return .spring(response: 0.25, dampingFraction: 0.8)
            }
        }
    }
}

// MARK: - Schatten

private struct DSCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let key = DS.Color.shadowKey
        if scheme == .dark {
            content.shadow(color: key.opacity(0.30), radius: 1, x: 0, y: 1)
        } else {
            content
                .shadow(color: key.opacity(0.04), radius: 1, x: 0, y: 1)
                .shadow(color: key.opacity(0.06), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Motion (respektiert Reduce Motion)

private struct DSAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let motion: DS.Motion
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : motion.animation, value: value)
    }
}

extension View {
    /// Weicher Kartenschatten (hell: zweilagig, dunkel: nur Kontaktschatten).
    func dsCardShadow() -> some View { modifier(DSCardShadow()) }

    /// Animation mit DS-Motion-Preset; ohne Animation bei "Bewegung reduzieren".
    func dsAnimation<V: Equatable>(_ motion: DS.Motion = .standard, value: V) -> some View {
        modifier(DSAnimationModifier(motion: motion, value: value))
    }
}
