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

                SS.background().ignoresSafeArea()

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

                    case .messages:
                        MessagesView(isEmployerMode: true)
                            .environmentObject(messageStore)

                    case .profile:
                        EmployerProfileTab()
                            .environmentObject(userStore)
                    }
                }
                .padding(.bottom, 80)

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

// MARK: - Employer Jobs Tab
private struct EmployerJobsTab: View {
    let onPostJob: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "briefcase.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("Posted Jobs")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
            Text("Your posted jobs will appear here.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onPostJob) {
                Label("Post a Job", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SS.background().ignoresSafeArea())
    }
}

// MARK: - Employer Placeholder Tab
private struct EmployerPlaceholderTab: View {
    let title: String
    let icon: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
            Text(description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SS.background().ignoresSafeArea())
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
