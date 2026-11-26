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

    /// Icon-Kachel-Ton je Kategorie
    var tone: DS.Tone {
        switch self {
        case .jobActivity: return .primary
        case .payments:    return .success
        case .messages:    return .primary
        case .reviews:     return .warning
        case .system:      return .neutral
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
    @State private var hasLoaded = false

    private var filtered: [AppNotification] {
        guard let filter = selectedFilter else { return notifications }
        return notifications.filter { $0.category == filter }
    }

    private var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
                .padding(.bottom, DS.Spacing.sm)

            if !hasLoaded && notifications.isEmpty {
                skeletonList
            } else if filtered.isEmpty {
                ScrollView {
                    DSEmptyState(
                        systemIcon: "bell.slash",
                        title: "No Notifications",
                        message: "Your job updates, payments, and messages will appear here."
                    )
                    .padding(.top, DS.Spacing.xxl)
                }
                .refreshable { await loadNotifications() }
            } else {
                notificationsList
            }
        }
        .dsBackground()
        .navigationBarHidden(true)
        .task { await loadNotifications() }
    }

    private func loadNotifications() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let dtos = try await APIClient.shared.fetchNotifications()
            // Lokal gesetzten Gelesen-Status beim Refresh beibehalten
            let readIds = Set(notifications.filter(\.isRead).map(\.id))
            notifications = dtos.map {
                var item = AppNotification(dto: $0)
                item.isRead = readIds.contains(item.id)
                return item
            }
            // Erst nach erfolgreichem Laden als gelesen markieren (bis zum juengsten gezeigten Eintrag)
            await NotificationBadgeStore.shared.markSeen(upTo: dtos.map(\.timestamp).max())
        } catch { }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button {
                DS.Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(DS.Font.make(17, .semibold))
                    .foregroundStyle(DS.Color.text)
                    .frame(width: 44, height: 44)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(DS.Color.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.dsPressable)
            .accessibilityLabel("Back")

            Text(unreadCount > 0 ? "Notifications (\(unreadCount))" : "Notifications")
                .dsFont(.title)
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                DSChip("Alle", isSelected: selectedFilter == nil) { selectedFilter = nil }
                ForEach(NotificationCategory.allCases, id: \.self) { cat in
                    DSChip(cat.rawValue, isSelected: selectedFilter == cat) { selectedFilter = cat }
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
        }
    }

    // MARK: - Skeleton

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    DSSkeletonBlock(width: 40, height: 40, radius: 12)
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        DSSkeletonBlock(width: 180, height: 14)
                        DSSkeletonBlock(height: 12)
                        DSSkeletonBlock(width: 80, height: 10)
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.vertical, DS.Spacing.sm)
            }
            Spacer(minLength: 0)
        }
        .dsSkeleton(true)
        .accessibilityLabel("Loading notifications")
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // "Mark all as read" wenn ungelesene vorhanden
                if unreadCount > 0 {
                    Button {
                        DS.Haptics.selection()
                        withAnimation(DS.Motion.snappy.animation) {
                            for i in notifications.indices { notifications[i].isRead = true }
                        }
                    } label: {
                        Text("Mark all as read")
                            .font(DS.Font.make(14, .bold))
                            .foregroundStyle(DS.Color.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                    }
                    .buttonStyle(.dsPressable)
                    .padding(.horizontal, DS.Spacing.screenEdge)
                }

                ForEach(filtered) { notification in
                    NotificationRow(notification: notification) {
                        markRead(notification)
                    }
                    DSDivider()
                        .padding(.leading, DS.Spacing.screenEdge + 40 + DS.Spacing.sm)
                }
            }
            .padding(.bottom, DS.Spacing.xxl)
        }
        .refreshable { await loadNotifications() }
    }

    // MARK: - Helpers

    private func markRead(_ notification: AppNotification) {
        if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[idx].isRead = true
        }
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        Button {
            if !notification.isRead { DS.Haptics.light() }
            onTap()
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                // Icon-Kachel je Kategorie
                Image(systemName: notification.category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(notification.category.tone.foreground)
                    .frame(width: 40, height: 40)
                    .background(notification.category.tone.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(alignment: .top, spacing: DS.Spacing.xs) {
                        Text(notification.title)
                            .font(DS.Font.make(15, notification.isRead ? .medium : .bold))
                            .foregroundStyle(DS.Color.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: DS.Spacing.xxs)
                        // Ungelesen-Punkt
                        if !notification.isRead {
                            Circle()
                                .fill(DS.Color.primary)
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)
                                .accessibilityLabel("Unread")
                        }
                    }

                    Text(notification.body)
                        .dsFont(.callout)
                        .foregroundStyle(notification.isRead ? DS.Color.text2 : DS.Color.text)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Text(notification.timestamp.relativeLabel)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(notification.isRead ? Color.clear : DS.Color.primarySoft.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressable)
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
