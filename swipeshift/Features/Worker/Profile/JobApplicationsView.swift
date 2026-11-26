//
//  JobApplicationsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Application Status

enum ApplicationStatus {
    case confirmed, applied, completed, cancelled
}

// MARK: - JobApplicationsView

struct JobApplicationsView: View {
    @State private var selectedTab: ApplicationStatus = .confirmed
    @State private var applications: [WorkerApplicationItem] = []
    @State private var isLoading    = false
    @State private var errorMessage: String? = nil
    @StateObject private var navigation = ApplicationNavigation()
    @EnvironmentObject private var messageStore: MessageStore

    private let tabs: [(String, ApplicationStatus)] = [
        ("Confirmed", .confirmed),
        ("Applied",   .applied),
        ("Completed", .completed),
        ("Cancelled", .cancelled),
    ]

    private func appStatus(_ item: WorkerApplicationItem) -> ApplicationStatus {
        switch item.displayStatus {
        case "confirmed": return .confirmed
        case "completed": return .completed
        case "cancelled": return .cancelled
        default:          return .applied
        }
    }

    private var filtered: [WorkerApplicationItem] {
        applications.filter { appStatus($0) == selectedTab }
    }

    /// Nach Monat gruppiert; kommende Jobs aufsteigend, vergangene absteigend, Stornierte ohne Summe
    private var groups: [ApplicationMonthGroup] {
        let past = selectedTab == .completed || selectedTab == .cancelled
        return ApplicationMonthGroup.make(from: filtered, newestFirst: past, includeEarnings: selectedTab != .cancelled)
    }

    var body: some View {
        SubScreenShell(title: "Job Applications", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                tabSelector

                if isLoading && applications.isEmpty {
                    skeleton
                } else if let err = errorMessage {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(err).dsFont(.callout).foregroundStyle(DS.Color.muted)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xxl)
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        ForEach(groups) { group in
                            VStack(spacing: DS.Spacing.sm) {
                                monthHeader(group)
                                ForEach(group.items) { item in
                                    ApplicationCard(
                                        item: item,
                                        status: appStatus(item),
                                        onWithdraw: { applications.removeAll { $0.id == item.id } },
                                        onViewJob: { navigation.openJob(jobId: item.jobId) },
                                        onOpenChat: {
                                            navigation.openChat(conversationId: item.conversationId, messageStore: messageStore)
                                        },
                                        onChanged: { Task { await load() } }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .applicationNavigation(navigation)
    }

    // MARK: - Skeleton

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        DSSkeletonBlock(width: 160, height: 16)
                        DSSkeletonBlock(width: 110, height: 12)
                        DSSkeletonBlock(height: 12)
                    }
                }
            }
        }
        .accessibilityLabel("Loading applications")
    }

    // MARK: - Month Header

    private func monthHeader(_ group: ApplicationMonthGroup) -> some View {
        HStack {
            Text(group.title)
                .dsFont(.sectionLabel).foregroundStyle(DS.Color.muted)
            Text("· \(group.items.count) \(group.items.count == 1 ? "job" : "jobs")")
                .dsFont(.caption).foregroundStyle(DS.Color.muted)
            Spacer()
            if let total = group.totalEarnings {
                Text("\(Money.format(total)) \(selectedTab == .completed ? "earned" : "expected")")
                    .font(DS.Font.make(12, .semibold, relativeTo: .caption)).foregroundStyle(DS.Color.text2)
            }
        }
    }

    // MARK: - Tab Selector (segmentierte Pills)

    private var tabSelector: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(tabs, id: \.0) { (label, tab) in
                Button {
                    DS.Haptics.selection()
                    selectedTab = tab
                } label: {
                    Text(label)
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(selectedTab == tab ? DS.Color.onPrimary : DS.Color.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selectedTab == tab ? DS.Color.primary : Color.clear, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.dsPressable)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(DS.Spacing.xxs)
        .background(DS.Color.surface2, in: Capsule())
        .dsAnimation(.snappy, value: selectedTab)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DSEmptyState(systemIcon: "tray", title: "No jobs here",
                     message: "No jobs in this category")
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; errorMessage = nil
        do { applications = try await APIClient.shared.fetchWorkerApplications() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
