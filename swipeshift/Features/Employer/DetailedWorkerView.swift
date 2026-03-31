//
//  DetailedWorkerView.swift
//  swipeShift
//

import SwiftUI

// MARK: - DetailedWorkerView

struct DetailedWorkerView: View {
    let applicant: Applicant
    let onAccept:  () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showAcceptAlert  = false
    @State private var showDeclineAlert = false

    private var user: ApplicantUser? { applicant.user }

    var body: some View {
        ZStack(alignment: .bottom) {
            SS.background().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    if let job = applicant.job { jobSection(job) }
                    ratingsSection
                    availabilitySection
                    experienceSection
                    preferencesSection
                    legalSection
                    Spacer().frame(height: 100)
                }
            }

            // Sticky Accept / Decline Footer
            actionFooter
        }
        .navigationBarHidden(true)
        .alert("Accept applicant?", isPresented: $showAcceptAlert) {
            Button("Accept") { onAccept(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(user?.fullName ?? "This applicant") will be confirmed for the shift.")
        }
        .alert("Decline applicant?", isPresented: $showDeclineAlert) {
            Button("Decline", role: .destructive) { onDecline(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The application from \(user?.fullName ?? "this applicant") will be declined.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            // Back Button
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 88, height: 88)
                    if let urlStr = user?.profilePhotoUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Name + Badge
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user?.fullName ?? "Unknown")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.white.opacity(0.9))
                            .font(.system(size: 16))
                    }
                    Text("Verified Worker")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                    // Sterne-Rating (Mock)
                    HStack(spacing: 3) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < 4 ? "star.fill" : "star.leadinghalf.filled")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                        }
                        Text("4.6")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("(18 Jobs)")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    if let location = user?.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Job Section (Bewerbung für)

    private func jobSection(_ job: ApplicantJob) -> some View {
        sectionCard("Applying For") {
            HStack(spacing: 12) {
                Text(job.logoEmoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 10) {
                        Label(job.shiftText, systemImage: "calendar")
                        Label(job.payText,   systemImage: "banknote")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
        }
    }

    // MARK: - Ratings

    private var ratingsSection: some View {
        sectionCard("Ratings & Reviews") {
            VStack(spacing: 0) {
                ratingRow(label: "Communication",        value: 4.7)
                Divider().padding(.leading, 16)
                ratingRow(label: "Teamwork",             value: 4.5)
                Divider().padding(.leading, 16)
                ratingRow(label: "Reliability",          value: 4.8)
                Divider().padding(.leading, 16)
                ratingRow(label: "Under Pressure",       value: 4.3)
            }
        }
    }

    private func ratingRow(label: String, value: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 14)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SS.primary)
                        .frame(width: geo.size.width * CGFloat(value / 5.0), height: 6)
                }
            }
            .frame(height: 6)

            Text(String(format: "%.1f", value))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SS.primary)
                .frame(width: 30, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Availability

    private var availabilitySection: some View {
        sectionCard("Availability & Location") {
            VStack(spacing: 0) {
                infoRow(icon: "calendar.badge.clock", label: "Available Days",
                        value: "Mon, Tue, Thu, Fri, Sat")
                Divider().padding(.leading, 52)
                infoRow(icon: "location.circle.fill", label: "Max. Travel Distance",
                        value: "20 km")
                Divider().padding(.leading, 52)
                infoRow(icon: "bolt.fill", label: "Same-day Jobs",
                        value: "Yes, available")
            }
        }
    }

    // MARK: - Experience

    private var experienceSection: some View {
        sectionCard("Work Experience") {
            VStack(spacing: 0) {
                experienceRow(category: "Hospitality", level: "1+ year", icon: "🍽️")
                Divider().padding(.leading, 52)
                experienceRow(category: "Events",      level: "3–12 months", icon: "🎪")
                Divider().padding(.leading, 52)
                experienceRow(category: "Retail",      level: "<3 months", icon: "🛍️")
            }
        }
    }

    private func experienceRow(category: String, level: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Text(icon)
                .font(.system(size: 20))
                .frame(width: 28)
                .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(category)
                    .font(.system(size: 14, weight: .semibold))
                Text(level)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        sectionCard("Job Preferences") {
            VStack(spacing: 0) {
                infoRow(icon: "briefcase.fill",    label: "Preferred Roles",
                        value: "Bartender, Event Staff")
                Divider().padding(.leading, 52)
                infoRow(icon: "moon.stars.fill",   label: "Preferred Shifts",
                        value: "Evening, Night")
                Divider().padding(.leading, 52)
                infoRow(icon: "eurosign.circle",   label: "Min. Hourly Rate",
                        value: "€13 / hour")
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        sectionCard("Legal & Compliance") {
            VStack(spacing: 0) {
                legalRow(icon: "checkmark.shield.fill", label: "Work Permit",
                         ok: true,  value: "EU Citizen")
                Divider().padding(.leading, 52)
                legalRow(icon: "person.text.rectangle", label: "Minimum Age (18+)",
                         ok: true,  value: "Confirmed")
                Divider().padding(.leading, 52)
                legalRow(icon: "doc.text.fill",         label: "Terms Accepted",
                         ok: true,  value: "Yes")
            }
        }
    }

    private func legalRow(icon: String, label: String, ok: Bool, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(ok ? .green : .red)
                .frame(width: 28)
                .padding(.leading, 14)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 13)
    }

    // MARK: - Action Footer

    private var actionFooter: some View {
        HStack(spacing: 12) {
            Button { showDeclineAlert = true } label: {
                Label("Decline", systemImage: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Button { showAcceptAlert = true } label: {
                Label("Accept", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SS.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: SS.primary.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .padding(.top, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Shared Helpers

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(SS.primary)
                .frame(width: 28)
                .padding(.leading, 14)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - Section Card Helper

private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 20)

        VStack(spacing: 0) {
            content()
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}
