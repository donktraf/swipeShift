import SwiftUI

// Liste der blockierten Nutzer (Worker + Employer) mit Unblock
struct BlockedUser: Identifiable, Decodable, Equatable {
    let userId: String
    let name: String
    let role: String
    let photoUrl: String?
    let createdAt: Date

    var id: String { userId }
    var isEmployer: Bool { role == "employer" }
    var roleLabel: String { isEmployer ? "Employer" : "Worker" }
    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}

struct BlockedUsersView: View {
    @State private var blocked: [BlockedUser] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var pendingUnblock: BlockedUser?
    @State private var unblockingId: String?
    @State private var actionError: String?

    var body: some View {
        SubScreenShell(title: "Blocked users") {
            VStack(spacing: 16) {
                content
                if !isLoading, loadError == nil {
                    Text("Blocking hides your jobs and profile activity from each other: you won't see each other's jobs, can't apply to each other's jobs, and can't send messages in existing chats (you can still read them). Unblocking restores all of this.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                if let actionError {
                    Text(actionError)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
        }
        .task { await load() }
        .confirmationDialog(
            pendingUnblock.map { "Unblock \($0.name)?" } ?? "Unblock?",
            isPresented: Binding(get: { pendingUnblock != nil }, set: { if !$0 { pendingUnblock = nil } }),
            titleVisibility: .visible,
            presenting: pendingUnblock
        ) { user in
            Button("Unblock") { Task { await unblock(user) } }
            Button("Cancel", role: .cancel) {}
        } message: { user in
            Text("You'll see each other's jobs again, can apply to each other's jobs, and can message each other again in existing chats.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let loadError {
            VStack(spacing: 10) {
                Text(loadError).font(.system(size: 13)).foregroundColor(.red).multilineTextAlignment(.center)
                Button("Try again") { Task { await load() } }
                    .buttonStyle(SSPrimaryButtonStyle())
            }
            .padding(.vertical, 24)
        } else if blocked.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "hand.raised.slash")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("You haven't blocked anyone.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(blocked.enumerated()), id: \.element.id) { index, user in
                    if index > 0 { Divider().padding(.leading, 64) }
                    row(user)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }

    private func row(_ user: BlockedUser) -> some View {
        HStack(spacing: 12) {
            ChatAvatar(photoUrl: user.photoUrl, emoji: user.initial, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text("\(user.roleLabel) · Blocked on \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if unblockingId == user.id {
                ProgressView()
            } else {
                Button("Unblock") { pendingUnblock = user }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .disabled(unblockingId != nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        do {
            blocked = try await APIClient.shared.fetchBlockedUsers()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func unblock(_ user: BlockedUser) async {
        unblockingId = user.id
        actionError = nil
        do {
            try await APIClient.shared.unblockUser(userId: user.userId)
            blocked.removeAll { $0.userId == user.userId }
        } catch {
            actionError = error.localizedDescription
        }
        unblockingId = nil
    }
}
