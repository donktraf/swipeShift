//
//  ApplicantSummary.swift
//  swipeShift
//
//  Gemeinsame Kurzzusammenfassung eines Bewerbers/Workers (Backend: utils/applicantSummary.js),
//  genutzt von Bewerberkarte, gemerkten Bewerbern und Arbeitgeber-Kalender, plus kleine
//  wiederverwendbare Teil-Views (Bewertung, Tags, 18+-Badge, Chat-Navigation).
//

import SwiftUI
import Combine

// MARK: - DTO

struct ApplicantSummary: Decodable, Equatable {
    let ratingAverage: Double?
    let reviewCount: Int
    let completedJobs: Int
    let tags: [String]
    let strongestExperience: String?
    /// Nur das Badge, das Alter selbst wird nicht ausgeliefert
    let isAdult: Bool
    let availabilityText: String?
    /// Rohwerte fuer "Available for this shift" (fehlen in aelteren Payloads)
    var availableDays: [String]? = nil
    var availableTimes: [String]? = nil
    /// Anwesenheit / No-Shows / kurzfristige Stornos (fehlt in aelteren Payloads)
    var reliability: ReliabilitySummary? = nil
}

// MARK: - Formatierung

enum ApplicantFormat {
    /// "Applied 2h ago" / "Applied 3d ago" / "Applied just now"
    static func appliedAgo(_ date: Date, now: Date = .now) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60:        return "Applied just now"
        case ..<3_600:     return "Applied \(Int(seconds / 60))m ago"
        case ..<86_400:    return "Applied \(Int(seconds / 3_600))h ago"
        default:           return "Applied \(Int(seconds / 86_400))d ago"
        }
    }

    static func jobsText(_ count: Int) -> String {
        "\(count) job\(count == 1 ? "" : "s") completed"
    }
}

// MARK: - Bewertung

/// "★ 4.6 (12)" bzw. "New" wenn noch keine Bewertung vorliegt
struct ApplicantRatingLabel: View {
    let average: Double?
    let count: Int

    var body: some View {
        if let average {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").foregroundStyle(DS.Color.warning)
                Text(String(format: "%.1f", average)).fontWeight(.semibold).foregroundStyle(DS.Color.text)
                Text("(\(count))").foregroundStyle(DS.Color.muted)
            }
            .font(DS.Font.make(12, .medium, relativeTo: .caption))
            .accessibilityElement(children: .combine)
        } else {
            DSBadge("New", .tone(.primary))
        }
    }
}

struct AdultBadge: View {
    var body: some View {
        DSBadge("18+", .tone(.success))
    }
}

struct ApplicantTagRow: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(DS.Font.make(11, .semibold, relativeTo: .caption))
                        .foregroundStyle(DS.Color.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, DS.Spacing.xs).padding(.vertical, 3)
                        .background(DS.Color.primarySoft, in: Capsule())
                }
            }
        }
    }
}

/// Runder Worker-Avatar mit Foto oder Platzhalter
struct ApplicantAvatar: View {
    let photoUrl: String?
    var size: CGFloat = 48
    /// Ohne Foto: Initialen statt Platzhalter-Icon (optional)
    var initials: String? = nil

    var body: some View {
        ZStack {
            if let photoUrl, let url = URL(string: photoUrl) {
                Circle().fill(DS.Color.surface2).frame(width: size, height: size)
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.fill").foregroundStyle(DS.Color.muted)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else if let initials, !initials.isEmpty {
                DSAvatar(text: initials, size: size, shape: .circle, tone: .neutral)
            } else {
                Circle().fill(DS.Color.surface2).frame(width: size, height: size)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(DS.Color.muted)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chat-Navigation (Arbeitgeber)

/// Oeffnet den Chat zu einer Bewerbung wie im Arbeitgeber-Messages-Tab
/// (ChatView mit isEmployerMode). Conversation wird bei Bedarf nachgeladen.
@MainActor
final class ApplicantChatNavigation: ObservableObject {
    @Published var conversation: Conversation?
    @Published var errorMessage: String?

    func openChat(conversationId: String, messageStore: MessageStore) {
        Task {
            if messageStore.employerConversations.first(where: { $0.id == conversationId }) == nil {
                await messageStore.loadConversations()
            }
            if let found = messageStore.employerConversations.first(where: { $0.id == conversationId }) {
                conversation = found
            } else {
                errorMessage = "The chat could not be found."
            }
        }
    }
}

private struct ApplicantChatModifier: ViewModifier {
    @ObservedObject var navigation: ApplicantChatNavigation
    @EnvironmentObject var messageStore: MessageStore

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(
                get: { navigation.conversation != nil },
                set: { if !$0 { navigation.conversation = nil } }
            )) {
                if let conversation = navigation.conversation {
                    ChatView(conversation: conversation, isEmployerMode: true)
                        .environmentObject(messageStore)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { navigation.errorMessage != nil },
                set: { if !$0 { navigation.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { navigation.errorMessage = nil }
            } message: {
                Text(navigation.errorMessage ?? "")
            }
    }
}

extension View {
    func applicantChatNavigation(_ navigation: ApplicantChatNavigation) -> some View {
        modifier(ApplicantChatModifier(navigation: navigation))
    }
}

struct ApplicantChatButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Chat", systemImage: "bubble.left.and.bubble.right")
        }
        .buttonStyle(.ds(.soft, size: .medium))
    }
}
