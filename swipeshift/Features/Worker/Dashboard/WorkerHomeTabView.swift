
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
    // Callbacks für Bottom CTAs
    let onGoToRadar: () -> Void
    let onGoToSwipe: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Personal Job Dashboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text("Hey \(userStore.currentUser?.firstName ?? "there")!")
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
                VStack(spacing: 10) {
                    Button(action: onGoToRadar) {
                        HStack {
                            Image(systemName: "location.circle.fill")
                                .foregroundColor(SS.primary)
                            Text("Looking for nearby jobs?")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("Go to Radar →")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SS.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)

                    Button(action: onGoToSwipe) {
                        HStack {
                            Image(systemName: "hand.draw.fill")
                                .foregroundColor(SS.primary)
                            Text("Want to decide fast?")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("Try Swipe →")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SS.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .task {
            if let location = userStore.currentUser?.location {
                jobStore.selectedLocation = location
            }
            // Basis-Jobs + alle Dashboard-Sektionen parallel laden
            // Wenn kein Standort gesetzt → alle Jobs laden als Fallback
            async let base     = jobStore.selectedLocation != nil
                                    ? jobStore.loadJobs()
                                    : jobStore.loadJobsAll()
            async let sections = jobStore.loadDashboardSections()
            _ = await (base, sections)
        }
    }
}
