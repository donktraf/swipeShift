//
//  SavedApplicantsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - DTO

struct SavedApplicantItem: Identifiable, Decodable {
    let savedId:     String
    let applyId:     String
    let savedAt:     Date
    let workerName:  String
    let userId:      String
    let workerPhoto: String?
    let workerCity:  String?
    let bio:         String?
    /// Graphem-sicher gekuerzt (Backend: truncateText)
    let bioShort:    String?
    let jobInterests: [String]
    let summary:     ApplicantSummary?
    let conversationId: String?
    let applyStatus: String
    let jobId:       String
    let jobTitle:    String
    let company:     String
    let logoEmoji:   String
    let location:    String
    let shiftDate:   Date?
    let payText:     String

    var id: String { savedId }

    /// Fuer DetailedWorkerView (ohne Accept/Decline, nur Profilansicht)
    var asApplicant: Applicant {
        Applicant(
            applyId: applyId, userId: userId, appliedAt: nil, status: applyStatus,
            job: ApplicantJob(
                id: jobId, title: jobTitle, payText: payText,
                shiftText: shiftDate?.formatted(.dateTime.day().month(.abbreviated).hour().minute()) ?? "",
                location: location, logoEmoji: logoEmoji
            ),
            user: ApplicantUser(
                id: userId,
                firstName: workerName, lastName: nil,
                location: workerCity, profilePhotoUrl: workerPhoto
            ),
            summary: summary, conversationId: conversationId
        )
    }
}

// MARK: - SavedApplicantsView

struct SavedApplicantsView: View {
    @State private var saved: [SavedApplicantItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var unsaveError: String?

    var body: some View {
        SubScreenShell(title: "Saved Applicants") {
            VStack(spacing: 0) {
                if isLoading && saved.isEmpty {
                    ProgressView().tint(.white).padding(.top, 40)
                } else if let errorMessage, saved.isEmpty {
                    errorView(errorMessage)
                } else if saved.isEmpty {
                    emptyState
                } else {
                    savedList
                }
            }
        }
        .task { await load() }
        .alert("Something went wrong", isPresented: Binding(
            get: { unsaveError != nil },
            set: { if !$0 { unsaveError = nil } }
        )) {
            Button("OK", role: .cancel) { unsaveError = nil }
        } message: {
            Text(unsaveError ?? "")
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            saved = try await APIClient.shared.fetchSavedApplicants()
        } catch {
            errorMessage = "Saved applicants could not be loaded. Check your connection and try again."
        }
        isLoading = false
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange.opacity(0.7))
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(SSPrimaryButtonStyle())
                .padding(.horizontal, 60)
        }
        .padding(.top, 40).padding(.horizontal, 24)
    }

    private var savedList: some View {
        VStack(spacing: 12) {
            ForEach(saved) { item in
                SavedApplicantCard(item: item) {
                    await unsave(item)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.3))
            Text("No saved applicants")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Bookmark applicants from the Applicants screen to find them here.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @MainActor
    private func unsave(_ item: SavedApplicantItem) async {
        do {
            try await APIClient.shared.unsaveApplicant(applyId: item.applyId)
            saved.removeAll { $0.savedId == item.savedId }
        } catch {
            unsaveError = "The applicant could not be removed. Please try again."
        }
    }
}
