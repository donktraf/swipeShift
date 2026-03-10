//
//  JobListView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Sort & Filter Models

enum JobSortOption: String, CaseIterable {
    case newest     = "Newest"
    case distance   = "Distance"
    case pay        = "Highest Pay"
}

struct JobFilterOptions {
    var category: String? = nil
    var maxDistance: Double? = nil  // TODO: wenn Backend Distanz-Felder liefert
}

// MARK: - JobListView

struct JobListView: View {
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var userStore: UserStore

    // Optional: vorgefilterter Start (z.B. von CategoryJobListView)
    var preselectedCategory: String? = nil

    @State private var searchText: String = ""
    @State private var sortOption: JobSortOption = .newest
    @State private var filterOptions: JobFilterOptions = JobFilterOptions()
    @State private var showSortSheet = false
    @State private var showFilterSheet = false

    // Aktiver Filter = mindestens ein Filterfeld gesetzt
    var hasActiveFilter: Bool {
        filterOptions.category != nil
    }

    // Gefilterte + sortierte Jobs
    var displayedJobs: [Job] {
        var result = jobStore.jobs

        // 1) Suche
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q)
                || $0.company.lowercased().contains(q)
                || $0.location.lowercased().contains(q)
            }
        }

        // 2) Kategorie-Filter
        if let category = filterOptions.category {
            result = result.filter {
                $0.tags.contains(where: { $0.lowercased() == category.lowercased() })
                || $0.title.lowercased().contains(category.lowercased())
            }
        }

        // 3) Sortierung
        // TODO: Wenn Backend strukturierte Felder liefert (payAmount, distanceKm, createdAt)
        // kann hier sauber sortiert werden. Aktuell keine Sortierung möglich
        // da die Felder nur als Text vorliegen (payText, distanceText).

        return result
    }

    var body: some View {
        ZStack(alignment: .top) {
            SS.background().ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Sticky Header
                stickyHeader
                    .background(SS.background())
                    .zIndex(1)

                // MARK: - Job List
                if jobStore.jobs.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "briefcase")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No jobs available right now.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if displayedJobs.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No jobs match your search.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(displayedJobs) { job in
                                NavigationLink {
                                    JobDetailView(job: job)
                                } label: {
                                    DashboardJobCard(job: job)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .navigationTitle("All Available Jobs")
        .navigationBarTitleDisplayMode(.large)
        // Sort Sheet
        .sheet(isPresented: $showSortSheet) {
            SortSheet(selected: $sortOption)
                .presentationDetents([.height(280)])
        }
        // Filter Sheet
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterOptions: $filterOptions)
                .presentationDetents([.medium])
        }
        .task {
            guard APIClient.shared.token != nil else { return }
            await jobStore.loadJobsAll()
        }
        .onAppear {
            // Vorausgewählte Kategorie von CategoryJobListView übernehmen
            if let cat = preselectedCategory {
                filterOptions.category = cat
            }
        }
    }

    // MARK: - Sticky Header

    private var stickyHeader: some View {
        VStack(spacing: 10) {

            // Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search Job Title, Company or Location", text: $searchText)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 16)

            // Sort + Filter Row
            HStack(spacing: 10) {

                // Sort Button
                Button {
                    showSortSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Sort")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Filter Button
                Button {
                    showFilterSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Filter")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(hasActiveFilter ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(hasActiveFilter ? SS.primary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(hasActiveFilter ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Clear All Filters — nur sichtbar wenn aktiver Filter
                if hasActiveFilter {
                    Button {
                        filterOptions = JobFilterOptions()
                    } label: {
                        Text("Clear All Filters")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SS.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(SS.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: hasActiveFilter)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Sort Sheet

struct SortSheet: View {
    @Binding var selected: JobSortOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sort by")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ForEach(JobSortOption.allCases, id: \.self) { option in
                Button {
                    selected = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option.rawValue)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        Spacer()
                        if selected == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(SS.primary)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 20)
            }

            Spacer()
        }
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    @Binding var filterOptions: JobFilterOptions
    @Environment(\.dismiss) private var dismiss

    private let categories = JobCategory.all.map { $0.name }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {

                // Kategorie Filter
                VStack(alignment: .leading, spacing: 10) {
                    Text("Category")
                        .font(.system(size: 16, weight: .semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { cat in
                                let isSelected = filterOptions.category == cat
                                Button {
                                    if isSelected {
                                        filterOptions.category = nil
                                    } else {
                                        filterOptions.category = cat
                                    }
                                } label: {
                                    Text(cat)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? SS.primary : Color.gray.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        filterOptions = JobFilterOptions()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        JobListView()
            .environmentObject(JobStore())
            .environmentObject(UserStore())
    }
}
