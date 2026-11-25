//
//  DSHaptics.swift
//  swipeShift
//

import UIKit

extension DS {
    /// Haptik-Helper. UIKit ist hier bewusst erlaubt (kein SwiftUI-Aequivalent unter iOS 17).
    @MainActor
    enum Haptics {
        static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
        static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }
}
