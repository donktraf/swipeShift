
//
//  CategoryScrollView.swift
//  swipeShift
//

import SwiftUI

struct JobCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String // SF Symbol
}

// Alle verfügbaren Kategorien
extension JobCategory {
    static let all: [JobCategory] = [
        JobCategory(name: "Hospitality", icon: "cup.and.saucer.fill"),
        JobCategory(name: "Events",      icon: "star.fill"),
        JobCategory(name: "Logistics",   icon: "shippingbox.fill"),
        JobCategory(name: "Retail",      icon: "bag.fill"),
        JobCategory(name: "Office",      icon: "desktopcomputer"),
        JobCategory(name: "Warehouse",   icon: "building.2.fill"),
        JobCategory(name: "Customer Service", icon: "headphones"),
    ]
}

struct CategoryScrollView: View {
    // Callback wenn User auf eine Kategorie tippt
    let onSelect: (JobCategory) -> Void

    private static let tones: [DS.Tone] = [.primary, .success, .warning, .neutral]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                ForEach(Array(JobCategory.all.enumerated()), id: \.element.id) { index, category in
                    Button {
                        DS.Haptics.selection()
                        onSelect(category)
                    } label: {
                        CategoryItemView(category: category, tone: Self.tones[index % Self.tones.count])
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel(category.name)
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
        }
    }
}

/// Getöntes Rundquadrat (64x64) mit Icon + Name darunter.
struct CategoryItemView: View {
    let category: JobCategory
    var tone: DS.Tone = .primary

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: category.icon)
                .font(DS.Font.make(24, .semibold, relativeTo: nil))
                .foregroundStyle(tone.foreground)
                .frame(width: 64, height: 64)
                .background(tone.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(category.name)
                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                .foregroundStyle(DS.Color.text2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 80)
        }
        .frame(width: 84)
        .contentShape(Rectangle())
    }
}
