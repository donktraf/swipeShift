//
//  WorkerHomeView.swift
//  swipeShift
//

import SwiftUI

struct WorkerHomeView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var messageStore: MessageStore
    @ObservedObject private var push = PushNotificationManager.shared

    @State private var selectedTab: WorkerTab = .home

    // Für Navigation zu Kategorie-JobListe und allen Jobs
    @State private var selectedCategory: JobCategory? = nil
    @State private var navigateToCategoryList = false
    @State private var navigateToAllJobs = false

    // Geteilter Job aus Deep Link (swipeshift://job/<id>)
    @State private var deepLinkJob: Job?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                DS.Color.bg.ignoresSafeArea()

                // MARK: - Tab Content
                Group {
                    switch selectedTab {
                    case .home:
                        WorkerHomeTabView(
                            onCategorySelected: { category in
                                selectedCategory = category
                                navigateToCategoryList = true
                            },
                            onViewAllJobs: {
                                navigateToAllJobs = true
                            },
                            onGoToRadar: {
                                selectedTab = .radar
                            },
                            onGoToSwipe: {
                                selectedTab = .swipe
                            }
                        )

                    case .radar:
                        RadarView(
                            lat: userStore.currentUser?.lat ?? 48.7758,
                            lng: userStore.currentUser?.lng ?? 9.1829
                        )

                    case .messages:
                        MessagesView()
                            .environmentObject(messageStore)

                    case .swipe:
                        JobSwipeView()
                            .onAppear {
                                if jobStore.selectedLocation == nil,
                                   let location = userStore.currentUser?.location {
                                    jobStore.selectedLocation = location
                                }
                            }

                    case .profile:
                        WorkerProfileView()
                            .environmentObject(userStore)
                    }
                }
                // Home scrollt unter der schwebenden TabBar weiter (Inset via .dsTabBarInset() im Tab);
                // die übrigen Tabs behalten den festen Abstand.
                .ignoresSafeArea(edges: .bottom)

                // MARK: - Tab Bar
                VStack(spacing: 0) {
                    Spacer()
                    AppTabBar(
                        selectedTab: $selectedTab,
                        unreadMessageCount: messageStore.unreadCount
                    )
                    .padding(.bottom, 8)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarHidden(true)
            #if DEBUG
            .debugWorkerRouting(selectedTab: $selectedTab, navigateToAllJobs: $navigateToAllJobs)
            #endif
            .task { await messageStore.loadConversations() }
            // Home ist sichtbar → eingeloggt + Onboarding fertig: einmalig Push-Berechtigung erfragen / Token registrieren
            .task { await PushNotificationManager.shared.onHomeAppeared() }
            // Tap auf eine Push-Benachrichtigung (auch Kaltstart)
            .onChange(of: push.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                push.pendingRoute = nil
                // Tap aus der Benachrichtigung eines anderen Kontos (nach Konto-Wechsel) nie hier ausfuehren
                guard route.belongs(to: userStore.currentUser?.id) else { return }
                handlePushRoute(route)
            }
            // Navigation zu Kategorie-Liste
            .navigationDestination(isPresented: $navigateToCategoryList) {
                if let category = selectedCategory {
                    CategoryJobListView(category: category)
                        .environmentObject(jobStore)
                }
            }
            .navigationDestination(isPresented: $navigateToAllJobs) {
                JobListView()
                    .environmentObject(jobStore)
                    .environmentObject(userStore)
            }
            // initial: true → auch Links, die die App kalt gestartet haben, werden geoeffnet
            .onChange(of: jobStore.pendingDeepLinkJobId, initial: true) { _, jobId in
                guard let jobId else { return }
                jobStore.pendingDeepLinkJobId = nil
                Task { deepLinkJob = try? await APIClient.shared.fetchJob(jobId: jobId) }
            }
            .sheet(item: $deepLinkJob) { job in
                NavigationStack {
                    JobDetailView(job: job)
                        .environmentObject(jobStore)
                        .environmentObject(userStore)
                }
            }
        }
    }
}

extension WorkerHomeView {
    /// Push-Tap → vorhandene Navigation: Job-Detail per Deep-Link-Mechanismus, Chat/Payments/Account ueber Tabs
    fileprivate func handlePushRoute(_ route: PushRoute) {
        switch route.type {
        case "chat":
            push.pendingConversationId = route.conversationId
            selectedTab = .messages
        case "job":
            if let jobId = route.jobId { jobStore.pendingDeepLinkJobId = jobId }
        case "payments", "reviews", "account":
            selectedTab = .profile
        default:
            break
        }
    }
}

#Preview {
    WorkerHomeView()
        .environmentObject(UserStore())
        .environmentObject(JobStore())
        .environmentObject(MessageStore())
}
