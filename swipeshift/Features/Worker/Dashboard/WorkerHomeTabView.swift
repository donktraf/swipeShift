
//
//  WorkerHomeTabView.swift
//  swipeShift
//

import SwiftUI

struct WorkerHomeTabView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var jobStore: JobStore

    // Callback wenn User eine Kategorie auswählt
    let onCategorySelected: (JobCategory) -> Void
    // Callback wenn User "View All" in einer Sektion tippt
    let onViewAllJobs: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hey \(userStore.currentUser?.firstName ?? "") 👋")
                            .font(.system(size: 26, weight: .bold))

                        if let location = userStore.currentUser?.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Notification Bell
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // MARK: - View All Jobs Button
                NavigationLink {
                    JobListView()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("View All Available Jobs")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                // MARK: - Category Discovery
                VStack(alignment: .leading, spacing: 10) {
                    Text("Category Discovery")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal, 16)

                    CategoryScrollView(onSelect: onCategorySelected)
                }

                // MARK: - Job Sections (echte Backend-Filter)

                JobSectionView(
                    title: "Recommended for You",
                    jobs: jobStore.recommendedJobs,
                    onViewAll: onViewAllJobs
                )

                JobSectionView(
                    title: "Quick Money Jobs",
                    jobs: jobStore.quickMoneyJobs,
                    onViewAll: onViewAllJobs
                )

                JobSectionView(
                    title: "Starting Soon",
                    jobs: jobStore.startingSoonJobs,
                    onViewAll: onViewAllJobs
                )

                JobSectionView(
                    title: "Popular This Week",
                    jobs: jobStore.popularJobs,
                    onViewAll: onViewAllJobs
                )

                // Alle Jobs als Fallback-Sektion wenn andere leer sind
                if jobStore.recommendedJobs.isEmpty && jobStore.quickMoneyJobs.isEmpty {
                    JobSectionView(
                        title: "Here are jobs you might like today",
                        jobs: jobStore.jobs,
                        onViewAll: onViewAllJobs
                    )
                }

                // MARK: - Bottom CTAs
                VStack(spacing: 8) {
                    HStack {
                        Text("Looking for nearby jobs?")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("→ Go to Radar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SS.primary)
                    }

                    HStack {
                        Text("Want to decide fast?")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("→ Try Swipe")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SS.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .task {
            if let location = userStore.currentUser?.location {
                jobStore.selectedLocation = location
            }
            // Basis-Jobs + alle Dashboard-Sektionen parallel laden
            async let base     = jobStore.loadJobs()
            async let sections = jobStore.loadDashboardSections()
            _ = await (base, sections)
        }
    }
}
