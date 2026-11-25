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
    case reviews     = "Reviews"
    case system      = "System"

    static func from(_ raw: String) -> NotificationCategory {
        switch raw {
        case "jobActivity": return .jobActivity
        case "payments":    return .payments
        case "messages":    return .messages
        case "reviews":     return .reviews
        default:            return .system
        }
    }

    var icon: String {
        switch self {
        case .jobActivity: return "briefcase.fill"
        case .payments:    return "dollarsign.circle.fill"
        case .messages:    return "bubble.left.fill"
        case .reviews:     return "star.fill"
        case .system:      return "bell.fill"
        }
    }

    var color: Color {
        switch self {
        case .jobActivity: return SS.primary
        case .payments:    return .green
        case .messages:    return .blue
        case .reviews:     return .yellow
        case .system:      return .orange
        }
    }
}

// MARK: - Notification Item

struct AppNotification: Identifiable {
    let id: String
    let category: NotificationCategory
    let title: String
    let body: String
    let timestamp: Date
    var isRead: Bool

    init(dto: NotificationDTO) {
        self.id        = dto.id
        self.category  = NotificationCategory.from(dto.category)
        self.title     = dto.title
        self.body      = dto.body
        self.timestamp = dto.timestamp
        self.isRead    = false
    }
}

// MARK: - NotificationsView

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: NotificationCategory? = nil
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false

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

                if isLoading {
                    ProgressView().tint(.white).padding(.top, 40)
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    notificationsList
                }
            }
        }
        .task { await loadNotifications() }
    }

    private func loadNotifications() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await APIClient.shared.fetchNotifications()
            notifications = dtos.map { AppNotification(dto: $0) }
            // Erst nach erfolgreichem Laden als gelesen markieren (bis zum juengsten gezeigten Eintrag)
            await NotificationBadgeStore.shared.markSeen(upTo: dtos.map(\.timestamp).max())
        } catch { }
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
                    Text("Mark all as read")
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
            return "Just now"
        } else if diff < 3600 {
            return "\(Int(diff / 60)) min ago"
        } else if diff < 86400 {
            return "\(Int(diff / 3600)) hr ago"
        } else if diff < 86400 * 7 {
            return "\(Int(diff / 86400)) day(s) ago"
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US")
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }
}
