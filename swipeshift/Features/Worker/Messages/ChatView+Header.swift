//
//  ChatView+Header.swift
//  swipeShift
//
//  Header, "..."-Menue (Melden/Blockieren/Support/Worker-Profil), Abschluss-Bereich.
//

import SwiftUI

extension ChatView {

    // MARK: - Header
    var chatHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // Avatar: Employer → Worker-Foto; Worker → Firmenlogo (tippbar → Company Profile)
            if isEmployerMode {
                ChatAvatar(photoUrl: live.counterpartPhotoUrl, emoji: conversation.logoEmoji)
            } else {
                NavigationLink {
                    CompanyProfileView(
                        companyName: conversation.company,
                        logoEmoji:   conversation.logoEmoji
                    )
                } label: {
                    ChatAvatar(photoUrl: live.counterpartPhotoUrl, emoji: conversation.logoEmoji)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // `company` wird serverseitig je nach Rolle bereits mit dem richtigen
                    // Anzeigenamen befuellt (Worker: Firma; Employer: Worker-Name).
                    Text(conversation.company)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    StatusBadge(status: conversation.status)
                }
                Text(conversation.jobTitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(live.shiftSummary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !isReadOnly && !live.isBlocked {
                    PresenceLine(presence: presence)
                }
            }

            Spacer()

            optionsMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - "..."-Menue (kontextuell)
    private var optionsMenu: some View {
        Menu {
            Button { openJobDetails() } label: { Label("Job details", systemImage: "info.circle") }

            if isEmployerMode, live.counterpartUserId != nil {
                Button { showWorkerProfile = true } label: {
                    Label("View worker profile", systemImage: "person.crop.circle")
                }
            }

            if live.counterpartUserId != nil {
                Divider()
                Button { showReportSheet = true } label: {
                    Label("Report \(conversation.company)", systemImage: "exclamationmark.bubble")
                }
                // Hat die Gegenseite uns blockiert, gibt es nichts zu (ent)blockieren
                if live.blockedByMe {
                    Button { showBlockConfirm = true } label: { Label("Unblock", systemImage: "hand.raised.slash") }
                } else {
                    Button(role: .destructive) { showBlockConfirm = true } label: {
                        Label("Block \(conversation.company)", systemImage: "hand.raised")
                    }
                }
            }

            Divider()
            Button { contactSupport() } label: { Label("Contact support", systemImage: "lifepreserver") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22))
                .foregroundColor(SS.primary)
                .frame(width: 32, height: 32)
        }
    }

    // MARK: - Hinweise
    var safetyNotice: some View {
        Label(ChatSafety.safetyNotice, systemImage: "lock.shield")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
    }

    var blockedBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill").foregroundColor(.orange)
                Text(live.blockedByMe ? "You blocked this user." : "You can't reply to this conversation.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                if live.blockedByMe {
                    Button("Unblock") { showBlockConfirm = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SS.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
            .padding(.bottom, 20)
        }
    }

    // MARK: - Abschluss: Zahlungsstatus + Save
    var completionSection: some View {
        let paidText: String = {
            if live.isPaid { return isEmployerMode ? "Paid – you've paid this worker." : "Paid – the employer released your payment." }
            return isEmployerMode ? "Payment pending – this worker hasn't been paid yet." : "Payment pending – the employer hasn't released payment yet."
        }()
        let saveTitle: String = {
            if isEmployerMode { return live.isCounterpartSaved ? "Worker saved" : "Save worker" }
            return live.isCounterpartSaved ? "Company saved" : "Save company"
        }()

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: live.isPaid ? "checkmark.seal.fill" : "clock.fill")
                    .foregroundColor(live.isPaid ? .green : .orange)
                Text(paidText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            HStack {
                Button { Task { await toggleSaved() } } label: {
                    Label(saveTitle, systemImage: live.isCounterpartSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SS.primary)
                }
                .disabled(isBusy)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Ziel: Worker-Profil (Employer)
    @ViewBuilder
    var workerProfileDestination: some View {
        if let userId = live.counterpartUserId {
            DetailedWorkerView(
                applicant: Applicant(
                    applyId:   conversation.applyId,
                    userId:    userId,
                    appliedAt: nil,
                    status:    "accepted",
                    job: ApplicantJob(
                        id: conversation.jobId, title: conversation.jobTitle,
                        payText: live.payDisplay, shiftText: live.shiftSummary,
                        location: live.location, logoEmoji: conversation.logoEmoji
                    ),
                    user: ApplicantUser(
                        id: userId, firstName: conversation.company, lastName: nil,
                        location: nil, profilePhotoUrl: live.counterpartPhotoUrl
                    )
                ),
                onAccept: {}, onDecline: {},
                showActions: false
            )
        }
    }

    // MARK: - Aktionen
    func openJobDetails() {
        guard !loadingJobDetail else { return }
        loadingJobDetail = true
        Task {
            do {
                jobDetailJob = try await APIClient.shared.fetchJob(jobId: conversation.jobId)
            } catch {
                actionError = error.localizedDescription
            }
            loadingJobDetail = false
        }
    }

    func contactSupport() {
        guard let url = ChatSafety.supportURL(for: live) else {
            showSupportFallback = true
            return
        }
        openURL(url) { accepted in
            if !accepted { showSupportFallback = true }
        }
    }

    @MainActor
    func toggleBlock() async {
        guard let userId = live.counterpartUserId, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if live.blockedByMe {
                try await APIClient.shared.unblockUser(userId: userId)
                messageStore.applyBlockFlags(conversationId: conversation.id, byMe: false, byOther: live.blockedByOther)
            } else {
                try await APIClient.shared.blockUser(userId: userId)
                messageStore.userStoppedTyping(conversationId: conversation.id)
                messageStore.applyBlockFlags(conversationId: conversation.id, byMe: true, byOther: live.blockedByOther)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Worker → Firma merken (SavedCompany); Employer → Worker merken (SavedApplicant)
    @MainActor
    func toggleSaved() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let target = !live.isCounterpartSaved
        do {
            if isEmployerMode {
                if target {
                    try await APIClient.shared.saveApplicant(applyId: conversation.applyId)
                } else {
                    try await APIClient.shared.unsaveApplicant(applyId: conversation.applyId)
                }
            } else {
                if target {
                    try await APIClient.shared.saveCompany(name: conversation.company)
                } else {
                    try await APIClient.shared.unsaveCompany(name: conversation.company)
                }
            }
            messageStore.setCounterpartSaved(conversationId: conversation.id, saved: target)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
