//
//  CategoryJobListView.swift
//  swipeShift
//

import SwiftUI

/// Zeigt alle Jobs einer bestimmten Kategorie.
/// Wird geöffnet wenn User auf eine Kategorie im CategoryScrollView tippt.
struct CategoryJobListView: View {
    @EnvironmentObject var jobStore: JobStore
    @Environment(\.dismiss) private var dismiss

    let category: JobCategory

    // TODO: Wenn Backend Kategorie-Filter unterstützt:
    // GET /jobs?category=Hospitality
    // Aktuell: client-seitiger Filter auf jobStore.jobs
    var filteredJobs: [Job] {
        jobStore.jobs.filter { job in
            job.tags.contains(where: { $0.lowercased() == category.name.lowercased() })
            || job.title.lowercased().contains(category.name.lowercased())
        }
    }

    var body: some View {
        ZStack {
            SS.background().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if filteredJobs.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: category.icon)
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.3))

                            Text("No \(category.name) jobs right now.")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)

                            Text("Check back later or explore other categories.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 32)
                    } else {
                        ForEach(filteredJobs) { job in
                            NavigationLink {
                                JobDetailView(job: job)
                            } label: {
                                DashboardJobCard(job: job)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
    }
}
