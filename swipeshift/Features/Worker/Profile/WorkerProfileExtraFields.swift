//
//  WorkerProfileExtraFields.swift
//  swipeShift
//
//  Teil-Views fuer EditProfileView: Tageszeiten, Schicht-Typen, Erfahrung je Kategorie.
//  Rendern nur den Inhalt (flach, ohne Karte), damit sie in die DSSection-Gruppen passen.
//

import SwiftUI

/// Beschriftete Chip-Auswahl (Mehrfachauswahl) fuer Whitelist-Werte
struct ProfileChipPicker<Option: Identifiable & Hashable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Set<Option>

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(DS.Color.text2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: DS.Spacing.xs)], alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(options) { option in
                    let isOn = selection.contains(option)
                    DSChip(label(option), isSelected: isOn) {
                        if isOn { selection.remove(option) } else { selection.insert(option) }
                    }
                }
            }
        }
    }
}

/// Erfahrung je Kategorie: pro Zeile ein Menue "None / < 3 months / 3–12 months / 1+ years"
struct ExperienceEditor: View {
    let categories: [String]
    @Binding var levels: [String: ExperienceLevel]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                DSRow(category, showsDivider: index > 0) {
                    Menu {
                        Button("None") { levels[category] = nil }
                        ForEach(ExperienceLevel.allCases) { level in
                            Button(level.title) { levels[category] = level }
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.xxs) {
                            Text(levels[category]?.title ?? "None")
                                .dsFont(.body)
                                .foregroundStyle(levels[category] == nil ? DS.Color.muted : DS.Color.primaryText)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Color.muted)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }
}
