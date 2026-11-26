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
        SubScreenShell(title: "Saved Applicants", padded: true) {
            VStack(spacing: 0) {
                if isLoading && saved.isEmpty {
                    skeleton
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
        .refreshable { await load() }
        .alert("Something went wrong", isPresented: Binding(
            get: { unsaveError != nil },
            set: { if !$0 { unsaveError = nil } }
        )) {
            Button("OK", role: .cancel) { unsaveError = nil }
        } message: {
            Text(unsaveError ?? "")
        }
    }

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                DSSkeletonBlock(height: 170, radius: DS.Radius.card)
            }
        }
        .accessibilityLabel("Loading saved applicants")
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
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(DS.Color.warning)
            Text(message)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text2)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .padding(.top, DS.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    private var savedList: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(saved) { item in
                SavedApplicantCard(item: item) {
                    await unsave(item)
                }
            }
        }
    }

    private var emptyState: some View {
        DSEmptyState(
            systemIcon: "bookmark.slash",
            title: "No saved applicants",
            message: "Bookmark applicants from the Applicants screen to find them here."
        )
        .padding(.top, DS.Spacing.xl)
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
