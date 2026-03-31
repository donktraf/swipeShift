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

    @State private var isLoading = false
    @State private var selectedJobId: String? = nil
    @State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405), // Berlin Fallback
        span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
    )
    @State private var mapHeightFraction: CGFloat = 0.45  // 45% initial, 25% beim Scrollen

    var body: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height
            let mapHeight = screenHeight * mapHeightFraction

            ZStack {
                SS.background().ignoresSafeArea()

                VStack(spacing: 0) {

                    // MARK: - Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Radar")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            Text("Jobs near you")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()

                        // Refresh Button
                        Button {
                            Task { await loadJobs() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(SS.primary)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                                .rotationEffect(.degrees(isLoading ? 360 : 0))
                                .animation(
                                    isLoading
                                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                                        : .default,
                                    value: isLoading
                                )
                        }
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                    // MARK: - Map (UIViewRepresentable mit Clustering)
                    ClusterMapView(
                        jobs: jobsWithCoords,
                        pinColor: { pinColor(for: $0) },
                        selectedJobId: selectedJobId,
                        onJobTapped: { job in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedJobId = job.id
                                // Kamera auf Pin zentrieren
                                mapRegion = MKCoordinateRegion(
                                    center: CLLocationCoordinate2D(latitude: job.lat!, longitude: job.lng!),
                                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                                )
                            }
                        },
                        region: $mapRegion
                    )
                    .frame(height: mapHeight)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mapHeightFraction)
                    .clipShape(RoundedRectangle(cornerRadius: mapHeightFraction < 0.40 ? 16 : 0))
                    .overlay(alignment: .bottomLeading) {
                        // Legende
                        HStack(spacing: 10) {
                            LegendDot(color: SS.primary, label: "Standard")
                            LegendDot(color: .orange, label: "Starting soon")
                            LegendDot(color: .green, label: "High pay")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                    }

                    // MARK: - Zähler + Filter
                    HStack {
                        Text("Showing \(jobsWithCoords.count) jobs near you")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))

                        Spacer()

                        // TODO: Radius-Filter implementieren
                        Button {
                            // Placeholder
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Filter")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SS.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // MARK: - Job-Liste
                    if isLoading {
                        Spacer()
                        ProgressView("Lade Jobs...")
                            .foregroundColor(.white)
                        Spacer()

                    } else if jobStore.nearbyJobs.isEmpty {
                        emptyView

                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView(showsIndicators: false) {
                                // Anchor oben für Scroll-Offset-Messung
                                GeometryReader { inner in
                                    Color.clear.preference(
                                        key: ScrollOffsetKey.self,
                                        value: inner.frame(in: .named("radarScroll")).minY
                                    )
                                }
                                .frame(height: 0)

                                LazyVStack(spacing: 10) {
                                    ForEach(jobStore.nearbyJobs) { job in
                                        NavigationLink {
                                            JobDetailView(job: job)
                                        } label: {
                                            RadarJobCard(job: job, isHighlighted: selectedJobId == job.id)
                                        }
                                        .buttonStyle(.plain)
                                        .id(job.id)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 32)
                            }
                            .coordinateSpace(name: "radarScroll")
                            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                                // offset < -20 → Scrollen → Map verkleinern
                                let collapsed = offset < -20
                                let target: CGFloat = collapsed ? 0.25 : 0.45
                                if abs(target - mapHeightFraction) > 0.01 {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        mapHeightFraction = target
                                    }
                                }
                            }
                            // Wenn selectedJobId sich ändert (durch Pin-Tap), scrolle zur Karte
                            .onChange(of: selectedJobId) { _, newId in
                                if let id = newId {
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        scrollProxy.scrollTo(id, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            // Nur beim ersten Erscheinen laden, nicht nach jedem dismiss von JobDetailView.
            // Dadurch bleiben Pins sichtbar auch wenn ein Job bereits beworben wurde.
            if jobStore.nearbyJobs.isEmpty {
                await loadJobs()
            }
        }
    }

    // MARK: - Helper

    /// Nur Jobs mit gültigen Koordinaten für die Map
    private var jobsWithCoords: [Job] {
        jobStore.nearbyJobs.filter { $0.lat != nil && $0.lng != nil }
    }

    /// Pin-Farbe basierend auf startTime und payAmount
    private func pinColor(for job: Job) -> Color {
        // Orange: startet innerhalb von 5 Stunden
        if let start = job.startTime {
            let hoursUntilStart = start.timeIntervalSinceNow / 3600
            if hoursUntilStart > 0 && hoursUntilStart <= 5 {
                return .orange
            }
        }
        // Grün: Stundenlohn >= 18 EUR
        if let pay = job.payAmount, pay >= 18 {
            return .green
        }
        return SS.primary
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "scope")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No jobs nearby")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("No jobs found within a 100 km radius.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await loadJobs() }
            } label: {
                Text("Refresh")
                    .fontWeight(.semibold)
            }
            .buttonStyle(SSPrimaryButtonStyle())
            .padding(.horizontal, 60)
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
        await jobStore.loadNearbyJobs(lat: lat, lng: lng)

        // Kamera auf Nutzer-Position setzen
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
            )
        }

        isLoading = false
    }
}

// MARK: - LegendDot
private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - RadarJobCard
/// Job-Karte für die Radar-Liste — hebt die ausgewählte Karte hervor
private struct RadarJobCard: View {
    let job: Job
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Logo
            Text(job.logoEmoji)
                .font(.system(size: 26))
                .frame(width: 48, height: 48)
                .background(Color.gray.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Text(job.company)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Label(job.distanceText, systemImage: "location")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Label(job.payText, systemImage: "banknote")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isHighlighted ? SS.primary : Color.gray.opacity(0.12),
                    lineWidth: isHighlighted ? 2 : 1
                )
        )
        .shadow(
            color: isHighlighted ? SS.primary.opacity(0.15) : .black.opacity(0.04),
            radius: isHighlighted ? 8 : 4,
            x: 0, y: 2
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHighlighted)
    }
}
