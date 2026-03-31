//
//  NotificationsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Notification Category

enum NotificationCategory: String, CaseIterable {
    case jobActivity = "Job Activity"
    case payments    = "Payments"
    case messages    = "Messages"
    case system      = "System"

    var icon: String {
        switch self {
        case .jobActivity: return "briefcase.fill"
        case .payments:    return "eurosign.circle.fill"
        case .messages:    return "bubble.left.fill"
        case .system:      return "bell.fill"
        }
    }

    var color: Color {
        switch self {
        case .jobActivity: return SS.primary
        case .payments:    return .green
        case .messages:    return .blue
        case .system:      return .orange
        }
    }
}

// MARK: - Notification Item

struct AppNotification: Identifiable {
    let id = UUID()
    let category: NotificationCategory
    let title: String
    let body: String
    let timestamp: Date
    var isRead: Bool
}

// MARK: - NotificationsView

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: NotificationCategory? = nil
    @State private var notifications: [AppNotification] = Self.mockNotifications()

    private var filtered: [AppNotification] {
        guard let filter = selectedFilter else { return notifications }
        return notifications.filter { $0.category == filter }
    }

    private var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    var body: some View {
        SubScreenShell(title: unreadCount > 0 ? "Notifications (\(unreadCount))" : "Notifications") {
            VStack(spacing: 16) {
                filterBar
                    .padding(.horizontal, 16)

                if filtered.isEmpty {
                    emptyState
                } else {
                    notificationsList
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "Alle" Chip
                FilterChip(
                    label: "Alle",
                    color: .gray,
                    isSelected: selectedFilter == nil
                ) { selectedFilter = nil }

                ForEach(NotificationCategory.allCases, id: \.self) { cat in
                    FilterChip(
                        label: cat.rawValue,
                        color: cat.color,
                        isSelected: selectedFilter == cat
                    ) { selectedFilter = cat }
                }
            }
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        VStack(spacing: 0) {
            // "Mark all as read" wenn ungelesene vorhanden
            if unreadCount > 0 {
                Button {
                    withAnimation {
                        for i in notifications.indices { notifications[i].isRead = true }
                    }
                } label: {
                    Text("Alle als gelesen markieren")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                ForEach(filtered) { notification in
                    NotificationRow(notification: notification) {
                        markRead(notification)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.3))
            Text("No Notifications")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Your job updates, payments, and messages will appear here.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func markRead(_ notification: AppNotification) {
        if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[idx].isRead = true
        }
    }

    // MARK: - Mock Data

    static func mockNotifications() -> [AppNotification] {
        let now = Date()
        func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

        return [
            AppNotification(
                category: .jobActivity,
                title: "Application accepted!",
                body: "Club Tresor has accepted your application as Bartender. Check your messages.",
                timestamp: ago(300), isRead: false
            ),
            AppNotification(
                category: .messages,
                title: "New message from Eventify GmbH",
                body: "\"Hi! We're looking forward to your shift on Mar 30. Please confirm your arrival time.\"",
                timestamp: ago(1800), isRead: false
            ),
            AppNotification(
                category: .payments,
                title: "Payment received",
                body: "€144 from Club Tresor has been credited to your account.",
                timestamp: ago(7200), isRead: false
            ),
            AppNotification(
                category: .jobActivity,
                title: "New jobs near you",
                body: "5 new Events jobs have been posted in Berlin that match your profile.",
                timestamp: ago(14400), isRead: true
            ),
            AppNotification(
                category: .system,
                title: "Profile verification complete",
                body: "Your profile has been successfully verified. You can now access all jobs.",
                timestamp: ago(86400), isRead: true
            ),
            AppNotification(
                category: .jobActivity,
                title: "Reminder: Shift tomorrow",
                body: "You're working tomorrow 22:00–04:00 at Club Tresor as Bartender.",
                timestamp: ago(3600 * 5), isRead: true
            ),
            AppNotification(
                category: .payments,
                title: "Pending review",
                body: "How was your shift at GourmetEvents? Leave a review now.",
                timestamp: ago(86400 * 2), isRead: true
            ),
            AppNotification(
                category: .messages,
                title: "Message from LogiCore",
                body: "\"Your application has been received. We will get back to you within 24h.\"",
                timestamp: ago(86400 * 3), isRead: true
            ),
        ]
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color : Color(uiColor: .systemBackground))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(notification.category.color.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: notification.category.icon)
                        .font(.system(size: 17))
                        .foregroundColor(notification.category.color)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.system(size: 14, weight: notification.isRead ? .regular : .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        // Ungelesen-Punkt
                        if !notification.isRead {
                            Circle()
                                .fill(SS.primary)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(notification.body)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(notification.timestamp.relativeLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(12)
            .background(
                notification.isRead
                    ? Color(uiColor: .systemBackground)
                    : Color(uiColor: .systemBackground)
            )
            .overlay(alignment: .leading) {
                if !notification.isRead {
                    Rectangle()
                        .fill(notification.category.color)
                        .frame(width: 3)
                        .clipShape(Capsule())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(notification.isRead ? 0.03 : 0.06), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Extension
private extension Date {
    var relativeLabel: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60 {
            return "Gerade eben"
        } else if diff < 3600 {
            return "vor \(Int(diff / 60)) Min."
        } else if diff < 86400 {
            return "vor \(Int(diff / 3600)) Std."
        } else if diff < 86400 * 7 {
            return "vor \(Int(diff / 86400)) Tag(en)"
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.dateFormat = "dd. MMM"
            return f.string(from: self)
        }
    }
}
