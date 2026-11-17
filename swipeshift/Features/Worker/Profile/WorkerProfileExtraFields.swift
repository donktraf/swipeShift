//
//  WorkerProfileExtraFields.swift
//  swipeShift
//
//  Teil-Views fuer EditProfileView: Tageszeiten, Schicht-Typen, Erfahrung je Kategorie.
//  Rendern nur den Inhalt (ohne Karte), damit sie in die vorhandenen Sections passen.
//

import SwiftUI

/// Beschriftete Chip-Auswahl (Mehrfachauswahl) fuer Whitelist-Werte
struct ProfileChipPicker<Option: Identifiable & Hashable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Set<Option>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(options) { option in
                    let isOn = selection.contains(option)
                    Button {
                        if isOn { selection.remove(option) } else { selection.insert(option) }
                    } label: {
                        Text(label(option))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isOn ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isOn ? SS.primary : Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

/// Erfahrung je Kategorie: pro Zeile ein Menue "None / < 3 months / 3–12 months / 1+ years"
struct ExperienceEditor: View {
    let categories: [String]
    @Binding var levels: [String: ExperienceLevel]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(categories, id: \.self) { category in
                HStack {
                    Text(category)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .padding(.leading, 14)
                    Spacer()
                    Menu {
                        Button("None") { levels[category] = nil }
                        ForEach(ExperienceLevel.allCases) { level in
                            Button(level.title) { levels[category] = level }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(levels[category]?.title ?? "None")
                                .font(.system(size: 14))
                                .foregroundColor(levels[category] == nil ? .secondary : SS.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.trailing, 14)
                }
                .padding(.vertical, 12)
                Divider().padding(.leading, 14)
            }
        }
    }
}
