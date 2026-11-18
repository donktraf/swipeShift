//
//  EmployerDashboardView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Needs Attention Item
private struct AttentionItem: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
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
    let delta: String       // z.B. "+3 this week"
    let deltaPositive: Bool
    let icon: String
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
    @State private var stats: EmployerStatsDTO? = nil
    @State private var jobsNeedingWorkersCount: Int = 0
    @State private var pendingReviewsCount: Int = 0
    @State private var pastReviews: [PastReviewItem] = []

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
                icon: "person.crop.circle.badge.clock", iconColor: .orange,
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
                                   delta: "this week", deltaPositive: true, icon: "bolt.fill"), at: 2)
        }
        return items
    }

    private var baseTrends: [TrendItem] {[
        TrendItem(value: "\(stats?.jobsFilledThisWeek ?? 0)", label: "Jobs Filled",
                  delta: "this week", deltaPositive: true, icon: "checkmark.circle"),
        TrendItem(value: "\(stats?.applicationsThisWeek ?? 0)", label: "New Applications",
                  delta: "this week", deltaPositive: true, icon: "person.crop.circle.badge.plus"),
        TrendItem(
            value: avgWorkerRating.map { String(format: "%.1f", $0) } ?? "—",
            label: "Avg. Worker Rating",
            delta: avgWorkerRating != nil
                ? "based on \(pastReviews.count) review\(pastReviews.count == 1 ? "" : "s")"
                : "Available after your first completed job",
            deltaPositive: true, icon: "star"
        ),
        TrendItem(value: stats?.topCategory ?? "—", label: "Top Category",
                  delta: "\(activeJobs) active jobs", deltaPositive: true, icon: "trophy"),
    ]}

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                dashboardHeader
                statsRow
                if !attentionItems.isEmpty {
                    needsAttentionSection
                }
                quickActionsSection
                navigationSection
                trendsSection

                Spacer().frame(height: 100)
            }
        }
        .task { await loadStats() }
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
    }

    // MARK: - Header
    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(userStore.currentUser?.companyName ?? "My Company")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    if let location = userStore.currentUser?.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            Text(location)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // Benachrichtigungs-Icon
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Stats Reihe
    private var statsRow: some View {
        HStack(spacing: 10) {
            StatCard(
                value: "\(activeJobs)",
                label: "Active Jobs",
                icon: "briefcase.fill",
                color: SS.primary,
                actionLabel: "View All"
            ) { onViewJobs?() }

            StatCard(
                value: "\(newApplicants)",
                label: "New Applicants",
                icon: "person.crop.circle.badge.plus",
                color: .green,
                actionLabel: "View All"
            ) { onViewApplicants?() }

            StatCard(
                value: Money.format(monthlySpend),
                label: "Monthly Spend",
                icon: "dollarsign.circle.fill",
                color: .orange,
                actionLabel: "Overview"
            ) { showFinancial = true }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Needs Attention
    private var needsAttentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Needs Attention", icon: "exclamationmark.triangle.fill", iconColor: .orange)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(attentionItems) { item in
                    AttentionCard(item: item)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Actions", icon: "bolt.fill", iconColor: SS.primary)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                // Post a New Job
                Button {
                    onPostJob?()
                } label: {
                    QuickActionCard(
                        icon: "plus.circle.fill",
                        label: "Post a Job",
                        color: SS.primary
                    )
                }
                .buttonStyle(.plain)

                // View All Posted Jobs
                Button {
                    onViewJobs?()
                } label: {
                    QuickActionCard(
                        icon: "list.bullet.rectangle.portrait",
                        label: "View All Jobs",
                        color: .indigo
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Navigation Section
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Navigation", icon: "square.grid.2x2", iconColor: .gray)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                NavGroup(title: "Job Management") {
                    NavRow(icon: "doc.text", label: "Posted Jobs", badge: activeJobs > 0 ? "\(activeJobs)" : nil) { onViewJobs?() }
                    Divider().padding(.leading, 52)
                    NavRow(icon: "pencil.and.list.clipboard", label: "Drafts", badge: nil) { onViewJobs?() }
                    Divider().padding(.leading, 52)
                    NavRow(icon: "checkmark.circle", label: "Completed Jobs", badge: nil) { onViewJobs?() }
                }

                Spacer().frame(height: 10)

                NavGroup(title: "Worker Management") {
                    NavRow(icon: "person.crop.circle.badge.questionmark", label: "Applicants", badge: newApplicants > 0 ? "\(newApplicants)" : nil) { onViewApplicants?() }
                    Divider().padding(.leading, 52)
                    NavRow(icon: "person.2.badge.gearshape", label: "Assign Workers",
                           badge: jobsNeedingWorkersCount > 0 ? "\(jobsNeedingWorkersCount)" : nil) { showAssignWorkers = true }
                    Divider().padding(.leading, 52)
                    NavRow(icon: "star.bubble", label: "Leave Reviews",
                           badge: pendingReviewsCount > 0 ? "\(pendingReviewsCount)" : nil) { showLeaveReviews = true }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Trends
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "This Week", icon: "chart.bar.fill", iconColor: .teal)
                .padding(.horizontal, 16)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(trends) { trend in
                    TrendCard(trend: trend)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Hilfs-Views

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    let actionLabel: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let action = actionLabel {
                Button(action: self.action) {
                    Text(action)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct AttentionCard: View {
    let item: AttentionItem

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .foregroundColor(item.iconColor)
                    .frame(width: 40, height: 40)
                    .background(item.iconColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(item.actionLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(item.iconColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(item.iconColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(12)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickActionCard: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

private struct NavGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            content
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct NavRow: View {
    let icon: String
    let label: String
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(SS.primary)
                    .frame(width: 28)
                    .padding(.leading, 14)

                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SS.primary)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct TrendCard: View {
    let trend: TrendItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: trend.icon)
                    .font(.system(size: 14))
                    .foregroundColor(SS.primary)
                Spacer()
            }

            Text(trend.value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)

            Text(trend.label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 3) {
                Image(systemName: trend.deltaPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(trend.deltaPositive ? .green : .red)
                Text(trend.delta)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
