//
//  EmployerHomeView.swift
//  swipeShift
//

import SwiftUI

struct EmployerHomeView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var messageStore: MessageStore

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
            .task { await messageStore.loadConversations() }
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // Profil-Header
                VStack(spacing: 12) {
                    // Company Logo Placeholder
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Text("🏢")
                            .font(.system(size: 36))
                    }

                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text(userStore.currentUser?.companyName ?? "My Company")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(SS.primary)
                                .font(.system(size: 16))
                        }

                        if let location = userStore.currentUser?.location {
                            Text(location)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        if let industry = userStore.currentUser?.industry {
                            Text(industry)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    // Edit Profile Button
                    Button {
                        showEditProfile = true
                    } label: {
                        Text("Edit Profile")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)

                // Navigation Liste
                VStack(spacing: 0) {
                    ProfileNavRow(icon: "briefcase",           label: "Job Management")       {}
                    Divider().padding(.leading, 52)
                    ProfileNavRow(icon: "bookmark",            label: "Saved Applicants")     { showSavedApplicants = true }
                    Divider().padding(.leading, 52)
                    ProfileNavRow(icon: "chart.bar",           label: "Financial Overview")   { showFinancial = true }
                    Divider().padding(.leading, 52)
                    ProfileNavRow(icon: "calendar",            label: "Calendar")             { showCalendar = true }
                    Divider().padding(.leading, 52)
                    ProfileNavRow(icon: "gearshape",           label: "Settings")             { showSettings = true }
                    Divider().padding(.leading, 52)
                    ProfileNavRow(icon: "person.crop.circle.badge.questionmark", label: "Help & Support") {}
                    Divider().padding(.leading, 52)

                    // Logout
                    Button {
                        showLogoutAlert = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                                .frame(width: 28)
                                .padding(.leading, 14)

                            Text("Log Out")
                                .font(.system(size: 15))
                                .foregroundColor(.red)

                            Spacer()
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

                Spacer().frame(height: 100)
            }
        }
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

private struct ProfileNavRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(SS.primary)
                    .frame(width: 28)
                    .padding(.leading, 14)

                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
