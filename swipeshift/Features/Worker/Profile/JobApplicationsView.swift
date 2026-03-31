//
//  JobApplicationsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Application Status

enum ApplicationStatus {
    case confirmed, applied, completed, cancelled
}

// MARK: - Mock Application

struct JobApplication: Identifiable {
    let id = UUID()
    let jobTitle: String
    let company: String
    let logoEmoji: String
    let date: String
    let timeRange: String
    let location: String
    let payText: String
    let status: ApplicationStatus
    let appliedAt: String
}

// MARK: - JobApplicationsView

struct JobApplicationsView: View {
    @State private var selectedTab: ApplicationStatus = .confirmed

    private let tabs: [(String, ApplicationStatus)] = [
        ("Confirmed", .confirmed),
        ("Applied",   .applied),
        ("Completed", .completed),
        ("Cancelled", .cancelled),
    ]

    // TODO: aus Backend laden (GET /users/:id/applications)
    private let mockApplications: [JobApplication] = [
        JobApplication(jobTitle: "Barkeeper", company: "Club Tresor", logoEmoji: "🍸",
                       date: "Mar 28", timeRange: "22:00–04:00", location: "Berlin Mitte",
                       payText: "€18/h", status: .confirmed, appliedAt: "2 days ago"),
        JobApplication(jobTitle: "Event Staff", company: "Eventify GmbH", logoEmoji: "🎪",
                       date: "Mar 30", timeRange: "14:00–22:00", location: "Prenzlauer Berg",
                       payText: "€15/h", status: .confirmed, appliedAt: "3 days ago"),
        JobApplication(jobTitle: "Warehouse Helper", company: "LogiCore", logoEmoji: "📦",
                       date: "Apr 2", timeRange: "06:00–14:00", location: "Wedding",
                       payText: "€14/h", status: .applied, appliedAt: "today"),
        JobApplication(jobTitle: "Retail Assistant", company: "FashionHub", logoEmoji: "👗",
                       date: "Apr 5", timeRange: "10:00–18:00", location: "Mitte",
                       payText: "€13/h", status: .applied, appliedAt: "yesterday"),
        JobApplication(jobTitle: "Catering Staff", company: "GourmetEvents", logoEmoji: "🍽️",
                       date: "Mar 15", timeRange: "18:00–23:00", location: "Charlottenburg",
                       payText: "€16/h", status: .completed, appliedAt: "2 weeks ago"),
        JobApplication(jobTitle: "Cleaning Staff", company: "CleanPro", logoEmoji: "🧹",
                       date: "Mar 10", timeRange: "08:00–12:00", location: "Tempelhof",
                       payText: "€12/h", status: .cancelled, appliedAt: "3 weeks ago"),
    ]

    private var filtered: [JobApplication] {
        mockApplications.filter { $0.status == selectedTab }
    }

    var body: some View {
        SubScreenShell(title: "Job Applications") {
            VStack(spacing: 16) {
                tabSelector
                    .padding(.horizontal, 16)

                if filtered.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(filtered) { app in
                            ApplicationCard(application: app)
                        }
                    }
                    .padding(.horizontal, 16)
                }
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
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("No jobs in this category")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Application Card

private struct ApplicationCard: View {
    let application: JobApplication
    @State private var showWithdrawAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(application.logoEmoji)
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.jobTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(application.company)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusBadge
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            // Details
            HStack(spacing: 16) {
                Label(application.date, systemImage: "calendar")
                Label(application.timeRange, systemImage: "clock")
                Label(application.payText, systemImage: "eurosign.circle")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Withdraw button (nur bei Applied)
            if application.status == .applied {
                Divider().padding(.horizontal, 14)
                Button {
                    showWithdrawAlert = true
                } label: {
                    Text("Withdraw Application")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .alert("Withdraw Application?", isPresented: $showWithdrawAlert) {
                    Button("Withdraw", role: .destructive) {
                        // TODO: DELETE /jobs/:id/apply
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your application for \(application.jobTitle) will be removed.")
                }
            }

            // Leave rating button (nur bei Completed)
            if application.status == .completed {
                Divider().padding(.horizontal, 14)
                Button {
                    // TODO: → ReviewsView / leave rating
                } label: {
                    Label("Leave a Review", systemImage: "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch application.status {
        case .confirmed: ("Confirmed", .green)
        case .applied:   ("Applied",   SS.primary)
        case .completed: ("Completed", .gray)
        case .cancelled: ("Cancelled", .red)
        }
        return Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}
