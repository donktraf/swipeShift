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

/// Radius 18, die Schwanzseite (unten) nur 4
private func bubbleShape(tailOnTrailing: Bool) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: 18,
        bottomLeadingRadius: tailOnTrailing ? 18 : 4,
        bottomTrailingRadius: tailOnTrailing ? 4 : 18,
        topTrailingRadius: 18,
        style: .continuous
    )
}

/// System-Nachricht: zentriert, neutrale Pill (z.B. "Bewerbung angenommen", "Schicht abgeschlossen")
struct SystemMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: DS.Spacing.lg)
            Text(text)
                .dsFont(.caption)
                .foregroundStyle(DS.Color.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.surface2, in: Capsule())
            Spacer(minLength: DS.Spacing.lg)
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}

/// Eigene Nachricht (rechts, primary)
struct UserBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                Text(message.text)
                    .dsFont(.body)
                    .foregroundStyle(DS.Color.onPrimary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.primary, in: bubbleShape(tailOnTrailing: true))
                HStack(spacing: DS.Spacing.xxs) {
                    Text(message.timestamp.timeLabel)
                        .font(DS.Font.make(11, .medium, relativeTo: .caption2))
                        .foregroundStyle(DS.Color.muted)
                    ReadReceiptIcon(message: message)
                }
            }
        }
    }
}

/// Fremde Nachricht (links, surface2)
struct EmployerBubble: View {
    let message: ChatMessage
    let logoEmoji: String

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
            DSAvatar(text: logoEmoji, size: 28, shape: .circle, tone: .neutral)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(message.text)
                    .dsFont(.body)
                    .foregroundStyle(DS.Color.text)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.surface2, in: bubbleShape(tailOnTrailing: false))
                Text(message.timestamp.timeLabel)
                    .font(DS.Font.make(11, .medium, relativeTo: .caption2))
                    .foregroundStyle(DS.Color.muted)
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
                    .foregroundStyle(DS.Color.muted)
            } else if message.isReadByOther {
                ZStack(alignment: .leading) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark").offset(x: 4)
                }
                .padding(.trailing, 4)
                .foregroundStyle(DS.Color.primaryText)
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(DS.Color.muted)
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
                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                .foregroundStyle(DS.Color.primaryText)
        } else if presence.otherIsOnline {
            HStack(spacing: DS.Spacing.xxs) {
                Circle().fill(DS.Color.success).frame(width: 6, height: 6)
                Text("Online")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
            }
        } else if let lastSeen = presence.otherLastSeenAt {
            Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.text2)
        }
    }
}

/// Animierte "…"-Blase, solange die Gegenseite tippt (statisch bei Reduce Motion)
struct TypingBubble: View {
    let logoEmoji: String
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
            DSAvatar(text: logoEmoji, size: 28, shape: .circle, tone: .neutral)

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(DS.Color.muted)
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion || phase == i ? 1 : 0.35)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 14)
            .background(DS.Color.surface2, in: bubbleShape(tailOnTrailing: false))
            Spacer(minLength: 60)
        }
        .accessibilityLabel("Typing")
        .task {
            guard !reduceMotion else { return }
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
