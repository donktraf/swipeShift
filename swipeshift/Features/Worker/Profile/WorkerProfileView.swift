//
//  WorkerProfileView.swift
//  swipeShift
//

import SwiftUI

struct WorkerProfileView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var showLogoutAlert = false
    @State private var rating: Double = 0
    @State private var reviewCount: Int = 0
    @State private var openApplicationsCount: Int = 0
    @State private var savedCount: Int = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                profileHeader
                    .padding(.bottom, 24)
                // Eigene Zuverlaessigkeit (Anwesenheit, No-Shows, kurzfristige Stornos) — nur der Worker selbst und Employer sehen sie
                WorkerReliabilityCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                navigationList
                Spacer().frame(height: 100)
            }
        }
        .background(SS.background().ignoresSafeArea())
        .task {
            if let data = try? await APIClient.shared.fetchWorkerReviews() {
                rating = data.overallRating
                reviewCount = data.totalJobs
            }
            // Echte Counts für die Nav-Badges laden (analog zu den bereits live gespeisten
            // Badges im Employer-Dashboard), statt hartcodierter Platzhalter-Zahlen.
            async let applications = try? APIClient.shared.fetchWorkerApplications()
            async let savedJobs    = try? APIClient.shared.fetchWorkerSaved()
            async let savedCompanies = try? APIClient.shared.fetchSavedCompanies()
            let (apps, jobs, companies) = await (applications, savedJobs, savedCompanies)
            openApplicationsCount = apps?.filter { $0.displayStatus == "applied" }.count ?? 0
            savedCount = (jobs?.count ?? 0) + (companies?.count ?? 0)
        }
        .alert("Log Out?", isPresented: $showLogoutAlert) {
            Button("Log Out", role: .destructive) { userStore.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out of your account.")
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            // Profilfoto
            ZStack {
                if let urlStr = userStore.currentUser?.profilePhotoUrl,
                   let url = URL(string: urlStr) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarPlaceholder
                    }
                    .frame(width: 90, height: 90)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }
            }

            // Name + Verified Badge
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    let name = [userStore.currentUser?.firstName,
                                userStore.currentUser?.lastName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    Text(name.isEmpty ? "My Profile" : name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                }

                Text("Verified Worker")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))

                if reviewCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("(\(reviewCount) Review\(reviewCount == 1 ? "" : "s"))")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    Text("No reviews yet")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Edit Profile Button
            NavigationLink {
                EditProfileView()
                    .environmentObject(userStore)
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
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 90, height: 90)
            Image(systemName: "person.fill")
                .font(.system(size: 38))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Navigation Liste

    private var navigationList: some View {
        VStack(spacing: 0) {
            NavigationLink {
                JobApplicationsView()
            } label: {
                ProfileNavItem(icon: "briefcase.fill", label: "Job Applications",
                                badge: openApplicationsCount > 0 ? "\(openApplicationsCount)" : nil)
            }
            Divider().padding(.leading, 52)

            NavigationLink {
                WorkerCalendarView()
            } label: {
                ProfileNavItem(icon: "calendar", label: "Calendar", badge: nil)
            }
            Divider().padding(.leading, 52)

            NavigationLink {
                FinancialOverviewView()
            } label: {
                ProfileNavItem(icon: "chart.pie.fill", label: "Financial Overview", badge: nil)
            }
            Divider().padding(.leading, 52)

            NavigationLink {
                SavedView()
            } label: {
                ProfileNavItem(icon: "bookmark.fill", label: "Saved",
                                badge: savedCount > 0 ? "\(savedCount)" : nil)
            }
            Divider().padding(.leading, 52)

            NavigationLink {
                ReviewsView()
            } label: {
                ProfileNavItem(icon: "star.bubble.fill", label: "Your Ratings", badge: nil)
            }
            Divider().padding(.leading, 52)

            NavigationLink {
                SettingsSupportView()
            } label: {
                ProfileNavItem(icon: "gearshape.fill", label: "Settings & Support", badge: nil)
            }
            Divider().padding(.leading, 52)

            NavigationLink {
                AccountSettingsView()
            } label: {
                ProfileNavItem(icon: "person.crop.circle.badge.gearshape", label: "Account Settings", badge: nil)
            }
            Divider().padding(.leading, 52)

            NavigationLink {
                HelpSupportPlaceholderView()
            } label: {
                ProfileNavItem(icon: "questionmark.circle.fill", label: "Help & Support", badge: nil)
            }
            Divider().padding(.leading, 52)

            // Logout
            Button { showLogoutAlert = true } label: {
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
    }
}

// MARK: - ProfileNavItem

private struct ProfileNavItem: View {
    let icon: String
    let label: String
    let badge: String?

    var body: some View {
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

            if let badge {
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SS.primary)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
                .padding(.trailing, 14)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Placeholder Sub-Screens

struct SettingsSupportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreenShell(title: "Settings & Support") {
            VStack(spacing: 0) {
                SettingsRow(icon: "bell.fill",         label: "Notifications")      {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "moon.fill",         label: "Dark Mode")          {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "globe",             label: "Language")           {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "questionmark.circle", label: "FAQ")              {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "envelope.fill",    label: "Contact Us")  {}
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }
}

struct AccountSettingsPlaceholderView: View {
    var body: some View {
        SubScreenShell(title: "Account Settings") {
            VStack(spacing: 0) {
                SettingsRow(icon: "envelope.fill",      label: "Change Email")       {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "lock.fill",          label: "Change Password")     {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "iphone",             label: "Active Devices")       {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "shield.fill",        label: "Privacy & Data") {}
                Divider().padding(.leading, 52)
                SettingsRow(icon: "trash.fill",         label: "Delete Account", tint: .red) {}
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }
}

struct HelpSupportPlaceholderView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SubScreenShell(title: "Help & Support") {
            VStack(spacing: 0) {
                SettingsRow(icon: "book.fill",        label: "Guide") {
                    openURL(AppConfig.websiteURL.appendingPathComponent("guide"))
                }
                Divider().padding(.leading, 52)
                SettingsRow(icon: "bubble.left.fill", label: "Live Chat") {
                    openURL(URL(string: "mailto:support@swipeshift.app")!)
                }
                Divider().padding(.leading, 52)
                SettingsRow(icon: "doc.text.fill",    label: "Terms & Conditions") {
                    openURL(AppConfig.websiteURL.appendingPathComponent("terms"))
                }
                Divider().padding(.leading, 52)
                SettingsRow(icon: "hand.raised.fill", label: "Privacy Policy") {
                    openURL(AppConfig.websiteURL.appendingPathComponent("privacy"))
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Shared Sub-Screen Components

/// Gemeinsames Shell-Layout für alle Profile-Unterseiten
struct SubScreenShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let trailingButton: AnyView?
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title         = title
        self.trailingButton = nil
        self.content       = content()
    }

    init<T: View>(title: String, @ViewBuilder trailing: () -> T, @ViewBuilder content: () -> Content) {
        self.title          = title
        self.trailingButton = AnyView(trailing())
        self.content        = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            SS.background().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Custom Header
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                        Spacer()
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        if let btn = trailingButton {
                            btn.frame(width: 40, height: 40)
                        } else {
                            Color.clear.frame(width: 40, height: 40)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    content

                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

private struct SettingsRow: View {
    let icon: String
    let label: String
    var tint: Color = SS.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(tint)
                    .frame(width: 28)
                    .padding(.leading, 14)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(tint == .red ? .red : .primary)
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
