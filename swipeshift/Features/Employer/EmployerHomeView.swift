//
//  EmployerHomeView.swift
//  swipeShift
//

import SwiftUI

struct EmployerHomeView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var messageStore: MessageStore
    @ObservedObject private var push = PushNotificationManager.shared

    @State private var selectedTab: EmployerTab = .dashboard
    @State private var showPostJob = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                DS.Color.bg.ignoresSafeArea()

                // MARK: - Tab Content
                Group {
                    switch selectedTab {
                    case .dashboard:
                        EmployerDashboardView(
                            onPostJob:        { showPostJob = true },
                            onViewJobs:       { selectedTab = .jobs },
                            onViewApplicants: { selectedTab = .applicants }
                        )
                        .environmentObject(userStore)

                    case .jobs:
                        AllPostedJobsView()

                    case .applicants:
                        AllApplicantsView()
                            .padding(.bottom, DS.tabBarInset)

                    case .messages:
                        MessagesView(isEmployerMode: true)
                            .environmentObject(messageStore)
                            .padding(.bottom, DS.tabBarInset)

                    case .profile:
                        EmployerProfileTab()
                            .environmentObject(userStore)
                            .dsTabBarInset()
                    }
                }
                // Dashboard, Jobs und Profil scrollen unter der schwebenden TabBar weiter (Inset via .dsTabBarInset());
                // Bewerber und Messages behalten den festen Abstand.
                .ignoresSafeArea(edges: .bottom)

                // MARK: - Tab Bar
                VStack(spacing: 0) {
                    Spacer()
                    EmployerTabBar(
                        selectedTab: $selectedTab,
                        unreadMessageCount: messageStore.employerUnreadCount
                    )
                    .padding(.bottom, 8)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarHidden(true)
            #if DEBUG
            .debugEmployerRouting(selectedTab: $selectedTab, showPostJob: $showPostJob)
            #endif
            .task { await messageStore.loadConversations() }
            // Home ist sichtbar → eingeloggt + Onboarding fertig: einmalig Push-Berechtigung erfragen / Token registrieren
            .task { await PushNotificationManager.shared.onHomeAppeared() }
            // Tap auf eine Push-Benachrichtigung (auch Kaltstart)
            // TODO: Es gibt keinen Employer-Deep-Link auf einen einzelnen Job/Bewerber — Tap oeffnet den passenden Tab.
            .onChange(of: push.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                push.pendingRoute = nil
                // Tap aus der Benachrichtigung eines anderen Kontos (nach Konto-Wechsel) nie hier ausfuehren
                guard route.belongs(to: userStore.currentUser?.id) else { return }
                switch route.type {
                case "chat":
                    push.pendingConversationId = route.conversationId
                    selectedTab = .messages
                case "applicants":           selectedTab = .applicants
                case "job", "payments":      selectedTab = .jobs
                case "reviews", "account":   selectedTab = .profile
                default: break
                }
            }
            .sheet(isPresented: $showPostJob) {
                PostJobView()
                    .environmentObject(userStore)
            }
        }
    }
}

// MARK: - Employer Profile Tab
private struct EmployerProfileTab: View {
    @EnvironmentObject var userStore: UserStore
    @State private var showEditProfile = false
    @State private var showFinancial      = false
    @State private var showCalendar       = false
    @State private var showSavedApplicants = false
    @State private var showSettings       = false
    @State private var showLogoutAlert = false

    private var companyName: String { userStore.currentUser?.companyName ?? "My Company" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.xl) {

                // Profil-Header
                VStack(spacing: DS.Spacing.sm) {
                    DSAvatar(text: "🏢", size: 80, shape: .circle)

                    VStack(spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(companyName)
                                .dsFont(.title)
                                .foregroundStyle(DS.Color.text)
                            Image(systemName: "checkmark.seal.fill")
                                .font(DS.Font.make(16, .semibold))
                                .foregroundStyle(DS.Color.primary)
                                .accessibilityLabel("Verified")
                        }

                        if let location = userStore.currentUser?.location {
                            Text(location)
                                .dsFont(.body)
                                .foregroundStyle(DS.Color.text2)
                        }

                        if let industry = userStore.currentUser?.industry {
                            Text(industry)
                                .dsFont(.callout)
                                .foregroundStyle(DS.Color.muted)
                        }
                    }

                    // Edit Profile Button
                    Button {
                        showEditProfile = true
                    } label: {
                        Text("Edit Profile")
                    }
                    .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                }
                .frame(maxWidth: .infinity)

                // Navigation Liste
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    DSSection("Manage") {
                        ProfileActionRow(icon: "briefcase",   label: "Job Management",   showsDivider: false) {}
                        ProfileActionRow(icon: "bookmark",    label: "Saved Applicants") { showSavedApplicants = true }
                        ProfileActionRow(icon: "chart.bar",   label: "Financial Overview") { showFinancial = true }
                        ProfileActionRow(icon: "calendar",    label: "Calendar")         { showCalendar = true }
                    }
                    DSSection("Account") {
                        ProfileActionRow(icon: "gearshape",   label: "Settings",         showsDivider: false) { showSettings = true }
                        ProfileActionRow(icon: "person.crop.circle.badge.questionmark", label: "Help & Support") {}

                        // Logout
                        DSRow("Log Out", systemIcon: "rectangle.portrait.and.arrow.right", iconTone: .danger) {
                            DS.Haptics.warning()
                            showLogoutAlert = true
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xl)
        }
        .dsBackground()
        .navigationDestination(isPresented: $showEditProfile) {
            EditEmployerProfileView()
                .environmentObject(userStore)
        }
        .navigationDestination(isPresented: $showFinancial) {
            EmployerFinancialView()
        }
        .navigationDestination(isPresented: $showCalendar) {
            EmployerCalendarView()
        }
        .navigationDestination(isPresented: $showSavedApplicants) {
            SavedApplicantsView()
        }
        // TODO: Employer-spezifisches "Payments & Billing" (Wireframe) — aktuell teilt sich der Employer
        // die Account Settings des Workers (inkl. "Payments & Payouts")
        .navigationDestination(isPresented: $showSettings) {
            AccountSettingsView()
                .environmentObject(userStore)
        }
        .alert("Log Out?", isPresented: $showLogoutAlert) {
            Button("Log Out", role: .destructive) { userStore.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out of your account.")
        }
    }
}
