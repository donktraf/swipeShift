//
//  AllApplicantsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Models

struct ApplicantUser: Decodable {
    let id: String
    let firstName: String?
    let lastName:  String?
    let location:  String?
    let profilePhotoUrl: String?

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ").isEmpty
            ? "Unknown"
            : [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

struct ApplicantJob: Decodable {
    let id: String
    let title: String
    let payText: String
    let shiftText: String
    let location: String
    let logoEmoji: String
    /// Schichtbeginn (fuer "Available for this shift"); fehlt z.B. bei aus dem Kalender gebauten Jobs
    var startTime: Date? = nil
}

struct Applicant: Identifiable, Decodable {
    let applyId:   String
    let userId:    String
    let appliedAt: Date?
    let status:    String
    let job:       ApplicantJob?
    let user:      ApplicantUser?
    /// Kurzprofil (Bewertung, Jobs, Tags, 18+, Verfuegbarkeit); fehlt z.B. beim Oeffnen aus dem Chat
    var summary:   ApplicantSummary? = nil
    /// Conversation der Bewerbung (Chat-Button erst nach Annahme)
    var conversationId: String? = nil
    /// Instant Match: automatisch angenommen (fehlt in aelteren Payloads)
    var autoAccepted: Bool? = nil
    /// Worker hat zur selben Zeit einen anderen angenommenen Job (Backend)
    var hasScheduleConflict: Bool? = nil
    /// Vom Worker gebuchte Schichten (leer/fehlt bei aelteren Backends)
    var bookedShifts: [BookedShift]? = nil

    var id: String { applyId }
}

// MARK: - AllApplicantsView

struct AllApplicantsView: View {
    /// Optional: nur Bewerber dieses Jobs anzeigen (Schnellaktion auf der Jobkarte)
    var jobId: String? = nil
    var jobTitle: String? = nil

    @State private var applicants: [Applicant] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // accepted/declined: beim Laden aus dem Backend-Status, danach sofort lokal aktualisiert
    @State private var localStates: [String: ApplicantLocalState] = [:]
    @StateObject private var chatNavigation = ApplicantChatNavigation()
    @EnvironmentObject private var messageStore: MessageStore

    enum ApplicantLocalState { case accepted, declined }

    private var pending:  [Applicant] { applicants.filter { localStates[$0.applyId] == nil } }
    private var accepted: [Applicant] { applicants.filter { localStates[$0.applyId] == .accepted } }
    private var declined: [Applicant] { applicants.filter { localStates[$0.applyId] == .declined } }

    @State private var selectedFilter: ApplicantFilter = .all

    enum ApplicantFilter: String, CaseIterable {
        case all      = "All"
        case pending  = "Pending"
        case accepted = "Accepted"
        case declined = "Declined"
    }

    private var filtered: [Applicant] {
        switch selectedFilter {
        case .all:      return applicants
        case .pending:  return pending
        case .accepted: return accepted
        case .declined: return declined
        }
    }

    var body: some View {
        SubScreenShell(title: jobTitle ?? "All Applicants", padded: true) {
            VStack(spacing: DS.Spacing.md) {
                // Filter-Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(ApplicantFilter.allCases, id: \.self) { filter in
                            filterChip(filter)
                        }
                    }
                }
        .contentMargins(.horizontal, DS.Spacing.screenEdge, for: .scrollContent)
        .padding(.horizontal, -DS.Spacing.screenEdge)

                if isLoading && applicants.isEmpty {
                    skeleton
                } else if let err = errorMessage {
                    errorView(err)
                } else if filtered.isEmpty {
                    emptyView
                } else {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(filtered) { applicant in
                            NavigationLink {
                                DetailedWorkerView(
                                    applicant: applicant,
                                    onAccept: { Task { await accept(applicant) } },
                                    onDecline: { Task { await decline(applicant) } },
                                    jobId: applicant.job?.id,
                                    chatConversationId: chatId(for: applicant)
                                )
                            } label: {
                                ApplicantCard(
                                    applicant: applicant,
                                    localState: localStates[applicant.applyId],
                                    onAccept: { Task { await accept(applicant) } },
                                    onDecline: { Task { await decline(applicant) } },
                                    onSave: { Task { await saveApplicant(applicant) } },
                                    onChat: chatId(for: applicant).map { id in
                                        { chatNavigation.openChat(conversationId: id, messageStore: messageStore) }
                                    }
                                )
                            }
                            .buttonStyle(.dsPressable)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .applicantChatNavigation(chatNavigation)
    }

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                DSSkeletonBlock(height: 190, radius: DS.Radius.card)
            }
        }
        .accessibilityLabel("Loading applicants")
    }

    /// Chat nur bei angenommener Bewerbung (Backend oder gerade lokal angenommen) mit Conversation
    private func chatId(for applicant: Applicant) -> String? {
        localStates[applicant.applyId] == .accepted ? applicant.conversationId : nil
    }

    // MARK: - Filter Chip

    private func filterChip(_ filter: ApplicantFilter) -> some View {
        let count: Int = {
            switch filter {
            case .all:      return applicants.count
            case .pending:  return pending.count
            case .accepted: return accepted.count
            case .declined: return declined.count
            }
        }()

        return DSChip(count > 0 ? "\(filter.rawValue) \(count)" : filter.rawValue,
                      isSelected: selectedFilter == filter) {
            selectedFilter = filter
        }
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        DSEmptyState(
            systemIcon: "person.2.slash",
            title: "No Applicants",
            message: "Once someone applies for your jobs, they will appear here."
        )
        .padding(.top, DS.Spacing.xl)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(DS.Color.warning)
            Text(msg)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text2)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .padding(.top, DS.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await APIClient.shared.fetchApplicants(jobId: jobId)
            // "New Matches" zuruecksetzen (nur mit Job-Kontext; Fehler hier sind unkritisch)
            if let jobId { try? await APIClient.shared.markApplicantsSeen(jobId: jobId) }
            applicants = jobId.map { id in all.filter { $0.job?.id == id } } ?? all
            localStates = Dictionary(uniqueKeysWithValues: applicants.compactMap { a in
                switch a.status {
                case "accepted": return (a.applyId, ApplicantLocalState.accepted)
                case "declined": return (a.applyId, ApplicantLocalState.declined)
                default:         return nil
                }
            })
        }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func accept(_ applicant: Applicant) async {
        do {
            try await APIClient.shared.acceptApplicant(applyId: applicant.applyId)
            DS.Haptics.success()
            withAnimation { localStates[applicant.applyId] = .accepted }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func decline(_ applicant: Applicant) async {
        do {
            try await APIClient.shared.declineApplicant(applyId: applicant.applyId)
            DS.Haptics.warning()
            withAnimation { localStates[applicant.applyId] = .declined }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveApplicant(_ applicant: Applicant) async {
        do { try await APIClient.shared.saveApplicant(applyId: applicant.applyId) }
        catch { }
    }
}
