//
//  AppTabBar.swift
//  swipeShift
//

import SwiftUI

enum WorkerTab {
    case home
    case radar
    case messages
    case swipe
    case profile
}

struct AppTabBar: View {
    @Binding var selectedTab: WorkerTab

    var body: some View {
        HStack(spacing: 0) {
            tabItem(icon: "house.fill",      label: "Home",     tab: .home)
            tabItem(icon: "scope",           label: "Radar",    tab: .radar)
            tabItem(icon: "envelope.fill",   label: "Messages", tab: .messages)
            tabItem(icon: "arrow.left.arrow.right", label: "Swipe", tab: .swipe)
            tabItem(icon: "person.fill",     label: "Profile",  tab: .profile)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -2)
        )
        .padding(.horizontal, 16)
    }

    private func tabItem(icon: String, label: String, tab: WorkerTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? SS.primary : .gray.opacity(0.5))

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? SS.primary : .gray.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? SS.primary.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
