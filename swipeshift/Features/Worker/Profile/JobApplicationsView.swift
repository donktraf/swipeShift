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
        SubScreenShell(title: "Job Applications") {
            VStack(spacing: 16) {
                tabSelector.padding(.horizontal, 16)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let err = errorMessage {
                    VStack(spacing: 12) {
                        Text(err).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button("Retry") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
                    }
                    .padding(.top, 60)
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 20) {
                        ForEach(groups) { group in
                            VStack(spacing: 10) {
                                monthHeader(group)
                                ForEach(group.items) { item in
                                    ApplicationCard(
                                        item: item,
                                        status: appStatus(item),
                                        onWithdraw: { applications.removeAll { $0.id == item.id } },
                                        onViewJob: { navigation.openJob(jobId: item.jobId) },
                                        onOpenChat: {
                                            navigation.openChat(conversationId: item.conversationId, messageStore: messageStore)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task { await load() }
        .applicationNavigation(navigation)
    }

    // MARK: - Month Header

    private func monthHeader(_ group: ApplicationMonthGroup) -> some View {
        HStack {
            Text(group.title)
                .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            Spacer()
            if let total = group.totalEarnings {
                Text("\(Money.format(total)) \(selectedTab == .completed ? "earned" : "expected")")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.75))
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { (label, tab) in
                Button { selectedTab = tab } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? SS.primary : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .systemBackground))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40)).foregroundColor(.white.opacity(0.3))
            Text("No jobs in this category")
                .font(.system(size: 15)).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; errorMessage = nil
        do { applications = try await APIClient.shared.fetchWorkerApplications() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
