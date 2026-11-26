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
        HStack(spacing: DS.Spacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(DS.Font.make(17, .semibold))
                    .foregroundStyle(DS.Color.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPressable)
            .accessibilityLabel("Back")

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
                .buttonStyle(.dsPressable)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.xs) {
                    // `company` wird serverseitig je nach Rolle bereits mit dem richtigen
                    // Anzeigenamen befuellt (Worker: Firma; Employer: Worker-Name).
                    Text(conversation.company)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                    StatusBadge(status: conversation.status)
                }
                Text(conversation.jobTitle)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
                    .lineLimit(1)
                Text(live.shiftSummary)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
                    .lineLimit(1)
                if !isReadOnly && !live.isBlocked {
                    PresenceLine(presence: presence)
                }
            }

            Spacer()

            optionsMenu
        }
        .padding(.leading, DS.Spacing.xs)
        .padding(.trailing, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.bg)
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
                .foregroundStyle(DS.Color.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: - Hinweise
    var safetyNotice: some View {
        Label(ChatSafety.safetyNotice, systemImage: "lock.shield")
            .dsFont(.caption)
            .foregroundStyle(DS.Color.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom, DS.Spacing.xs)
    }

    var blockedBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(DS.Tone.warning.foreground)
                .accessibilityHidden(true)
            Text(live.blockedByMe ? "You blocked this user." : "You can't reply to this conversation.")
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
            Spacer(minLength: DS.Spacing.xs)
            if live.blockedByMe {
                Button("Unblock") { showBlockConfirm = true }
                    .font(DS.Font.make(14, .bold))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(minHeight: 44)
                    .buttonStyle(.dsPressable)
            }
        }
        .padding(DS.Spacing.inset)
        .background(DS.Tone.warning.soft, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.bg)
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

        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: live.isPaid ? "checkmark.seal.fill" : "clock.fill")
                    .foregroundStyle(live.isPaid ? DS.Tone.success.foreground : DS.Tone.warning.foreground)
                    .accessibilityHidden(true)
                Text(paidText)
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text)
                Spacer(minLength: 0)
            }
            Button { Task { await toggleSaved() } } label: {
                Label(saveTitle, systemImage: live.isCounterpartSaved ? "bookmark.fill" : "bookmark")
                    .font(DS.Font.make(14, .bold))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.dsPressable)
            .disabled(isBusy)
        }
        .padding(DS.Spacing.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: 1)
        )
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
                jobId: conversation.jobId,
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
