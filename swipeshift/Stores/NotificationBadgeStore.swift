//
//  NotificationBadgeStore.swift
//  swipeShift
//
//  Ungelesen-Zaehler fuer die Glocke (Worker- und Employer-Header). Kein Polling:
//  wird beim Erscheinen des Home-Tabs und beim Zurueckkommen in den Vordergrund aktualisiert.
//

import SwiftUI
import Combine

@MainActor
final class NotificationBadgeStore: ObservableObject {
    static let shared = NotificationBadgeStore()

    @Published private(set) var unreadCount = 0

    /// Wird bei reset() erhoeht: Antworten, die vor einem Konto-Wechsel gestartet wurden, werden verworfen
    private var generation = 0

    func refresh() async {
        let gen = generation
        guard let count = try? await APIClient.shared.fetchUnreadNotificationCount(), gen == generation else { return }
        unreadCount = count
    }

    /// NotificationsView hat die Liste erfolgreich geladen; upTo = juengster Zeitstempel der gezeigten Liste
    func markSeen(upTo: Date?) async {
        unreadCount = 0
        // Bei Konto-Wechsel waehrenddessen wird die Antwort ohnehin nicht mehr ausgewertet
        try? await APIClient.shared.markNotificationsSeen(upTo: upTo)
    }

    func reset() {
        generation += 1
        unreadCount = 0
    }

    /// "9+" ab zehn
    static func label(for count: Int) -> String { count > 9 ? "9+" : "\(count)" }
}

/// Rote Zahl-Pill, die oben rechts an die Glocke gehaengt wird (nur sichtbar bei count > 0)
struct NotificationBadgeModifier: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if count > 0 {
                Text(NotificationBadgeStore.label(for: count))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 6, y: -4)
                    .accessibilityLabel("\(count) unread notifications")
            }
        }
    }
}

extension View {
    func notificationBadge(_ count: Int) -> some View {
        modifier(NotificationBadgeModifier(count: count))
    }
}
