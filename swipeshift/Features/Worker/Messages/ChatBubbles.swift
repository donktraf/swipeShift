//
//  ChatBubbles.swift
//  swipeShift
//
//  Nachrichten-Blasen + Presence-Bausteine fuer ChatView: Lesebestaetigung,
//  Online-/Typing-Zeile im Header, animierte Typing-Blase.
//  Presence-Daten kommen per Polling aus GET /messages/:conversationId.
//

import SwiftUI

// MARK: - Nachrichten-Blasen

/// System-Nachricht: zentriert, kursiv (z.B. "Bewerbung angenommen", "Schicht abgeschlossen")
struct SystemMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .italic()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Capsule())
            Spacer(minLength: 24)
        }
        .padding(.vertical, 4)
    }
}

/// Nachricht vom Worker (rechts, lila)
struct UserBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(SS.primary)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )
                    .clipShape(
                        .rect(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: 18,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 18
                        )
                    )
                HStack(spacing: 4) {
                    Text(message.timestamp.timeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    ReadReceiptIcon(message: message)
                }
            }
        }
    }
}

/// Nachricht vom Arbeitgeber (links, grau)
struct EmployerBubble: View {
    let message: ChatMessage
    let logoEmoji: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(logoEmoji)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(
                        .rect(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: 4,
                            bottomTrailingRadius: 18,
                            topTrailingRadius: 18
                        )
                    )
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                Text(message.timestamp.timeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Presence

/// Lesebestaetigung unter eigenen Nachrichten:
/// Uhr = wird gesendet, ein Haken = zugestellt, zwei Haken (Markenfarbe) = gelesen
struct ReadReceiptIcon: View {
    let message: ChatMessage

    private var isPending: Bool { message.id.hasPrefix("optimistic-") }

    var body: some View {
        Group {
            if isPending {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
            } else if message.isReadByOther {
                ZStack(alignment: .leading) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark").offset(x: 4)
                }
                .padding(.trailing, 4)
                .foregroundColor(SS.primary)
            } else {
                Image(systemName: "checkmark")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 9, weight: .bold))
        .accessibilityLabel(isPending ? "Sending" : (message.isReadByOther ? "Read" : "Delivered"))
    }
}

/// Status-Zeile im Header: "typing…" > "Online" > "Last seen …"
struct PresenceLine: View {
    let presence: ChatPresence

    var body: some View {
        if presence.otherIsTyping {
            Text("typing…")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SS.primary)
        } else if presence.otherIsOnline {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Online")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else if let lastSeen = presence.otherLastSeenAt {
            Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

/// Animierte "…"-Blase, solange die Gegenseite tippt
struct TypingBubble: View {
    let logoEmoji: String
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(logoEmoji)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Circle())

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(phase == i ? 1 : 0.35)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(uiColor: .systemBackground))
            .clipShape(
                .rect(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18
                )
            )
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            Spacer(minLength: 60)
        }
        .accessibilityLabel("Typing")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
    }
}

// MARK: - Date Helper
private extension Date {
    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
}
