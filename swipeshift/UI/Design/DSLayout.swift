//
//  DSLayout.swift
//  swipeShift
//
//  Flache Abschnitte (DSSection/DSRow/DSToggleRow), Karte (DSCard), Kachel (DSTile).
//  Regel: flach fuer Formulare/Einstellungen, Karte nur fuer Antippbares, Kachel fuer Kennzahlen.
//

import SwiftUI

// MARK: - Section

/// Flacher Abschnitt: Sektionslabel + Inhalt, keine Box.
/// `ruled: true` zeichnet unter dem Inhalt die letzte Trennlinie (fuer DSRow-Listen).
struct DSSection<Content: View>: View {
    let label: String
    var trailing: String?
    var ruled: Bool
    let content: Content

    init(_ label: String, trailing: String? = nil, ruled: Bool = true, @ViewBuilder content: () -> Content) {
        self.label = label
        self.trailing = trailing
        self.ruled = ruled
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .dsFont(.sectionLabel)
                    .foregroundStyle(DS.Color.muted)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Spacing.sm)
                if let trailing {
                    Text(trailing).dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
            }
            .padding(.bottom, DS.Spacing.xs)

            VStack(alignment: .leading, spacing: 0) { content }
                .overlay(alignment: .bottom) {
                    if ruled { DSDivider() }
                }
        }
    }
}

struct DSDivider: View {
    var body: some View {
        Rectangle().fill(DS.Color.border).frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Row

/// Zeile: Titel, optional Untertitel / Wert / Icon-Kachel / Chevron. Trennlinie oben, min. 44pt.
struct DSRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var value: String?
    var accentValue: Bool
    var systemIcon: String?
    var iconTone: DS.Tone
    var showsChevron: Bool
    var showsDivider: Bool
    var action: (() -> Void)?
    let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        value: String? = nil,
        accentValue: Bool = false,
        systemIcon: String? = nil,
        iconTone: DS.Tone = .primary,
        showsChevron: Bool = false,
        showsDivider: Bool = true,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.accentValue = accentValue
        self.systemIcon = systemIcon
        self.iconTone = iconTone
        self.showsChevron = showsChevron
        self.showsDivider = showsDivider
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(DSRowButtonStyle())
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let systemIcon {
                DSIconTile(systemName: systemIcon, tone: iconTone)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(.body).foregroundStyle(DS.Color.text)
                if let subtitle {
                    Text(subtitle).dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
            }
            Spacer(minLength: DS.Spacing.sm)
            if let value {
                Text(value)
                    .font(DS.Font.make(15, .semibold))
                    .foregroundStyle(accentValue ? DS.Color.primaryText : DS.Color.text)
                    .multilineTextAlignment(.trailing)
            }
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if showsDivider { DSDivider() }
        }
    }
}

extension DSRow where Trailing == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        value: String? = nil,
        accentValue: Bool = false,
        systemIcon: String? = nil,
        iconTone: DS.Tone = .primary,
        showsChevron: Bool = false,
        showsDivider: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title, subtitle: subtitle, value: value, accentValue: accentValue,
            systemIcon: systemIcon, iconTone: iconTone, showsChevron: showsChevron,
            showsDivider: showsDivider, action: action
        ) { EmptyView() }
    }
}

private struct DSRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Color.surface2.opacity(0.6) : Color.clear)
    }
}

/// Getoente Icon-Kachel (36x36) fuer Zeilen.
struct DSIconTile: View {
    let systemName: String
    var tone: DS.Tone = .primary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tone.foreground)
            .frame(width: 36, height: 36)
            .background(tone.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Toggle Row

struct DSToggleRow: View {
    let title: String
    var subtitle: String?
    var systemIcon: String?
    var iconTone: DS.Tone = .primary
    var showsDivider: Bool = true
    @Binding var isOn: Bool

    init(
        _ title: String,
        subtitle: String? = nil,
        systemIcon: String? = nil,
        iconTone: DS.Tone = .primary,
        showsDivider: Bool = true,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemIcon = systemIcon
        self.iconTone = iconTone
        self.showsDivider = showsDivider
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let systemIcon { DSIconTile(systemName: systemIcon, tone: iconTone) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(.body).foregroundStyle(DS.Color.text)
                if let subtitle {
                    Text(subtitle).dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
            }
            Spacer(minLength: DS.Spacing.sm)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(DS.Color.primary)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .overlay(alignment: .top) {
            if showsDivider { DSDivider() }
        }
        .onChange(of: isOn) { _, _ in DS.Haptics.selection() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Card

/// Container fuer ANTIPPBARE Inhalte. Mit `action` wird die ganze Karte zum Button.
struct DSCard<Content: View>: View {
    var action: (() -> Void)?
    let content: Content

    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.dsPressable)
        } else {
            card
        }
    }

    private var card: some View {
        content
            .padding(DS.Spacing.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Color.border, lineWidth: 1)
            )
            .dsCardShadow()
    }
}

// MARK: - Tile

/// Getoente Kennzahl-Kachel.
struct DSTile: View {
    let label: String
    let value: String
    var tone: DS.Tone = .primary
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(label)
                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                .foregroundStyle(tone.foreground)
            Text(value)
                .font(DS.Font.make(22, .extrabold, relativeTo: .title2))
                .foregroundStyle(DS.Color.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let caption {
                Text(caption).dsFont(.caption).foregroundStyle(DS.Color.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Layout – Light") { DSLayoutPreview() }
#Preview("Layout – Dark") { DSLayoutPreview().preferredColorScheme(.dark) }

private struct DSLayoutPreview: View {
    @State private var notify = true

    var body: some View {
        DSPreviewCanvas {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                DSSection("Pay") {
                    DSRow("Hourly rate", value: "$22.00")
                    DSRow("Payment", value: "Weekly", accentValue: true, showsChevron: true) {}
                    DSRow("Account", subtitle: "Security and sessions", systemIcon: "lock", showsChevron: true) {}
                    DSToggleRow("Push notifications", systemIcon: "bell", isOn: $notify)
                }
                DSSection("Shifts", trailing: "Duration is calculated") {
                    DSRow("Thu, Nov 26", subtitle: "18:00 – 23:00", value: "5 h")
                }
                DSCard(action: {}) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Barista").dsFont(.headline)
                        Text("Blue Cup Coffee · 1.2 mi").dsFont(.caption).foregroundStyle(DS.Color.muted)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                    DSTile(label: "Upcoming", value: "$340", tone: .primary)
                    DSTile(label: "Paid out", value: "$1,280", tone: .success)
                    DSTile(label: "Pending", value: "$90", tone: .warning)
                    DSTile(label: "Disputed", value: "$0", tone: .danger)
                }
            }
        }
    }
}
