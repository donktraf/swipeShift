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
                    VStack(spacing: 12) {
                        ForEach(filtered) { item in
                            ApplicationCard(item: item, status: appStatus(item)) {
                                applications.removeAll { $0.id == item.id }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task { await load() }
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

// MARK: - Application Card

private struct ApplicationCard: View {
    let item:     WorkerApplicationItem
    let status:   ApplicationStatus
    let onWithdraw: () -> Void

    @State private var showWithdrawAlert = false
    @State private var isWithdrawing     = false
    @State private var showRatingSheet   = false
    @State private var hasReviewed       = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(item.logoEmoji)
                    .font(.system(size: 28)).frame(width: 48, height: 48)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.jobTitle)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    Text(item.company)
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }
                Spacer()
                statusBadge
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            // Details
            HStack(spacing: 16) {
                Label(item.shiftText, systemImage: "calendar")
                Label(item.payText,   systemImage: "dollarsign.circle")
                Label(item.location,  systemImage: "mappin")
            }
            .font(.system(size: 12)).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .lineLimit(1)

            // Grund der Stornierung/Ablehnung (Employer-Angabe oder Standardtext vom Backend)
            if status == .cancelled, let reason = item.cancellationReason {
                Label(reason, systemImage: "xmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }

            if status == .applied {
                Divider().padding(.horizontal, 14)
                Button {
                    showWithdrawAlert = true
                } label: {
                    Text(isWithdrawing ? "Withdrawing…" : "Withdraw Application")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isWithdrawing)
                .alert("Withdraw Application?", isPresented: $showWithdrawAlert) {
                    Button("Withdraw", role: .destructive) {
                        Task {
                            isWithdrawing = true
                            try? await APIClient.shared.withdrawApplication(applyId: item.id)
                            onWithdraw()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your application for \(item.jobTitle) will be removed.")
                }
            }

            if status == .completed {
                Divider().padding(.horizontal, 14)
                Button { showRatingSheet = true } label: {
                    Label(hasReviewed ? "Review Submitted" : "Leave a Review",
                          systemImage: hasReviewed ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(hasReviewed ? .secondary : SS.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(hasReviewed)
                .sheet(isPresented: $showRatingSheet) {
                    EmployerRatingSheet(
                        applyId:     item.id,
                        companyName: item.company,
                        jobTitle:    item.jobTitle
                    ) {
                        hasReviewed = true
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch status {
        case .confirmed: ("Confirmed", .green)
        case .applied:   ("Applied",   SS.primary)
        case .completed: ("Completed", .gray)
        case .cancelled: ("Cancelled", .red)
        }
        return Text(label)
            .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color).clipShape(Capsule())
    }
}
