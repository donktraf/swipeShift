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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
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
                        skeleton
                    } else if let loadError {
                        VStack(spacing: DS.Spacing.sm) {
                            Text(loadError)
                                .dsFont(.callout)
                                .foregroundStyle(DS.Color.text2)
                                .multilineTextAlignment(.center)
                            Button("Try Again") { Task { await load() } }
                                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xl)
                    }

                    Spacer().frame(height: showActions ? 100 : DS.Spacing.xl)
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)
            }
            .refreshable { await load() }

            // Sticky Accept / Decline Footer
            if showActions { actionFooter }
        }
        .dsBackground()
        .navigationBarHidden(true)
        .task { await load() }
        .applicantChatNavigation(chatNavigation)
        .alert("Accept applicant?", isPresented: $showAcceptAlert) {
            Button("Accept") { DS.Haptics.success(); onAccept(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(user?.fullName ?? "This applicant") will be confirmed for the shift.")
        }
        .alert("Decline applicant?", isPresented: $showDeclineAlert) {
            Button("Decline", role: .destructive) { DS.Haptics.warning(); onDecline(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The application from \(user?.fullName ?? "this applicant") will be declined.")
        }
    }

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSSkeletonBlock(height: 90, radius: DS.Radius.card)
            DSSkeletonBlock(height: 160, radius: DS.Radius.card)
            DSSkeletonBlock(height: 160, radius: DS.Radius.card)
        }
        .accessibilityLabel("Loading profile")
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
        VStack(spacing: DS.Spacing.md) {
            HStack {
                DSIconButton(systemName: "chevron.left", label: "Back") { dismiss() }
                Spacer()
            }

            VStack(spacing: DS.Spacing.sm) {
                avatar

                VStack(spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(user?.fullName ?? "Unknown")
                            .dsFont(.title)
                            .foregroundStyle(DS.Color.text)
                        if worker?.isEmailVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(DS.Color.primaryText)
                                .font(.system(size: 16))
                                .accessibilityHidden(true)
                        }
                    }
                    if worker?.isEmailVerified == true {
                        // Bewusst ehrlich: verifiziert ist bisher nur die E-Mail, keine Identitaet
                        Text("Verified email")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.muted)
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
                        }
                        .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                        .padding(.top, DS.Spacing.xxs)
                    }

                    HStack(spacing: DS.Spacing.sm) {
                        if let location = worker?.location ?? user?.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                        }
                        if let age = worker?.age {
                            Label("\(age) years", systemImage: "person.crop.circle")
                        }
                    }
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var avatar: some View {
        ApplicantAvatar(photoUrl: worker?.profilePhotoUrl ?? user?.profilePhotoUrl, size: 88)
    }

    @ViewBuilder
    private func ratingLine(_ stats: WorkerProfileStats) -> some View {
        let jobsText = "\(stats.completedJobs) job\(stats.completedJobs == 1 ? "" : "s") completed"
        if let rating = stats.overallRating {
            HStack(spacing: 3) {
                StarRow(value: rating, size: 12)
                Text(String(format: "%.1f", rating))
                    .font(DS.Font.make(13, .semibold, relativeTo: .caption))
                    .foregroundStyle(DS.Color.text)
                Text("(\(stats.reviewCount) review\(stats.reviewCount == 1 ? "" : "s") · \(jobsText))")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
            }
        } else {
            Text("New on SwipeShift · \(jobsText)")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.text2)
        }
    }

    // MARK: - Job Section (Bewerbung für)

    private func jobSection(_ job: ApplicantJob) -> some View {
        DSSection("Applying For") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Spacing.sm) {
                    DSAvatar(text: job.logoEmoji, size: 48)

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(job.title)
                            .dsFont(.headline)
                            .foregroundStyle(DS.Color.text)
                        HStack(spacing: DS.Spacing.sm) {
                            Label(job.shiftText, systemImage: "calendar")
                            Label(job.payText, systemImage: "banknote")
                        }
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.text2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Spacing.sm)

                // Gebuchte Schichten dieses Bewerbers (aus der Bewerberliste, sonst aus dem Profil-Request mit jobId)
                if let booked = applicant.bookedShifts ?? profile?.bookedShifts, !booked.isEmpty {
                    DSDivider()
                    Label("Shifts: \(booked.summaryLabel)", systemImage: "calendar.badge.checkmark")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DS.Spacing.sm)
                }

                if let hint = profile?.matchHint {
                    DSDivider()
                    Label(hint, systemImage: "sparkles")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DS.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Account-Status

    @ViewBuilder
    private func accountSection(_ profile: WorkerProfileDTO) -> some View {
        if let account = profile.account {
            DSSection("Account") {
                infoRow(icon: "envelope", label: "Email",
                        value: account.emailVerified ? "Verified" : "Not verified")
                if let since = account.memberSince {
                    infoRow(icon: "calendar", label: "Member since",
                            value: since.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
    }

    // MARK: - Reliability

    @ViewBuilder
    private func reliabilitySection(_ profile: WorkerProfileDTO) -> some View {
        if let reliability = profile.reliability {
            DSSection("Reliability") {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ReliabilityLabel(summary: reliability, font: 14)
                    Text(reliability.isNew
                         ? "The show-up rate appears after 3 finished shifts."
                         : "Based on finished shifts in the last 12 months.")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    // MARK: - Past Jobs

    @ViewBuilder
    private func pastJobsSection(_ profile: WorkerProfileDTO) -> some View {
        if let jobs = profile.pastJobs {
            DSSection("Past Jobs") {
                if jobs.isEmpty {
                    emptyNote("No completed jobs on SwipeShift yet.")
                } else {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 { DSDivider() }
                        HStack(alignment: .top, spacing: DS.Spacing.sm) {
                            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                Text(job.jobTitle)
                                    .font(DS.Font.make(15, .semibold, relativeTo: .callout))
                                    .foregroundStyle(DS.Color.text)
                                Text(job.companyName)
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Color.text2)
                                if let date = job.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .dsFont(.caption)
                                        .foregroundStyle(DS.Color.muted)
                                }
                            }
                            Spacer()
                            if let rating = job.rating {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill").foregroundStyle(DS.Color.warning)
                                    Text(String(format: "%.1f", rating)).fontWeight(.semibold)
                                        .foregroundStyle(DS.Color.text)
                                }
                                .font(DS.Font.make(13, .semibold, relativeTo: .caption))
                            } else {
                                Text("Not rated")
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Color.muted)
                            }
                        }
                        .padding(.vertical, DS.Spacing.sm)
                    }
                }
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .dsFont(.callout)
            .foregroundStyle(DS.Color.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Ratings

    private func ratingsSection(_ profile: WorkerProfileDTO) -> some View {
        DSSection("Ratings & Reviews") {
            if let ratings = profile.stats.ratings, profile.stats.reviewCount > 0 {
                ratingRow(label: "Communication",  value: ratings.communication)
                ratingRow(label: "Teamwork",       value: ratings.teamwork)
                ratingRow(label: "Reliability",    value: ratings.reliability)
                ratingRow(label: "Under Pressure", value: ratings.underPressure)
                if ratings.workQuality != nil {
                    ratingRow(label: "Work Quality", value: ratings.workQuality)
                }
                if let top = profile.stats.topWorkerCount, top > 0 {
                    DSDivider()
                    HStack {
                        TopWorkerBadge(text: "Top Worker ×\(top)")
                        Spacer()
                    }
                    .padding(.vertical, DS.Spacing.sm)
                }

                if let rehire = profile.stats.wouldRehirePercent {
                    infoRow(icon: "arrow.triangle.2.circlepath", label: "Would rehire",
                            value: "\(rehire)% of employers")
                }

                ForEach(profile.recentReviews) { review in
                    DSDivider()
                    reviewRow(review)
                }
            } else {
                emptyNote("No reviews from employers yet.")
            }

            // Selbsteinschaetzung aus dem Worker-Profil — klar als solche gekennzeichnet
            if let skills = profile.worker.selfRatedSkills {
                DSDivider()
                Text("SELF-ASSESSED SKILLS")
                    .dsFont(.sectionLabel)
                    .foregroundStyle(DS.Color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Spacing.sm)
                ratingRow(label: "Communication",  value: Double(skills.communication))
                ratingRow(label: "Teamwork",       value: Double(skills.teamwork))
                ratingRow(label: "Reliability",    value: Double(skills.reliability))
                ratingRow(label: "Under Pressure", value: Double(skills.underPressure))
            }
        }
    }

    private func ratingRow(label: String, value: Double?) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(label)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
                .frame(width: 110, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.surface2)
                    Capsule()
                        .fill(DS.Color.primary)
                        .frame(width: geo.size.width * CGFloat(min(max((value ?? 0) / 5, 0), 1)))
                }
            }
            .frame(height: 8)

            Text(value.map { String(format: "%.1f", $0) } ?? "–")
                .font(DS.Font.make(13, .semibold, relativeTo: .caption))
                .foregroundStyle(DS.Color.text)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { String(format: "%.1f of 5", $0) } ?? "no rating")
    }

    private func reviewRow(_ review: WorkerProfileReview) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                if let rating = review.rating {
                    StarRow(value: rating, size: 10)
                }
                if review.topWorker == true { TopWorkerBadge(text: "Top Worker") }
                Text([review.jobTitle, review.createdAt.formatted(date: .abbreviated, time: .omitted)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
            }
            Text("“\(review.comment)”")
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - About

    private func aboutSection(_ bio: String) -> some View {
        DSSection("About") {
            Text(bio)
                .dsFont(.body)
                .foregroundStyle(DS.Color.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Availability

    private func availabilitySection(_ w: WorkerProfileInfo) -> some View {
        DSSection("Availability & Location") {
            infoRow(icon: "calendar.badge.clock", label: "Available Days",
                    value: w.availableDays.isEmpty ? "Not specified" : w.availableDays.joined(separator: ", "))
            infoRow(icon: "clock.fill", label: "Available Times",
                    value: timesText(w.availableTimes))
            infoRow(icon: "location.circle.fill", label: "Max. Travel Distance",
                    value: w.maxTravelDistance.map { "\($0) mi" } ?? "Not specified")
            infoRow(icon: "bolt.fill", label: "Same-day Jobs",
                    value: w.availableForSameDay ? "Yes, available" : "No")
            infoRow(icon: "arrow.left.arrow.right", label: "Works in other cities",
                    value: w.willingToRelocate ? "Yes" : "No")
            if let transport = w.transport, !transport.isEmpty {
                infoRow(icon: "car.fill", label: "Transport", value: transport.capitalized)
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
        DSSection("Work Experience") {
            if w.experience.isEmpty {
                emptyNote("No prior experience specified.")
            } else {
                ForEach(w.experience) { item in
                    infoRow(icon: "person.badge.clock.fill", label: item.category, value: item.level.title)
                }
            }
        }
    }

    private func experienceSection(_ profile: WorkerProfileDTO) -> some View {
        DSSection("Completed on SwipeShift") {
            if profile.stats.completedByCategory.isEmpty {
                emptyNote("No completed jobs on SwipeShift yet.")
            } else {
                ForEach(profile.stats.completedByCategory) { item in
                    infoRow(icon: "briefcase.fill", label: item.category,
                            value: "\(item.count) job\(item.count == 1 ? "" : "s")")
                }
            }
        }
    }

    // MARK: - Preferences

    private func preferencesSection(_ w: WorkerProfileInfo) -> some View {
        let categories = w.preferredCategories.isEmpty ? w.jobInterests : w.preferredCategories
        return DSSection("Job Preferences") {
            infoRow(icon: "square.grid.2x2.fill", label: "Preferred Categories",
                    value: categories.isEmpty ? "Not specified" : categories.joined(separator: ", "))
            infoRow(icon: "calendar", label: "Shift Types", value: shiftTypesText(w.shiftTypes))
            infoRow(icon: "dollarsign.circle", label: "Hourly Rate", value: payRangeText(w))
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
        DSSection("Legal & Compliance") {
            legalRow(icon: "checkmark.shield.fill", label: "Work Authorization",
                     ok: w.workAuthorization,
                     value: w.workAuthorization ? "Confirmed by worker" : "Not confirmed")
            legalRow(icon: "person.text.rectangle", label: "Minimum Age (18+)",
                     ok: w.isAdult == true,
                     value: w.isAdult == true ? "Yes" : (w.isAdult == false ? "Under 18" : "Unknown"))
        }
    }

    private func legalRow(icon: String, label: String, ok: Bool, value: String) -> some View {
        DSRow(label, systemIcon: icon, iconTone: ok ? .success : .warning) {
            Text(value)
                .dsFont(.caption)
                .foregroundStyle(ok ? DS.Color.text2 : DS.Color.warning)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Action Footer

    private var actionFooter: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button { showDeclineAlert = true } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.ds(.destructiveSoft))

            Button { showAcceptAlert = true } label: {
                Label("Accept", systemImage: "checkmark")
            }
            .buttonStyle(.ds(.primary))
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .background(DS.Color.bg.opacity(0.96))
        .overlay(alignment: .top) { DSDivider() }
    }

    // MARK: - Shared Helpers

    private func infoRow(icon: String, label: String, value: String) -> some View {
        DSRow(label, value: value, systemIcon: icon)
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
                    .foregroundStyle(DS.Color.warning)
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
