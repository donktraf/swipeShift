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
        SubScreenShell(title: "Blocked users", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                content
                if !isLoading, loadError == nil {
                    Text("Blocking hides your jobs and profile activity from each other: you won't see each other's jobs, can't apply to each other's jobs, and can't send messages in existing chats (you can still read them). Unblocking restores all of this.")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
                if let actionError {
                    Text(actionError)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.danger)
                }
            }
        }
        .refreshable { await load() }
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
        if isLoading && blocked.isEmpty {
            VStack(spacing: DS.Spacing.xs) {
                DSSkeletonBlock(height: 56, radius: DS.Radius.control)
                DSSkeletonBlock(height: 56, radius: DS.Radius.control)
            }
            .accessibilityLabel("Loading blocked users")
        } else if let loadError {
            VStack(spacing: DS.Spacing.sm) {
                Text(loadError).dsFont(.callout).foregroundStyle(DS.Color.danger).multilineTextAlignment(.center)
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xl)
        } else if blocked.isEmpty {
            DSEmptyState(systemIcon: "hand.raised.slash", title: "You haven't blocked anyone.",
                         message: "People you block will show up here.")
        } else {
            DSSection("Blocked") {
                ForEach(blocked) { user in
                    row(user)
                }
            }
        }
    }

    private func row(_ user: BlockedUser) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ChatAvatar(photoUrl: user.photoUrl, emoji: user.initial, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).dsFont(.body).foregroundStyle(DS.Color.text).lineLimit(1)
                Text("\(user.roleLabel) · Blocked on \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            if unblockingId == user.id {
                ProgressView()
            } else {
                Button("Unblock") { pendingUnblock = user }
                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(minHeight: 44)
                    .disabled(unblockingId != nil)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { DSDivider() }
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
