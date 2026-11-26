//
//  RadarView.swift
//  swipeShift
//

import SwiftUI
import MapKit

// MARK: - ScrollOffset PreferenceKey

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - RadarView

struct RadarView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var jobStore: JobStore

    // Initiale Region kommt direkt vom User — kein Berlin-Flash
    @State private var mapRegion: MKCoordinateRegion
    @State private var isLoading = false
    @State private var selectedJobId: String? = nil
    @State private var mapHeightFraction: CGFloat = 0.45
    @State private var showRadiusSheet = false
    @State private var selectedRadius: Double = 100   // Meilen

    private let radiusOptions: [Double] = [5, 10, 25, 50, 100]

    init(lat: Double = 48.7758, lng: Double = 9.1829) {
        _mapRegion = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
        ))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation nur ohne "Bewegung reduzieren"
    private func motion(_ m: DS.Motion = .standard) -> Animation? {
        reduceMotion ? nil : m.animation
    }

    var body: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height
            let mapHeight = screenHeight * mapHeightFraction

            VStack(spacing: 0) {

                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Radar")
                            .dsFont(.display)
                            .foregroundStyle(DS.Color.text)
                        Text("Jobs near you")
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.muted)
                    }

                    Spacer()

                    DSIconButton(systemName: "arrow.clockwise", label: "Refresh") {
                        Task { await loadJobs() }
                    }
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.45 : 1)
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.sm)

                // MARK: - Map
                ClusterMapView(
                    jobs: jobsWithCoords,
                    pinColor: { pinColor(for: $0) },
                    selectedJobId: selectedJobId,
                    onJobTapped: { job in
                        DS.Haptics.selection()
                        withAnimation(motion(.snappy)) {
                            selectedJobId = job.id
                            mapRegion = MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: job.lat!, longitude: job.lng!),
                                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                            )
                        }
                    },
                    region: $mapRegion
                )
                .frame(height: mapHeight)
                .animation(motion(), value: mapHeightFraction)
                .clipShape(RoundedRectangle(cornerRadius: mapHeightFraction < 0.40 ? DS.Radius.card : 0, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    // Radius-Filter oben rechts auf der Karte
                    DSIconButton(systemName: "slider.horizontal.3", label: "Search radius, \(Int(selectedRadius)) miles") {
                        showRadiusSheet = true
                    }
                    .dsCardShadow()
                    .padding(DS.Spacing.sm)
                }

                // MARK: - Legende direkt unter der Karte
                legend
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.top, DS.Spacing.xs)

                // MARK: - Counter
                HStack {
                    Text("Showing \(jobsWithCoords.count) jobs near you")
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.text2)
                    Spacer()
                    Text("within \(Int(selectedRadius)) mi")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.vertical, DS.Spacing.sm)

                // MARK: - Job List
                if isLoading {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(0..<3, id: \.self) { _ in RadarCardSkeleton() }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .accessibilityLabel("Loading jobs")

                } else if jobStore.nearbyJobs.isEmpty {
                    emptyView

                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: inner.frame(in: .named("radarScroll")).minY
                                )
                            }
                            .frame(height: 0)

                            LazyVStack(spacing: DS.Spacing.sm) {
                                ForEach(jobStore.nearbyJobs) { job in
                                    NavigationLink {
                                        JobDetailView(job: job)
                                    } label: {
                                        RadarJobCard(job: job, isHighlighted: selectedJobId == job.id)
                                    }
                                    .buttonStyle(.dsPressable)
                                    .id(job.id)
                                }
                            }
                            .padding(.horizontal, DS.Spacing.screenEdge)
                            .padding(.bottom, DS.Spacing.xxl)
                        }
                        .ignoresSafeArea(.container, edges: .bottom)
                        .dsTabBarInset()
                        .refreshable {
                            await loadJobs()
                        }
                        .coordinateSpace(name: "radarScroll")
                        .onPreferenceChange(ScrollOffsetKey.self) { offset in
                            let collapsed = offset < -20
                            let target: CGFloat = collapsed ? 0.25 : 0.45
                            if abs(target - mapHeightFraction) > 0.01 {
                                withAnimation(motion()) {
                                    mapHeightFraction = target
                                }
                            }
                        }
                        .onChange(of: selectedJobId) { _, newId in
                            if let id = newId {
                                withAnimation(motion()) {
                                    scrollProxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .dsBackground()
        }
        .task {
            if jobStore.nearbyJobs.isEmpty {
                await loadJobs()
            }
        }
        // Nach Rückkehr von JobDetailView: Map auf highlighted Pin zentrieren
        .onAppear {
            if let id = selectedJobId,
               let job = jobStore.nearbyJobs.first(where: { $0.id == id }),
               let lat = job.lat, let lng = job.lng {
                withAnimation(motion()) {
                    mapRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                }
            }
        }
        .sheet(isPresented: $showRadiusSheet) {
            radiusSheet
        }
    }

    // MARK: - Legende

    private var legend: some View {
        HStack(spacing: DS.Spacing.xs) {
            LegendChip(color: DS.Color.primary, label: "Standard")
            LegendChip(color: DS.Color.warning, label: "Starting soon")
            LegendChip(color: DS.Color.success, label: "High pay")
            Spacer(minLength: 0)
        }
    }

    // MARK: - Radius Sheet

    private var radiusSheet: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(DS.Color.border)
                .frame(width: 36, height: 4)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.md)

            Text("Search Radius")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .padding(.bottom, DS.Spacing.md)

            VStack(spacing: 0) {
                ForEach(Array(radiusOptions.enumerated()), id: \.element) { idx, option in
                    DSRow("\(Int(option)) mi", showsDivider: idx > 0, action: {
                        DS.Haptics.selection()
                        selectedRadius = option
                        showRadiusSheet = false
                        Task { await loadJobs() }
                    }) {
                        if selectedRadius == option {
                            Image(systemName: "checkmark")
                                .font(DS.Font.make(14, .bold, relativeTo: .body))
                                .foregroundStyle(DS.Color.primary)
                                .accessibilityLabel("Selected")
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)

            Spacer()
        }
        .dsBackground()
        .presentationDetents([.fraction(0.42)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private var jobsWithCoords: [Job] {
        jobStore.nearbyJobs.filter { $0.lat != nil && $0.lng != nil }
    }

    /// Pin-Farben aus DS-Tokens: Standard primary, Starting soon warning, High pay success.
    private func pinColor(for job: Job) -> Color {
        if let start = job.startTime {
            let hoursUntilStart = start.timeIntervalSinceNow / 3600
            if hoursUntilStart > 0 && hoursUntilStart <= 5 { return DS.Color.warning }
        }
        if let pay = job.payAmount, pay >= 18 { return DS.Color.success }
        return DS.Color.primary
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            DSEmptyState(
                systemIcon: "scope",
                title: "No jobs nearby",
                message: "No jobs found within \(Int(selectedRadius)) miles.",
                actionTitle: "Refresh",
                action: { Task { await loadJobs() } }
            )
            Spacer()
        }
    }

    @MainActor
    private func loadJobs() async {
        guard let lat = userStore.currentUser?.lat,
              let lng = userStore.currentUser?.lng else {
            print("RadarView: User hat keine Koordinaten")
            return
        }

        isLoading = true
        await jobStore.loadNearbyJobs(lat: lat, lng: lng, radius: selectedRadius)

        withAnimation(motion()) {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
            )
        }

        isLoading = false
    }
}

// MARK: - LegendChip

private struct LegendChip: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                .foregroundStyle(DS.Color.text2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DS.Color.surface2, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - RadarJobCard

private struct RadarJobCard: View {
    let job: Job
    let isHighlighted: Bool

    var body: some View {
        DSCard {
            HStack(spacing: DS.Spacing.sm) {
                DSAvatar(text: job.logoEmoji, size: 48)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(job.title)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                    Text(job.company)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.sm) {
                        if !job.distanceText.isEmpty {
                            Label(job.distanceText, systemImage: "location")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.text2)
                        }
                        Label(job.payText, systemImage: "banknote")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.text2)
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.xs)

                Image(systemName: "chevron.right")
                    .font(DS.Font.make(13, .semibold, relativeTo: .caption))
                    .foregroundStyle(DS.Color.muted)
                    .accessibilityHidden(true)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Color.primary, lineWidth: isHighlighted ? 2 : 0)
        )
        .dsAnimation(.snappy, value: isHighlighted)
    }
}

// MARK: - Skeleton

private struct RadarCardSkeleton: View {
    var body: some View {
        DSCard {
            HStack(spacing: DS.Spacing.sm) {
                DSSkeletonBlock(width: 48, height: 48, radius: 14)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    DSSkeletonBlock(width: 160, height: 16)
                    DSSkeletonBlock(width: 100, height: 12)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityHidden(true)
    }
}
