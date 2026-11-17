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
}

struct Applicant: Identifiable, Decodable {
    let applyId:   String
    let userId:    String
    let appliedAt: String
    let status:    String
    let job:       ApplicantJob?
    let user:      ApplicantUser?

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

    // Lokaler accepted/declined-State (MVP: nicht persistent bis Backend-Modell erweitert)
    @State private var localStates: [String: ApplicantLocalState] = [:]

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
        SubScreenShell(title: jobTitle ?? "All Applicants") {
            VStack(spacing: 16) {
                // Filter-Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ApplicantFilter.allCases, id: \.self) { filter in
                            filterChip(filter)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if isLoading {
                    ProgressView()
                        .foregroundColor(.white)
                        .padding(.top, 60)

                } else if let err = errorMessage {
                    errorView(err)

                } else if filtered.isEmpty {
                    emptyView

                } else {
                    VStack(spacing: 10) {
                        ForEach(filtered) { applicant in
                            NavigationLink {
                                DetailedWorkerView(
                                    applicant: applicant,
                                    onAccept: { Task { await accept(applicant) } },
                                    onDecline: { Task { await decline(applicant) } }
                                )
                            } label: {
                                ApplicantCard(
                                    applicant: applicant,
                                    localState: localStates[applicant.applyId],
                                    onAccept: { Task { await accept(applicant) } },
                                    onDecline: { Task { await decline(applicant) } },
                                    onSave: { Task { await saveApplicant(applicant) } }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
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

        return Button { selectedFilter = filter } label: {
            HStack(spacing: 4) {
                Text(filter.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(selectedFilter == filter ? Color.white.opacity(0.3) : SS.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(selectedFilter == filter ? .white : .secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selectedFilter == filter ? SS.primary : Color(uiColor: .systemBackground))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selectedFilter)
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.3))
            Text("No Applicants")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Once someone applies for your jobs, they will appear here.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange.opacity(0.7))
            Text(msg)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(SSPrimaryButtonStyle())
                .padding(.horizontal, 60)
        }
        .padding(.top, 40).padding(.horizontal, 24)
    }

    // MARK: - Actions

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await APIClient.shared.fetchApplicants()
            applicants = jobId.map { id in all.filter { $0.job?.id == id } } ?? all
        }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func accept(_ applicant: Applicant) async {
        do {
            try await APIClient.shared.acceptApplicant(applyId: applicant.applyId)
            withAnimation { localStates[applicant.applyId] = .accepted }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func decline(_ applicant: Applicant) async {
        do {
            try await APIClient.shared.declineApplicant(applyId: applicant.applyId)
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

// MARK: - ApplicantCard

private struct ApplicantCard: View {
    let applicant:  Applicant
    let localState: AllApplicantsView.ApplicantLocalState?
    let onAccept:   () -> Void
    let onDecline:  () -> Void
    var onSave:     (() -> Void)? = nil

    private var isDecided: Bool { localState != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Worker-Info
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 48, height: 48)
                    if let urlStr = applicant.user?.profilePhotoUrl,
                       let url = URL(string: urlStr) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(applicant.user?.fullName ?? "Unknown")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        stateBadge
                        if let onSave {
                            Button(action: onSave) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 16))
                                    .foregroundColor(SS.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let location = applicant.user?.location {
                        Label(location, systemImage: "mappin")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            // Job-Info
            if let job = applicant.job {
                HStack(spacing: 10) {
                    Text(job.logoEmoji)
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        HStack(spacing: 8) {
                            Label(job.shiftText, systemImage: "calendar")
                            Label(job.payText,   systemImage: "banknote")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 14)
            }

            // Accept / Decline Buttons
            if !isDecided {
                HStack(spacing: 8) {
                    Button(action: onDecline) {
                        Label("Decline", systemImage: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: onAccept) {
                        Label("Accept", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(SS.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isDecided ? 0.03 : 0.05), radius: 5, x: 0, y: 2)
        .opacity(isDecided ? 0.65 : 1)
        .animation(.easeInOut(duration: 0.25), value: isDecided)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch localState {
        case .accepted:
            Text("Accepted")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.green)
                .clipShape(Capsule())
        case .declined:
            Text("Declined")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.red)
                .clipShape(Capsule())
        case nil:
            Text("Pending")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SS.primary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(SS.primary.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}
