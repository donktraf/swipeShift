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
            VStack(spacing: DS.Spacing.xl) {
                profileHeader
                // Eigene Zuverlaessigkeit (Anwesenheit, No-Shows, kurzfristige Stornos) — nur der Worker selbst und Employer sehen sie
                WorkerReliabilityCard()
                navigationList
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xl)
        }
        .dsTabBarInset()
        .refreshable { await loadCounts() }
        .dsBackground()
        .task { await loadCounts() }
        .alert("Log Out?", isPresented: $showLogoutAlert) {
            Button("Log Out", role: .destructive) { userStore.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out of your account.")
        }
    }

    private func loadCounts() async {
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

    // MARK: - Header

    private var fullName: String {
        [userStore.currentUser?.firstName, userStore.currentUser?.lastName]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private var profileHeader: some View {
        VStack(spacing: DS.Spacing.sm) {
            // Profilfoto
            if let urlStr = userStore.currentUser?.profilePhotoUrl,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .accessibilityHidden(true)
            } else {
                avatarPlaceholder
            }

            // Name + Verified Badge
            VStack(spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(fullName.isEmpty ? "My Profile" : fullName)
                        .dsFont(.title)
                        .foregroundStyle(DS.Color.text)
                    Image(systemName: "checkmark.seal.fill")
                        .font(DS.Font.make(16, .semibold))
                        .foregroundStyle(DS.Color.primary)
                        .accessibilityHidden(true)
                }

                Text("Verified Worker")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.muted)

                if reviewCount > 0 {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "star.fill")
                            .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                            .foregroundStyle(DS.Color.warning)
                        Text(String(format: "%.1f", rating))
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.text)
                        Text("(\(reviewCount) Review\(reviewCount == 1 ? "" : "s"))")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.muted)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("No reviews yet")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
            }

            // Edit Profile Button
            NavigationLink {
                EditProfileView()
                    .environmentObject(userStore)
            } label: {
                Text("Edit Profile")
            }
            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarPlaceholder: some View {
        Group {
            if fullName.isEmpty {
                Image(systemName: "person.fill")
                    .font(DS.Font.make(36, .semibold, relativeTo: nil))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(width: 88, height: 88)
                    .background(DS.Color.primarySoft, in: Circle())
                    .accessibilityHidden(true)
            } else {
                DSAvatar(text: DSAvatar.initials(from: fullName), size: 88, shape: .circle)
            }
        }
    }

    // MARK: - Navigation Liste

    private var navigationList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            DSSection("Work") {
                ProfileNavRow(icon: "briefcase.fill", label: "Job Applications",
                              badge: openApplicationsCount > 0 ? "\(openApplicationsCount)" : nil,
                              showsDivider: false) { JobApplicationsView() }
                ProfileNavRow(icon: "calendar", label: "Calendar") { WorkerCalendarView() }
                ProfileNavRow(icon: "chart.pie.fill", label: "Financial Overview") { FinancialOverviewView() }
                ProfileNavRow(icon: "bookmark.fill", label: "Saved",
                              badge: savedCount > 0 ? "\(savedCount)" : nil) { SavedView() }
            }

            DSSection("You") {
                ProfileNavRow(icon: "star.bubble.fill", label: "Your Ratings", showsDivider: false) { ReviewsView() }
                ProfileNavRow(icon: "gearshape.fill", label: "Settings & Support") { SettingsSupportView() }
                ProfileNavRow(icon: "person.crop.circle.badge.gearshape", label: "Account Settings") { AccountSettingsView() }
            }

            DSSection("Help") {
                ProfileNavRow(icon: "questionmark.circle.fill", label: "Help & Support", showsDivider: false) {
                    HelpSupportPlaceholderView()
                }
                // Logout
                DSRow("Log Out", systemIcon: "rectangle.portrait.and.arrow.right", iconTone: .danger) {
                    DS.Haptics.warning()
                    showLogoutAlert = true
                }
            }
        }
    }
}

// MARK: - ProfileNavRow

/// Press-Hintergrund fuer Zeilen, die als NavigationLink aufgebaut sind (Pendant zum Button-Stil in DSRow).
struct DSRowLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Color.surface2.opacity(0.6) : Color.clear)
    }
}

/// Flache Navigationszeile mit Icon-Kachel, optionalem Zaehler und Chevron.
struct ProfileNavRow<Destination: View>: View {
    let icon: String
    let label: String
    var badge: String?
    var showsDivider: Bool = true
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            DSRow(label, systemIcon: icon, showsChevron: true, showsDivider: showsDivider) {
                if let badge {
                    Text(badge)
                        .font(DS.Font.make(12, .bold, relativeTo: .caption))
                        .foregroundStyle(DS.Color.onPrimary)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, DS.Spacing.xxs)
                        .background(DS.Color.primary, in: Capsule())
                }
            }
        }
        .buttonStyle(DSRowLinkStyle())
        .simultaneousGesture(TapGesture().onEnded { DS.Haptics.light() })
    }
}

/// Wie `ProfileNavRow`, aber mit Aktion statt NavigationLink (z. B. Employer-Profil mit navigationDestination).
struct ProfileActionRow: View {
    let icon: String
    let label: String
    var showsDivider: Bool = true
    let action: () -> Void

    var body: some View {
        DSRow(label, systemIcon: icon, showsChevron: true, showsDivider: showsDivider) {
            DS.Haptics.light()
            action()
        }
    }
}

// MARK: - Placeholder Sub-Screens

struct SettingsSupportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreenShell(title: "Settings & Support", padded: true) {
            DSSection("Settings") {
                SettingsRow(icon: "bell.fill",         label: "Notifications", showsDivider: false)      {}
                SettingsRow(icon: "moon.fill",         label: "Dark Mode")          {}
                SettingsRow(icon: "globe",             label: "Language")           {}
                SettingsRow(icon: "questionmark.circle", label: "FAQ")              {}
                SettingsRow(icon: "envelope.fill",    label: "Contact Us")  {}
            }
        }
    }
}

struct AccountSettingsPlaceholderView: View {
    var body: some View {
        SubScreenShell(title: "Account Settings", padded: true) {
            DSSection("Account") {
                SettingsRow(icon: "envelope.fill",      label: "Change Email", showsDivider: false)       {}
                SettingsRow(icon: "lock.fill",          label: "Change Password")     {}
                SettingsRow(icon: "iphone",             label: "Active Devices")       {}
                SettingsRow(icon: "shield.fill",        label: "Privacy & Data") {}
                SettingsRow(icon: "trash.fill",         label: "Delete Account", tone: .danger) {}
            }
        }
    }
}

struct HelpSupportPlaceholderView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SubScreenShell(title: "Help & Support", padded: true) {
            DSSection("Help") {
                SettingsRow(icon: "book.fill",        label: "Guide", showsDivider: false) {
                    openURL(AppConfig.websiteURL.appendingPathComponent("guide"))
                }
                SettingsRow(icon: "bubble.left.fill", label: "Live Chat") {
                    openURL(URL(string: "mailto:support@swipeshift.app")!)
                }
                SettingsRow(icon: "doc.text.fill",    label: "Terms & Conditions") {
                    openURL(AppConfig.websiteURL.appendingPathComponent("terms"))
                }
                SettingsRow(icon: "hand.raised.fill", label: "Privacy Policy") {
                    openURL(AppConfig.websiteURL.appendingPathComponent("privacy"))
                }
            }
        }
    }
}

// MARK: - Shared Sub-Screen Components

/// Gemeinsames Shell-Layout für alle Profile-Unterseiten: heller DS-Kopf (Zurück, Titel, optional Trailing)
/// + scrollbarer Inhalt. `padded: true` setzt den Bildschirmrand (20) um den Inhalt; Aufrufer mit eigenem
/// Rand lassen es aus.
struct SubScreenShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let padded: Bool
    let trailingButton: AnyView?
    let content: Content

    init(title: String, padded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title         = title
        self.padded        = padded
        self.trailingButton = nil
        self.content       = content()
    }

    init<T: View>(title: String, padded: Bool = false, @ViewBuilder trailing: () -> T, @ViewBuilder content: () -> Content) {
        self.title          = title
        self.padded         = padded
        self.trailingButton = AnyView(trailing())
        self.content        = content()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                // Kopf
                HStack(spacing: DS.Spacing.sm) {
                    DSIconButton(systemName: "chevron.left", label: "Back") { dismiss() }
                    Spacer(minLength: 0)
                    Text(title)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if let btn = trailingButton {
                        btn.frame(width: 44, height: 44)
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)

                Group {
                    if padded {
                        content.padding(.horizontal, DS.Spacing.screenEdge)
                    } else {
                        content
                    }
                }

                Spacer().frame(height: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .navigationBarHidden(true)
    }
}

/// Flache Einstellungszeile (Icon-Kachel + Titel + Chevron).
private struct SettingsRow: View {
    let icon: String
    let label: String
    var tone: DS.Tone = .primary
    var showsDivider: Bool = true
    let action: () -> Void

    var body: some View {
        DSRow(label, systemIcon: icon, iconTone: tone, showsChevron: true, showsDivider: showsDivider, action: action)
    }
}
