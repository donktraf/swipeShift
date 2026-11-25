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
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.sm) {
                if isLoading && jobs.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in DashboardJobCardSkeleton() }

                } else if let err = errorMessage {
                    DSEmptyState(
                        systemIcon: "wifi.exclamationmark",
                        title: "Something went wrong",
                        message: err,
                        actionTitle: "Retry",
                        action: { Task { await load() } }
                    )
                    .padding(.top, DS.Spacing.xxl)

                } else if jobs.isEmpty {
                    DSEmptyState(
                        systemIcon: category.icon,
                        title: "No \(category.name) jobs right now.",
                        message: "Check back later or explore other categories."
                    )
                    .padding(.top, DS.Spacing.xxl)

                } else {
                    ForEach(jobs) { job in
                        NavigationLink {
                            JobDetailView(job: job)
                        } label: {
                            DashboardJobCard(job: job)
                        }
                        .buttonStyle(.dsPressable)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .dsBackground()
        .refreshable {
            async let reloaded: Void = load()
            async let saved: Void = jobStore.loadSavedJobIds()
            _ = await (reloaded, saved)
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
