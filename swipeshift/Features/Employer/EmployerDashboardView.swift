//
//  EmployerDashboardView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Needs Attention Item
private struct AttentionItem: Identifiable {
    let id = UUID()
    let icon: String
    let tone: DS.Tone
    let title: String
    let subtitle: String
    let actionLabel: String
    let action: () -> Void
}

// MARK: - Trend Item
private struct TrendItem: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let delta: String       // z.B. "this week"
    let deltaPositive: Bool
    let icon: String
    var tone: DS.Tone = .primary
}

// MARK: - EmployerDashboardView
struct EmployerDashboardView: View {
    @EnvironmentObject var userStore: UserStore
    var onPostJob:       (() -> Void)? = nil
    var onViewJobs:      (() -> Void)? = nil
    var onViewApplicants:(() -> Void)? = nil

    @State private var showLeaveReviews   = false
    @State private var showAssignWorkers  = false
    @State private var showFinancial      = false
    @State private var showCalendar       = false
    @State private var showNotifications  = false
    @ObservedObject private var badge = NotificationBadgeStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var stats: EmployerStatsDTO? = nil
    @State private var jobsNeedingWorkersCount: Int = 0
    @State private var pendingReviewsCount: Int = 0
    @State private var pastReviews: [PastReviewItem] = []
    @State private var isLoading = true

    private var activeJobs:    Int    { stats?.activeJobs    ?? 0 }
    private var newApplicants: Int    { stats?.newApplicants ?? 0 }
    private var monthlySpend:  Double { stats?.monthlySpend  ?? 0 }

    // Durchschnitt aller Bewertungen, die dieser Employer bisher an seine Worker vergeben hat
    // (Review-Model: communication/teamwork/reliability/underPressure), gespeist aus
    // GET /employer/reviews (bereits vorhanden, wird auch von LeaveReviewsView genutzt).
    private var avgWorkerRating: Double? {
        guard !pastReviews.isEmpty else { return nil }
        let sum = pastReviews.reduce(0.0) { $0 + $1.avgRating }
        return sum / Double(pastReviews.count)
    }

    private var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        if newApplicants > 0 {
            items.append(AttentionItem(
                icon: "person.crop.circle.badge.clock", tone: .warning,
                title: "\(newApplicants) pending application\(newApplicants == 1 ? "" : "s")",
                subtitle: "Applicants are waiting for your response.",
                actionLabel: "View Now",
                action: { onViewApplicants?() }
            ))
        }
        return items
    }

    private var trends: [TrendItem] {
        var items = baseTrends
        // Instant Matches (automatisch angenommen) separat von "New Applications"; nur wenn vorhanden
        if let instant = stats?.instantMatchesThisWeek, instant > 0 {
            items.insert(TrendItem(value: "\(instant)", label: "Instant Matches",
                                   delta: "this week", deltaPositive: true, icon: "bolt.fill", tone: .primary), at: 2)
        }
        return items
    }

    private var baseTrends: [TrendItem] {[
        TrendItem(value: "\(stats?.jobsFilledThisWeek ?? 0)", label: "Jobs Filled",
                  delta: "this week", deltaPositive: true, icon: "checkmark.circle", tone: .success),
        TrendItem(value: "\(stats?.applicationsThisWeek ?? 0)", label: "New Applications",
                  delta: "this week", deltaPositive: true, icon: "person.crop.circle.badge.plus"),
        TrendItem(
            value: avgWorkerRating.map { String(format: "%.1f", $0) } ?? "—",
            label: "Avg. Worker Rating",
            delta: avgWorkerRating != nil
                ? "based on \(pastReviews.count) review\(pastReviews.count == 1 ? "" : "s")"
                : "Available after your first completed job",
            deltaPositive: true, icon: "star", tone: .warning
        ),
        TrendItem(value: stats?.topCategory ?? "—", label: "Top Category",
                  delta: "\(activeJobs) active jobs", deltaPositive: true, icon: "trophy", tone: .neutral),
    ]}

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                dashboardHeader
                statsRow
                if !attentionItems.isEmpty {
                    needsAttentionSection
                }
                quickActionsSection
                trendsSection
                navigationSection
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xl)
        }
        .dsTabBarInset()
        .refreshable { await loadStats() }
        .dsBackground()
        .task { await loadStats() }
        // Glocken-Badge: beim Erscheinen und beim Zurueckkommen in den Vordergrund
        .task { await badge.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await badge.refresh() } }
        }
        .navigationDestination(isPresented: $showLeaveReviews) {
            LeaveReviewsView()
        }
        .navigationDestination(isPresented: $showAssignWorkers) {
            AssignWorkersView()
        }
        .navigationDestination(isPresented: $showFinancial) {
            EmployerFinancialView()
        }
        .navigationDestination(isPresented: $showCalendar) {
            EmployerCalendarView()
        }
        .sheet(isPresented: $showNotifications) {
            NavigationStack {
                NotificationsView()
            }
        }
    }

    @MainActor
    private func loadStats() async {
        // Echte Counts für die Nav-Badges laden, analog zu "Active Jobs"/"New Applicants" oben,
        // statt hartcodierter Platzhalter-Zahlen. Alle vier Calls parallel statt sequenziell.
        async let employerStats = try? APIClient.shared.fetchEmployerStats()
        async let assignableJobs = try? APIClient.shared.fetchAssignedWorkers()
        async let pendingReviews = try? APIClient.shared.fetchPendingReviews()
        async let completedReviews = try? APIClient.shared.fetchPastReviews()
        let (statsResult, jobs, reviews, past) = await (employerStats, assignableJobs, pendingReviews, completedReviews)
        stats = statsResult
        jobsNeedingWorkersCount = jobs?.filter { !$0.isFullyStaffed }.count ?? 0
        pendingReviewsCount = reviews?.count ?? 0
        pastReviews = past ?? []
        isLoading = false
    }

    // MARK: - Header
    private var dashboardHeader: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                Text("My company")
                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(DS.Color.muted)
                Text(userStore.currentUser?.companyName ?? "My Company")
                    .dsFont(.display)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let location = userStore.currentUser?.location {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(location)
                            .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                            .lineLimit(1)
                    }
                    .foregroundStyle(DS.Color.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.Color.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(DS.Color.border, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Location \(location)")
                }
            }

            Spacer(minLength: DS.Spacing.sm)

            // Benachrichtigungs-Icon
            Button {
                DS.Haptics.light()
                showNotifications = true
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.Color.text)
                    .frame(width: 44, height: 44)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DS.Color.border, lineWidth: 1)
                    )
                    .notificationBadge(badge.unreadCount)
            }
            .buttonStyle(.dsPressable)
            .accessibilityLabel(badge.unreadCount > 0 ? "Notifications, \(badge.unreadCount) unread" : "Notifications")
        }
    }

    // MARK: - Stats
    private var statsRow: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                StatTile(
                    label: "Active jobs", value: "\(activeJobs)", tone: .primary,
                    actionLabel: "View all"
                ) { onViewJobs?() }

                StatTile(
                    label: "New applicants", value: "\(newApplicants)", tone: .warning,
                    actionLabel: "View all"
                ) { onViewApplicants?() }
            }

            SpendCard(
                value: Money.format(monthlySpend),
                wages: stats?.monthlySpendWages,
                fees: stats?.monthlySpendFees
            ) {
                DS.Haptics.light()
                showFinancial = true
            }
        }
        .dsSkeleton(isLoading && stats == nil)
    }

    // MARK: - Needs Attention
    private var needsAttentionSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Needs attention")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .accessibilityAddTraits(.isHeader)

            ForEach(attentionItems) { item in
                DSCard(action: item.action) {
                    HStack(spacing: DS.Spacing.sm) {
                        Circle()
                            .fill(item.tone.foreground)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(DS.Font.make(15, .bold))
                                .foregroundStyle(DS.Color.text)
                            Text(item.subtitle)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.muted)
                        }
                        Spacer(minLength: DS.Spacing.xs)
                        Text(item.actionLabel)
                            .font(DS.Font.make(14, .bold))
                            .foregroundStyle(DS.Color.primaryText)
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                onPostJob?()
            } label: {
                Label("Post a job", systemImage: "plus")
            }
            .buttonStyle(.ds(.primary))

            Button {
                onViewJobs?()
            } label: {
                Text("View all jobs")
            }
            .buttonStyle(.ds(.secondary))
        }
    }

    // MARK: - Trends
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("This week")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: DS.Spacing.sm), GridItem(.flexible(), spacing: DS.Spacing.sm)],
                spacing: DS.Spacing.sm
            ) {
                ForEach(trends) { trend in
                    DSTile(
                        label: trend.label,
                        value: trend.value,
                        tone: trend.tone,
                        caption: trend.delta
                    )
                }
            }
            .dsSkeleton(isLoading && stats == nil)
        }
    }

    // MARK: - Navigation Section (flach)
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            DSSection("Job management") {
                navRow("Posted jobs", count: activeJobs, first: true) { onViewJobs?() }
                navRow("Drafts", count: 0) { onViewJobs?() }
                navRow("Completed jobs", count: 0) { onViewJobs?() }
            }

            DSSection("Worker management") {
                navRow("Applicants", count: newApplicants, first: true) { onViewApplicants?() }
                navRow("Assign workers", count: jobsNeedingWorkersCount) { showAssignWorkers = true }
                navRow("Leave reviews", count: pendingReviewsCount) { showLeaveReviews = true }
            }
        }
    }

    private func navRow(_ title: String, count: Int, first: Bool = false, action: @escaping () -> Void) -> some View {
        DSRow(title, showsChevron: true, action: action) {
            if count > 0 {
                Text("\(count)")
                    .font(DS.Font.make(12, .extrabold, relativeTo: .caption))
                    .foregroundStyle(DS.Color.text2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.Color.surface2, in: Capsule())
            }
        }
    }
}

// MARK: - Hilfs-Views

/// Antippbare Kennzahl-Kachel mit Aktion ("View all ›").
private struct StatTile: View {
    let label: String
    let value: String
    let tone: DS.Tone
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(DS.Font.make(12, .bold, relativeTo: .caption))
                    .foregroundStyle(tone.foreground)
                Text(value)
                    .font(DS.Font.make(28, .extrabold, relativeTo: .title))
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(actionLabel) ›")
                    .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(tone.foreground)
            }
            .padding(DS.Spacing.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.soft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        }
        .buttonStyle(.dsPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint(actionLabel)
    }
}

/// Monatsausgaben mit Mini-Balken (Loehne vs. Plattform-Gebuehr, nur wenn das Backend die Aufteilung liefert).
private struct SpendCard: View {
    let value: String
    let wages: Double?
    let fees: Double?
    let action: () -> Void

    var body: some View {
        DSCard(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Monthly spend · incl. fee")
                        .font(DS.Font.make(12, .bold, relativeTo: .caption))
                        .foregroundStyle(DS.Color.muted)
                    Text(value)
                        .font(DS.Font.make(24, .extrabold, relativeTo: .title2))
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: DS.Spacing.sm)
                if let wages, let fees, wages + fees > 0 {
                    let maxValue = max(wages, fees)
                    HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
                        bar(height: 40 * wages / maxValue, color: DS.Color.primary)
                        bar(height: 40 * fees / maxValue, color: DS.Color.warning)
                    }
                    .frame(height: 40, alignment: .bottom)
                    .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.muted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens financial overview")
    }

    private func bar(height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 8, height: max(4, height))
    }
}
