//
//  JobListView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Sort & Filter Models

enum JobSortOption: String, CaseIterable {
    case newest   = "Newest"
    case distance = "Distance"
    case pay      = "Highest Pay"
}

struct JobFilterOptions {
    var category:    String? = nil
    var maxDistance: Double? = nil   // Meilen; nil = kein Filter
}

// MARK: - JobListView

struct JobListView: View {
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var userStore: UserStore

    // Optional: vorgefilterter Start (z.B. von CategoryJobListView oder CompanyProfileView)
    var preselectedCategory: String? = nil
    var companyFilter: String? = nil

    @State private var searchText: String = ""
    @State private var sortOption: JobSortOption = .newest
    @State private var filterOptions: JobFilterOptions = JobFilterOptions()
    @State private var showSortSheet = false
    @State private var showFilterSheet = false
    // Skeleton nur beim ersten Laden
    @State private var hasLoaded = false
    @FocusState private var searchFocused: Bool

    // Anzahl aktiver Filter (Indikator am Filter-Button)
    var activeFilterCount: Int {
        (filterOptions.category != nil ? 1 : 0) + (filterOptions.maxDistance != nil ? 1 : 0)
    }

    // Aktiver Filter = mindestens ein Filterfeld gesetzt
    var hasActiveFilter: Bool {
        filterOptions.category != nil || filterOptions.maxDistance != nil
    }

    // User-Koordinaten für Distanz-Berechnung
    private var userLat: Double? { userStore.currentUser?.lat }
    private var userLng: Double? { userStore.currentUser?.lng }

    // Distanz eines Jobs zum User in Meilen (nil wenn Koordinaten fehlen)
    private func distanceMiles(to job: Job) -> Double? {
        guard let uLat = userLat, let uLng = userLng,
              let jLat = job.lat,  let jLng = job.lng else { return nil }
        return Distance.haversineMiles(lat1: uLat, lng1: uLng, lat2: jLat, lng2: jLng)
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

        // 3) Distanz-Filter
        if let maxMiles = filterOptions.maxDistance, userLat != nil {
            result = result.filter { job in
                guard let d = distanceMiles(to: job) else { return true }
                return d <= maxMiles
            }
        }

        // 4) Company-Filter (von CompanyProfileView)
        if let company = companyFilter {
            result = result.filter { $0.company.lowercased() == company.lowercased() }
        }

        // 5) Sortierung
        switch sortOption {
        case .newest:
            result.sort {
                ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture)
            }
        case .pay:
            result.sort { ($0.payAmount ?? 0) > ($1.payAmount ?? 0) }
        case .distance:
            result.sort { a, b in
                let dA = distanceMiles(to: a) ?? .greatestFiniteMagnitude
                let dB = distanceMiles(to: b) ?? .greatestFiniteMagnitude
                return dA < dB
            }
        }

        return result
    }

    private func reload() async {
        guard APIClient.shared.token != nil else { return }
        async let jobs  = jobStore.loadJobsAll()
        async let saved = jobStore.loadSavedJobIds()
        _ = await (jobs, saved)
        hasLoaded = true
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Sticky Header
            stickyHeader
                .background(DS.Color.bg)
                .zIndex(1)

            // MARK: - Job List
            if jobStore.jobs.isEmpty && !hasLoaded {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(0..<4, id: \.self) { _ in DashboardJobCardSkeleton() }
                    }
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.top, DS.Spacing.sm)
                }
                .scrollDisabled(true)
            } else if jobStore.jobs.isEmpty {
                emptyScroll {
                    DSEmptyState(
                        systemIcon: "briefcase",
                        title: "No jobs yet",
                        message: "No jobs available right now."
                    )
                }
            } else if displayedJobs.isEmpty {
                emptyScroll {
                    DSEmptyState(
                        systemIcon: "magnifyingglass",
                        title: "No matches",
                        message: "No jobs match your search."
                    )
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: DS.Spacing.sm) {
                        ForEach(displayedJobs) { job in
                            NavigationLink {
                                JobDetailView(job: job)
                            } label: {
                                DashboardJobCard(job: job)
                            }
                            .buttonStyle(.dsPressable)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxl)
                }
                .refreshable { await reload() }
            }
        }
        .dsBackground()
        .navigationTitle("All Available Jobs")
        .navigationBarTitleDisplayMode(.large)
        // Sort Sheet
        .sheet(isPresented: $showSortSheet) {
            SortSheet(selected: $sortOption)
                .presentationDetents([.height(320)])
                .presentationCornerRadius(DS.Radius.sheet)
                .presentationBackground(DS.Color.bg)
        }
        // Filter Sheet
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterOptions: $filterOptions)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(DS.Radius.sheet)
                .presentationBackground(DS.Color.bg)
        }
        .task { await reload() }
        .onAppear {
            // Vorausgewählte Kategorie von CategoryJobListView übernehmen
            if let cat = preselectedCategory {
                filterOptions.category = cat
            }
        }
    }

    /// Leerzustand scrollbar, damit Pull-to-refresh auch hier funktioniert.
    private func emptyScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content().padding(.top, DS.Spacing.xxl)
        }
        .refreshable { await reload() }
    }

    // MARK: - Sticky Header

    private var stickyHeader: some View {
        VStack(spacing: DS.Spacing.sm) {

            // Search Bar (Optik wie DSTextField, ohne Label)
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DS.Color.muted)
                    .accessibilityHidden(true)
                TextField(
                    "Search Job Title, Company or Location",
                    text: $searchText,
                    prompt: Text("Search Job Title, Company or Location").foregroundStyle(DS.Color.muted)
                )
                .font(DS.Font.make(15, .medium))
                .foregroundStyle(DS.Color.text)
                .tint(DS.Color.primary)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        DS.Haptics.light()
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.Color.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                    .padding(.trailing, -DS.Spacing.sm)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DS.Spacing.inset)
            .frame(minHeight: 50)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(searchFocused ? DS.Color.primary : DS.Color.border, lineWidth: searchFocused ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .onTapGesture { searchFocused = true }
            .padding(.horizontal, DS.Spacing.screenEdge)

            // Sort + Filter Row
            HStack(spacing: DS.Spacing.xs) {
                headerButton(
                    title: "Sort", icon: "arrow.up.arrow.down",
                    isActive: sortOption != .newest, count: nil
                ) { showSortSheet = true }

                headerButton(
                    title: "Filter", icon: "slider.horizontal.3",
                    isActive: hasActiveFilter, count: activeFilterCount
                ) { showFilterSheet = true }

                Spacer(minLength: DS.Spacing.xs)

                // Clear All Filters — nur sichtbar wenn aktiver Filter
                if hasActiveFilter {
                    Button {
                        DS.Haptics.light()
                        filterOptions = JobFilterOptions()
                    } label: {
                        Text("Clear All Filters")
                    }
                    .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .dsAnimation(.standard, value: hasActiveFilter)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    /// Sort-/Filter-Button mit Aktiv-Indikator (Punkt bzw. Anzahl).
    private func headerButton(title: String, icon: String, isActive: Bool, count: Int?, action: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.selection()
            action()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.make(14, .semibold, relativeTo: nil))
                Text(title)
                    .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                if isActive {
                    if let count, count > 0 {
                        Text("\(count)")
                            .font(DS.Font.make(12, .extrabold, relativeTo: .caption))
                            .foregroundStyle(DS.Color.onPrimary)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(DS.Color.primary, in: Capsule())
                    } else {
                        Circle().fill(DS.Color.primary).frame(width: 8, height: 8)
                    }
                }
            }
            .foregroundStyle(isActive ? DS.Color.primaryText : DS.Color.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isActive ? DS.Color.primarySoft : DS.Color.surface,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(isActive ? DS.Color.primary.opacity(0.4) : DS.Color.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.dsPressable)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? (count.map { "\($0) active" } ?? "active") : "")
    }
}

// MARK: - Sort Sheet

struct SortSheet: View {
    @Binding var selected: JobSortOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sort by")
                .dsFont(.title)
                .foregroundStyle(DS.Color.text)
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.sm)

            VStack(spacing: 0) {
                ForEach(Array(JobSortOption.allCases.enumerated()), id: \.element) { index, option in
                    DSRow(option.rawValue, showsDivider: index > 0, action: {
                        DS.Haptics.selection()
                        selected = option
                        dismiss()
                    }) {
                        if selected == option {
                            Image(systemName: "checkmark")
                                .font(DS.Font.make(15, .bold, relativeTo: nil))
                                .foregroundStyle(DS.Color.primary)
                        }
                    }
                    .accessibilityAddTraits(selected == option ? .isSelected : [])
                }
            }
            .overlay(alignment: .bottom) { DSDivider() }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
    }
}

// MARK: - Filter Sheet

/// Arbeitet auf einem Entwurf; erst "Apply" schreibt zurück, "Cancel" verwirft.
struct FilterSheet: View {
    @Binding var filterOptions: JobFilterOptions
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JobFilterOptions

    private let categories    = JobCategory.all.map { $0.name }
    private let distanceOptions: [Double] = [5, 10, 15, 20, 25]

    init(filterOptions: Binding<JobFilterOptions>) {
        self._filterOptions = filterOptions
        self._draft = State(initialValue: filterOptions.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Kopf
            HStack {
                Text("Filter")
                    .dsFont(.title)
                    .foregroundStyle(DS.Color.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Reset") {
                    DS.Haptics.light()
                    draft = JobFilterOptions()
                }
                .font(DS.Font.make(15, .semibold, relativeTo: .callout))
                .foregroundStyle(DS.Color.danger)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.sm)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {

                    // Distanz-Filter
                    DSSection("Max Distance", ruled: false) {
                        DSFlowLayout(spacing: DS.Spacing.xs) {
                            // "Any" — kein Filter
                            DSChip("Any", isSelected: draft.maxDistance == nil) {
                                draft.maxDistance = nil
                            }
                            ForEach(distanceOptions, id: \.self) { miles in
                                let isSelected = draft.maxDistance == miles
                                DSChip("\(Int(miles)) mi", isSelected: isSelected) {
                                    draft.maxDistance = isSelected ? nil : miles
                                }
                            }
                        }
                        .padding(.top, DS.Spacing.xs)
                    }

                    // Kategorie-Filter
                    DSSection("Category", ruled: false) {
                        DSFlowLayout(spacing: DS.Spacing.xs) {
                            ForEach(categories, id: \.self) { cat in
                                let isSelected = draft.category == cat
                                DSChip(cat, isSelected: isSelected) {
                                    draft.category = isSelected ? nil : cat
                                }
                            }
                        }
                        .padding(.top, DS.Spacing.xs)
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.lg)
            }

            // Footer: Cancel / Apply
            HStack(spacing: DS.Spacing.sm) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ds(.secondary))
                Button("Apply") {
                    DS.Haptics.success()
                    filterOptions = draft
                    dismiss()
                }
                .buttonStyle(.ds(.primary))
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.bg)
            .overlay(alignment: .top) { DSDivider() }
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
