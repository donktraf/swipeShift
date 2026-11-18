//
//  DetailedWorkerView.swift
//  swipeShift
//
//  Vollstaendiges Worker-Profil aus Arbeitgeber-Sicht. Alle Werte kommen von
//  GET /employer/workers/:userId (frueher: fest eingetragene Beispieldaten).
//

import SwiftUI

// MARK: - DetailedWorkerView

struct DetailedWorkerView: View {
    let applicant: Applicant
    let onAccept:  () -> Void
    let onDecline: () -> Void
    /// Job, in dessen Kontext das Profil geoeffnet wird (steuert den Match-Hinweis); nil = ohne Job-Kontext
    var jobId: String? = nil
    /// false → ohne Accept/Decline-Footer (z.B. wenn aus dem Chat geoeffnet)
    var showActions: Bool = true
    /// gesetzt, wenn angenommen und Conversation vorhanden → "Chat"-Button im Header
    var chatConversationId: String? = nil

    @StateObject private var chatNavigation = ApplicantChatNavigation()
    @EnvironmentObject private var messageStore: MessageStore

    @Environment(\.dismiss) private var dismiss
    @State private var showAcceptAlert  = false
    @State private var showDeclineAlert = false

    @State private var profile: WorkerProfileDTO?
    @State private var isLoading = true
    @State private var loadError: String?

    private var user: ApplicantUser? { applicant.user }
    private var worker: WorkerProfileInfo? { profile?.worker }
    private var stats: WorkerProfileStats? { profile?.stats }

    var body: some View {
        ZStack(alignment: .bottom) {
            SS.background().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    if let job = applicant.job { jobSection(job) }

                    if let profile {
                        accountSection(profile)
                        ratingsSection(profile)
                        reliabilitySection(profile)
                        pastJobsSection(profile)
                        if let bio = profile.worker.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                            aboutSection(bio)
                        }
                        availabilitySection(profile.worker)
                        selfDeclaredExperienceSection(profile.worker)
                        experienceSection(profile)
                        preferencesSection(profile.worker)
                        legalSection(profile.worker)
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 40)
                    } else if let loadError {
                        VStack(spacing: 12) {
                            Text(loadError)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                            Button("Try Again") { Task { await load() } }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 30)
                    }

                    Spacer().frame(height: 100)
                }
            }

            // Sticky Accept / Decline Footer
            if showActions { actionFooter }
        }
        .navigationBarHidden(true)
        .task { await load() }
        .applicantChatNavigation(chatNavigation)
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

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            profile = try await APIClient.shared.fetchWorkerProfile(userId: applicant.userId, jobId: jobId)
        } catch {
            loadError = "Couldn't load this worker's profile. Check your connection and try again."
        }
        isLoading = false
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
                avatar

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user?.fullName ?? "Unknown")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        if worker?.isEmailVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.white.opacity(0.9))
                                .font(.system(size: 16))
                        }
                    }
                    if worker?.isEmailVerified == true {
                        // Bewusst ehrlich: verifiziert ist bisher nur die E-Mail, keine Identitaet
                        Text("Verified email")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    if let stats {
                        ratingLine(stats)
                        if let top = stats.topWorkerCount, top > 0 {
                            TopWorkerBadge(text: "Top Worker ×\(top)")
                        }
                    }

                    if let chatConversationId {
                        Button {
                            chatNavigation.openChat(conversationId: chatConversationId, messageStore: messageStore)
                        } label: {
                            Label("Chat", systemImage: "bubble.left.and.bubble.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(SS.primary)
                                .padding(.horizontal, 18).padding(.vertical, 8)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }

                    HStack(spacing: 12) {
                        if let location = worker?.location ?? user?.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                        }
                        if let age = worker?.age {
                            Label("\(age) years", systemImage: "person.crop.circle")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.top, 2)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 88, height: 88)
            if let urlStr = worker?.profilePhotoUrl ?? user?.profilePhotoUrl, let url = URL(string: urlStr) {
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
    }

    @ViewBuilder
    private func ratingLine(_ stats: WorkerProfileStats) -> some View {
        let jobsText = "\(stats.completedJobs) job\(stats.completedJobs == 1 ? "" : "s") completed"
        if let rating = stats.overallRating {
            HStack(spacing: 3) {
                StarRow(value: rating, size: 12)
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("(\(stats.reviewCount) review\(stats.reviewCount == 1 ? "" : "s") · \(jobsText))")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
        } else {
            Text("New on SwipeShift · \(jobsText)")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Job Section (Bewerbung für)

    private func jobSection(_ job: ApplicantJob) -> some View {
        sectionCard("Applying For") {
            HStack(spacing: 12) {
                Text(job.logoEmoji)
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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

            if let hint = profile?.matchHint {
                Divider().padding(.horizontal, 14)
                Label(hint, systemImage: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SS.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    // MARK: - Account-Status

    @ViewBuilder
    private func accountSection(_ profile: WorkerProfileDTO) -> some View {
        if let account = profile.account {
            sectionCard("Account") {
                VStack(spacing: 0) {
                    infoRow(icon: "envelope", label: "Email",
                            value: account.emailVerified ? "Verified" : "Not verified")
                    if let since = account.memberSince {
                        Divider().padding(.leading, 52)
                        infoRow(icon: "calendar", label: "Member since",
                                value: since.formatted(.dateTime.month(.wide).year()))
                    }
                }
            }
        }
    }

    // MARK: - Reliability

    @ViewBuilder
    private func reliabilitySection(_ profile: WorkerProfileDTO) -> some View {
        if let reliability = profile.reliability {
            sectionCard("Reliability") {
                VStack(alignment: .leading, spacing: 6) {
                    ReliabilityLabel(summary: reliability, font: 14)
                    Text(reliability.isNew
                         ? "The show-up rate appears after 3 finished shifts."
                         : "Based on finished shifts in the last 12 months.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    // MARK: - Past Jobs

    @ViewBuilder
    private func pastJobsSection(_ profile: WorkerProfileDTO) -> some View {
        if let jobs = profile.pastJobs {
            sectionCard("Past Jobs") {
                if jobs.isEmpty {
                    Text("No completed jobs on SwipeShift yet.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 { Divider().padding(.leading, 16) }
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.jobTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(job.companyName)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if let date = job.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let rating = job.rating {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill").foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating)).fontWeight(.semibold)
                                }
                                .font(.system(size: 13))
                            } else {
                                Text("Not rated")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Ratings

    private func ratingsSection(_ profile: WorkerProfileDTO) -> some View {
        sectionCard("Ratings & Reviews") {
            VStack(spacing: 0) {
                if let ratings = profile.stats.ratings, profile.stats.reviewCount > 0 {
                    ratingRow(label: "Communication",  value: ratings.communication)
                    Divider().padding(.leading, 16)
                    ratingRow(label: "Teamwork",       value: ratings.teamwork)
                    Divider().padding(.leading, 16)
                    ratingRow(label: "Reliability",    value: ratings.reliability)
                    Divider().padding(.leading, 16)
                    ratingRow(label: "Under Pressure", value: ratings.underPressure)
                    if ratings.workQuality != nil {
                        Divider().padding(.leading, 16)
                        ratingRow(label: "Work Quality", value: ratings.workQuality)
                    }
                    if let top = profile.stats.topWorkerCount, top > 0 {
                        Divider().padding(.leading, 16)
                        HStack {
                            TopWorkerBadge(text: "Top Worker ×\(top)")
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }

                    if let rehire = profile.stats.wouldRehirePercent {
                        Divider().padding(.leading, 16)
                        infoRow(icon: "arrow.triangle.2.circlepath", label: "Would rehire",
                                value: "\(rehire)% of employers")
                    }

                    ForEach(profile.recentReviews) { review in
                        Divider().padding(.leading, 16)
                        reviewRow(review)
                    }
                } else {
                    Text("No reviews from employers yet.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }

                // Selbsteinschaetzung aus dem Worker-Profil — klar als solche gekennzeichnet
                if let skills = profile.worker.selfRatedSkills {
                    Divider()
                    Text("SELF-ASSESSED SKILLS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    ratingRow(label: "Communication",  value: Double(skills.communication))
                    ratingRow(label: "Teamwork",       value: Double(skills.teamwork))
                    ratingRow(label: "Reliability",    value: Double(skills.reliability))
                    ratingRow(label: "Under Pressure", value: Double(skills.underPressure))
                }
            }
        }
    }

    private func ratingRow(label: String, value: Double?) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(width: 110, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SS.primary)
                        .frame(width: geo.size.width * CGFloat(min(max((value ?? 0) / 5, 0), 1)))
                }
            }
            .frame(height: 8)

            Text(value.map { String(format: "%.1f", $0) } ?? "–")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func reviewRow(_ review: WorkerProfileReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let rating = review.rating {
                    StarRow(value: rating, size: 10)
                }
                if review.topWorker == true { TopWorkerBadge(text: "Top Worker") }
                Text([review.jobTitle, review.createdAt.formatted(date: .abbreviated, time: .omitted)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Text("“\(review.comment)”")
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - About

    private func aboutSection(_ bio: String) -> some View {
        sectionCard("About") {
            Text(bio)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    // MARK: - Availability

    private func availabilitySection(_ w: WorkerProfileInfo) -> some View {
        sectionCard("Availability & Location") {
            VStack(spacing: 0) {
                infoRow(icon: "calendar.badge.clock", label: "Available Days",
                        value: w.availableDays.isEmpty ? "Not specified" : w.availableDays.joined(separator: ", "))
                Divider().padding(.leading, 52)
                infoRow(icon: "clock.fill", label: "Available Times",
                        value: timesText(w.availableTimes))
                Divider().padding(.leading, 52)
                infoRow(icon: "location.circle.fill", label: "Max. Travel Distance",
                        value: w.maxTravelDistance.map { "\($0) mi" } ?? "Not specified")
                Divider().padding(.leading, 52)
                infoRow(icon: "bolt.fill", label: "Same-day Jobs",
                        value: w.availableForSameDay ? "Yes, available" : "No")
                Divider().padding(.leading, 52)
                infoRow(icon: "arrow.left.arrow.right", label: "Works in other cities",
                        value: w.willingToRelocate ? "Yes" : "No")
                if let transport = w.transport, !transport.isEmpty {
                    Divider().padding(.leading, 52)
                    infoRow(icon: "car.fill", label: "Transport", value: transport.capitalized)
                }
            }
        }
    }

    // MARK: - Experience

    private func timesText(_ raw: [String]) -> String {
        let titles = WorkerAvailableTime.allCases.filter { raw.contains($0.rawValue) }.map(\.title)
        return titles.isEmpty ? "Not specified" : titles.joined(separator: ", ")
    }

    private func shiftTypesText(_ raw: [String]) -> String {
        let titles = WorkerShiftType.allCases.filter { raw.contains($0.rawValue) }.map(\.title)
        return titles.isEmpty ? "Not specified" : titles.joined(separator: ", ")
    }

    /// Selbst angegebene Vorerfahrung je Kategorie (Worker-Profil)
    @ViewBuilder
    private func selfDeclaredExperienceSection(_ w: WorkerProfileInfo) -> some View {
        sectionCard("Work Experience") {
            VStack(spacing: 0) {
                if w.experience.isEmpty {
                    Text("No prior experience specified.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(w.experience.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 52) }
                        infoRow(icon: "person.badge.clock.fill", label: item.category, value: item.level.title)
                    }
                }
            }
        }
    }

    private func experienceSection(_ profile: WorkerProfileDTO) -> some View {
        sectionCard("Completed on SwipeShift") {
            VStack(spacing: 0) {
                if profile.stats.completedByCategory.isEmpty {
                    Text("No completed jobs on SwipeShift yet.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(profile.stats.completedByCategory.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 52) }
                        infoRow(icon: "briefcase.fill", label: item.category,
                                value: "\(item.count) job\(item.count == 1 ? "" : "s")")
                    }
                }
            }
        }
    }

    // MARK: - Preferences

    private func preferencesSection(_ w: WorkerProfileInfo) -> some View {
        let categories = w.preferredCategories.isEmpty ? w.jobInterests : w.preferredCategories
        return sectionCard("Job Preferences") {
            VStack(spacing: 0) {
                infoRow(icon: "square.grid.2x2.fill", label: "Preferred Categories",
                        value: categories.isEmpty ? "Not specified" : categories.joined(separator: ", "))
                Divider().padding(.leading, 52)
                infoRow(icon: "calendar", label: "Shift Types", value: shiftTypesText(w.shiftTypes))
                Divider().padding(.leading, 52)
                infoRow(icon: "dollarsign.circle", label: "Hourly Rate", value: payRangeText(w))
            }
        }
    }

    private func payRangeText(_ w: WorkerProfileInfo) -> String {
        switch (w.payRangeMin, w.payRangeMax) {
        case let (min?, max?): return "\(Money.format(min))–\(Money.hourly(max))"
        case let (min?, nil):  return "from \(Money.hourly(min))"
        case let (nil, max?):  return "up to \(Money.hourly(max))"
        default:               return "Not specified"
        }
    }

    // MARK: - Legal

    private func legalSection(_ w: WorkerProfileInfo) -> some View {
        sectionCard("Legal & Compliance") {
            VStack(spacing: 0) {
                legalRow(icon: "checkmark.shield.fill", label: "Work Authorization",
                         ok: w.workAuthorization,
                         value: w.workAuthorization ? "Confirmed by worker" : "Not confirmed")
                Divider().padding(.leading, 52)
                legalRow(icon: "person.text.rectangle", label: "Minimum Age (18+)",
                         ok: w.isAdult == true,
                         value: w.isAdult == true ? "Yes" : (w.isAdult == false ? "Under 18" : "Unknown"))
            }
        }
    }

    private func legalRow(icon: String, label: String, ok: Bool, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(ok ? .green : .orange)
                .frame(width: 28)
                .padding(.leading, 14)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(ok ? .secondary : .orange)
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
                .multilineTextAlignment(.trailing)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - Sterne (volle, halbe, leere)

private struct StarRow: View {
    let value: Double
    let size: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Image(systemName: symbol(for: i))
                    .font(.system(size: size))
                    .foregroundColor(.yellow)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f of 5 stars", value))
    }

    private func symbol(for index: Int) -> String {
        let remaining = value - Double(index)
        if remaining >= 0.75 { return "star.fill" }
        if remaining >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
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
