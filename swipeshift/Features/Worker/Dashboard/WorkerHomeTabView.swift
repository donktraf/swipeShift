
//
//  WorkerHomeTabView.swift
//  swipeShift
//

import SwiftUI
import Combine

struct WorkerHomeTabView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var messageStore: MessageStore
    @ObservedObject private var badge = NotificationBadgeStore.shared
    @StateObject private var confirmedModel = ConfirmedShiftModel()
    // Stabiler Minuten-Takt (nicht in body erzeugen, sonst startet der Countdown bei jedem Re-Render neu)
    private let minuteTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    // Chat-Navigation lebt hier (immer vorhanden), nicht in der Karte — sonst wuerde der Chat mit der Karte abgebaut
    @StateObject private var applicationNavigation = ApplicationNavigation()
    @AppStorage(ConfirmedShiftLogic.dismissedKey) private var dismissedConfirmedRaw: String = ""
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    // Callback wenn User eine Kategorie auswählt
    let onCategorySelected: (JobCategory) -> Void
    // Callback wenn User "View All" in einer Sektion tippt
    let onViewAllJobs: () -> Void
    // Callbacks für Bottom CTAs
    let onGoToRadar: () -> Void
    let onGoToSwipe: () -> Void

    // Skeleton nur beim ersten Laden (nicht beim Pull-to-refresh)
    @State private var hasLoaded = false

    private var greetingLine: String {
        let name = userStore.currentUser?.firstName ?? "there"
        if let location = userStore.currentUser?.location, !location.isEmpty {
            return "Hi \(name) · \(location)"
        }
        return "Hi \(name)"
    }

    private func reload() async {
        if let location = userStore.currentUser?.location {
            jobStore.selectedLocation = location
        }
        // Basis-Jobs + alle Dashboard-Sektionen parallel laden
        // Wenn kein Standort gesetzt → alle Jobs laden als Fallback
        async let base     = jobStore.selectedLocation != nil
                                ? jobStore.loadJobs()
                                : jobStore.loadJobsAll()
        async let sections = jobStore.loadDashboardSections()
        async let saved    = jobStore.loadSavedJobIds()
        _ = await (base, sections, saved)
        hasLoaded = true
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {

                // MARK: - Header
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(greetingLine)
                            .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(DS.Color.muted)
                            .lineLimit(1)

                        Text("Your Personal Job Dashboard")
                            .dsFont(.display)
                            .foregroundStyle(DS.Color.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }

                    Spacer(minLength: DS.Spacing.xs)

                    // Notification Bell (Look wie DSIconButton, Ziel = NavigationLink)
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Image(systemName: "bell")
                            .font(DS.Font.make(17, .semibold))
                            .foregroundStyle(DS.Color.text)
                            .frame(width: 44, height: 44)
                            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .strokeBorder(DS.Color.border, lineWidth: 1)
                            )
                            .notificationBadge(badge.unreadCount)
                    }
                    .buttonStyle(.dsPressable)
                    .simultaneousGesture(TapGesture().onEnded { DS.Haptics.light() })
                    .accessibilityLabel(badge.unreadCount > 0 ? "Notifications, \(badge.unreadCount) unread" : "Notifications")
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)

                // MARK: - Confirmed-Karte (naechste angenommene Schicht)
                let confirmed = confirmedModel.visible(dismissedRaw: dismissedConfirmedRaw, now: now)
                if let next = confirmed.first {
                    ConfirmedShiftCard(
                        item: next,
                        more: confirmed.count - 1,
                        now: now,
                        onOpenChat: {
                            applicationNavigation.openChat(conversationId: next.conversationId, messageStore: messageStore)
                        },
                        onDismiss: {
                            dismissedConfirmedRaw = ConfirmedShiftLogic.appendId(next.id, to: dismissedConfirmedRaw)
                        }
                    )
                }

                // MARK: - View All Jobs
                NavigationLink {
                    JobListView()
                } label: {
                    DSCard {
                        HStack(spacing: DS.Spacing.sm) {
                            DSIconTile(systemName: "magnifyingglass", tone: .primary)
                            Text("View All Available Jobs")
                                .font(DS.Font.make(15, .bold))
                                .foregroundStyle(DS.Color.text)
                            Spacer(minLength: DS.Spacing.xs)
                            if !jobStore.jobs.isEmpty {
                                Text("\(jobStore.jobs.count)")
                                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                                    .foregroundStyle(DS.Color.muted)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Color.muted)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.dsPressable)
                .padding(.horizontal, DS.Spacing.screenEdge)

                // MARK: - Category Discovery
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Category Discovery")
                        .font(DS.Font.make(17, .bold, relativeTo: .headline))
                        .foregroundStyle(DS.Color.text)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, DS.Spacing.screenEdge)

                    CategoryScrollView(onSelect: onCategorySelected)
                }

                // MARK: - Job Sections (echte Backend-Filter)
                let loading = !hasLoaded

                JobSectionView(
                    title: "Recommended for You",
                    jobs: jobStore.recommendedJobs,
                    isLoading: loading,
                    onViewAll: onViewAllJobs
                )

                JobSectionView(
                    title: "Quick Money Jobs",
                    jobs: jobStore.quickMoneyJobs,
                    isLoading: loading,
                    onViewAll: onViewAllJobs
                )

                JobSectionView(
                    title: "Starting Soon",
                    jobs: jobStore.startingSoonJobs,
                    isLoading: loading,
                    onViewAll: onViewAllJobs
                )

                JobSectionView(
                    title: "Popular This Week",
                    jobs: jobStore.popularJobs,
                    isLoading: loading,
                    onViewAll: onViewAllJobs
                )

                // Alle Jobs als Fallback-Sektion wenn andere leer sind
                if hasLoaded && jobStore.recommendedJobs.isEmpty && jobStore.quickMoneyJobs.isEmpty {
                    JobSectionView(
                        title: "Here are jobs you might like today",
                        jobs: jobStore.jobs,
                        onViewAll: onViewAllJobs
                    )
                }

                // MARK: - Bottom CTAs (Kacheln)
                HStack(spacing: DS.Spacing.sm) {
                    ctaTile(label: "Nearby jobs?", title: "Go to Radar →", tone: .success, action: onGoToRadar)
                    ctaTile(label: "Decide fast?", title: "Try Swipe →", tone: .primary, action: onGoToSwipe)
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.bottom, DS.Spacing.xl)
            }
        }
        .dsTabBarInset()
        .dsBackground()
        .refreshable {
            async let reloaded: Void = reload()
            async let badgeRefresh: Void = badge.refresh()
            async let confirmed: Void = confirmedModel.load()
            _ = await (reloaded, badgeRefresh, confirmed)
        }
        .task { await reload() }
        // Glocken-Badge: beim Erscheinen und beim Zurueckkommen in den Vordergrund
        .task { await badge.refresh() }
        .task { await confirmedModel.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                Task {
                    await badge.refresh()
                    await confirmedModel.load()
                }
            }
        }
        // Karte verschwindet nach Schichtende, ohne dass neu geladen werden muss
        .onReceive(minuteTicker) { now = $0 }
        .applicationNavigation(applicationNavigation)
    }
}

extension WorkerHomeTabView {
    /// Getönte Kachel für die Bottom-CTAs.
    fileprivate func ctaTile(label: String, title: String, tone: DS.Tone, action: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.light()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(DS.Font.make(12, .bold, relativeTo: .caption))
                    .foregroundStyle(tone.foreground)
                Text(title)
                    .font(DS.Font.make(15, .extrabold))
                    .foregroundStyle(DS.Color.text)
            }
            .padding(DS.Spacing.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.soft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        }
        .buttonStyle(.dsPressable)
    }
}
