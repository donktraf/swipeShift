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
    let workerPhoto: String?
    let bio:         String?
    let jobInterests: [String]
    let applyStatus: String
    let jobId:       String
    let jobTitle:    String
    let company:     String
    let logoEmoji:   String
    let location:    String
    let shiftDate:   Date?
    let payText:     String

    var id: String { savedId }
}

// MARK: - SavedApplicantsView

struct SavedApplicantsView: View {
    @State private var saved: [SavedApplicantItem] = []
    @State private var isLoading = false

    var body: some View {
        SubScreenShell(title: "Saved Applicants") {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView().tint(.white).padding(.top, 40)
                } else if saved.isEmpty {
                    emptyState
                } else {
                    savedList
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            saved = try await APIClient.shared.fetchSavedApplicants()
        } catch { }
        isLoading = false
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

    private func unsave(_ item: SavedApplicantItem) async {
        do {
            try await APIClient.shared.unsaveApplicant(applyId: item.applyId)
            saved.removeAll { $0.savedId == item.savedId }
        } catch { }
    }
}

// MARK: - Card

private struct SavedApplicantCard: View {
    let item: SavedApplicantItem
    let onUnsave: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle().fill(SS.primary.opacity(0.15)).frame(width: 48, height: 48)
                Text(String(item.workerName.prefix(1)))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(SS.primary)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.workerName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text("\(item.logoEmoji) \(item.jobTitle) at \(item.company)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if !item.jobInterests.isEmpty {
                    Text(item.jobInterests.prefix(3).joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            // Unsave button
            Button {
                Task { await onUnsave() }
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18))
                    .foregroundColor(SS.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
