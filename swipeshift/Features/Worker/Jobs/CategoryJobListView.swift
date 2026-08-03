//
//  CategoryJobListView.swift
//  swipeShift
//

import SwiftUI

/// Zeigt alle Jobs einer bestimmten Kategorie.
/// Wird geöffnet wenn User auf eine Kategorie im CategoryScrollView tippt.
struct CategoryJobListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var jobStore: JobStore

    let category: JobCategory

    @State private var jobs: [Job] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            SS.background().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)

                    } else if let err = errorMessage {
                        VStack(spacing: 12) {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Button("Retry") { Task { await load() } }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SS.primary)
                        }
                        .padding(.top, 60)

                    } else if jobs.isEmpty {
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
                        ForEach(jobs) { job in
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
        .task {
            await load()
            await jobStore.loadSavedJobIds()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            jobs = try await APIClient.shared.fetchJobs(category: category.name)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
