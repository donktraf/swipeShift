
//
//  JobSectionView.swift
//  swipeShift
//

import SwiftUI

/// Wiederverwendbare Job-Sektion für das Dashboard.
/// Jede Sektion hat einen Titel, eine Liste von Jobs und einen "View All" Button.
/// Die Logik WIE Jobs gefiltert werden kommt später vom Backend.
struct JobSectionView: View {
    let title: String
    let jobs: [Job]
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button(action: onViewAll) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)

            if jobs.isEmpty {
                // Placeholder wenn noch keine Jobs geladen
                Text("No jobs available right now.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                // Job Cards
                VStack(spacing: 10) {
                    ForEach(jobs.prefix(2)) { job in
                        NavigationLink {
                            JobDetailView(job: job)
                        } label: {
                            DashboardJobCard(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                // "Click to view all jobs"
                Button(action: onViewAll) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SS.primary)
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(SS.primary)
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(SS.primary)
                            .frame(width: 6, height: 6)
                        Text("Click to view all jobs")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(SS.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Kompakte Job-Card für das Dashboard
struct DashboardJobCard: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Logo / Emoji
                Text(job.logoEmoji)
                    .font(.system(size: 28))
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)

                    Text(job.company)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Bookmark + Apply
                HStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)

                    Text("Apply")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(SS.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Details
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(job.distanceText, systemImage: "location")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Label(job.shiftText, systemImage: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Label(job.payText, systemImage: "banknote")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            // Tags
            if !job.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(job.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(SS.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SS.primary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
