//
//  DSBadge.swift
//  swipeShift
//
//  DSBadge (Status), DSChip (auswaehlbar), DSAvatar (Initialen/Emoji).
//

import SwiftUI

// MARK: - Badge

struct DSBadge: View {
    enum Style {
        case today, upcoming, completed, cancelled
        case draft, published, inProgress
        case tone(DS.Tone)
    }

    let title: String
    var style: Style

    init(_ title: String, _ style: Style) {
        self.title = title
        self.style = style
    }

    private var foreground: Color {
        switch style {
        case .today: return DS.Color.onPrimary
        case .upcoming: return DS.Tone.success.foreground
        case .completed: return DS.Color.text2
        case .cancelled: return DS.Tone.danger.foreground
        case .draft: return DS.Color.text2
        case .published: return DS.Tone.primary.foreground
        case .inProgress: return DS.Tone.warning.foreground
        case .tone(let tone): return tone.foreground
        }
    }

    private var background: Color {
        switch style {
        case .today: return DS.Color.primary
        case .upcoming: return DS.Tone.success.soft
        case .completed: return DS.Color.surface2
        case .cancelled: return DS.Tone.danger.soft
        case .draft: return .clear
        case .published: return DS.Tone.primary.soft
        case .inProgress: return DS.Tone.warning.soft
        case .tone(let tone): return tone.soft
        }
    }

    private var isDraft: Bool {
        if case .draft = style { return true }
        return false
    }

    var body: some View {
        Text(title)
            .font(DS.Font.make(12, .bold, relativeTo: .caption))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .overlay {
                if isDraft {
                    Capsule().strokeBorder(DS.Color.muted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Chip

struct DSChip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            DS.Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                .foregroundStyle(isSelected ? DS.Color.onPrimary : DS.Color.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    isSelected ? DS.Color.primary : DS.Color.surface,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(isSelected ? DS.Color.primary : DS.Color.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.dsPressable)
        .dsAnimation(.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Avatar

struct DSAvatar: View {
    enum Shape { case circle, roundedSquare }

    let text: String
    var size: CGFloat = 40
    var shape: Shape = .roundedSquare
    var tone: DS.Tone = .primary

    /// "Blue Cup Coffee" -> "BC", "Anna" -> "A"
    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Text(text)
            .font(DS.Font.make(size * 0.35, .extrabold, relativeTo: nil))
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(tone.soft, in: clipShape)
            .accessibilityHidden(true)
    }

    private var clipShape: AnyShape {
        switch shape {
        case .circle: return AnyShape(Circle())
        case .roundedSquare: return AnyShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        }
    }
}

#Preview("Badge/Chip/Avatar – Light") { DSBadgePreview() }
#Preview("Badge/Chip/Avatar – Dark") { DSBadgePreview().preferredColorScheme(.dark) }

private struct DSBadgePreview: View {
    @State private var selected = "Events"

    var body: some View {
        DSPreviewCanvas {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                HStack {
                    DSBadge("Today", .today)
                    DSBadge("Upcoming", .upcoming)
                    DSBadge("Completed", .completed)
                    DSBadge("Cancelled", .cancelled)
                }
                HStack {
                    DSBadge("Draft", .draft)
                    DSBadge("Published", .published)
                    DSBadge("In progress", .inProgress)
                    DSBadge("Verified", .tone(.success))
                }
                HStack {
                    ForEach(["Hospitality", "Events", "Retail"], id: \.self) { name in
                        DSChip(name, isSelected: selected == name) { selected = name }
                    }
                }
                HStack(spacing: DS.Spacing.sm) {
                    DSAvatar(text: DSAvatar.initials(from: "Blue Cup Coffee"))
                    DSAvatar(text: "🍕", shape: .circle, tone: .warning)
                    DSAvatar(text: "AK", size: 56, shape: .circle, tone: .success)
                }
            }
        }
    }
}
