
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(JobCategory.all) { category in
                    CategoryItemView(category: category)
                        .onTapGesture {
                            onSelect(category)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// NEU
struct CategoryItemView: View {
    let category: JobCategory

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color.white)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                .overlay(
                    Image(systemName: category.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(SS.primary)
                )

            Text(category.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
    }
}
