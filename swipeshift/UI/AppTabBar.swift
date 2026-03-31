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

enum EmployerTab {
    case dashboard
    case jobs
    case applicants
    case messages
    case profile
}

// MARK: - EmployerTabBar
struct EmployerTabBar: View {
    @Binding var selectedTab: EmployerTab
    var unreadMessageCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            employerTabItem(icon: "square.grid.2x2.fill", label: "Dashboard", tab: .dashboard)
            employerTabItem(icon: "briefcase.fill",        label: "Jobs",      tab: .jobs)
            employerTabItem(icon: "person.2.fill",         label: "Applicants",tab: .applicants)
            employerTabItemBadge(icon: "envelope.fill",    label: "Messages",  tab: .messages, badge: unreadMessageCount)
            employerTabItem(icon: "person.fill",           label: "Profile",   tab: .profile)
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

    private func employerTabItem(icon: String, label: String, tab: EmployerTab) -> some View {
        let isSelected = selectedTab == tab
        return Button { selectedTab = tab } label: {
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
            .background(isSelected ? SS.primary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func employerTabItemBadge(icon: String, label: String, tab: EmployerTab, badge: Int) -> some View {
        let isSelected = selectedTab == tab
        return Button { selectedTab = tab } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? SS.primary : .gray.opacity(0.5))
                    if badge > 0 {
                        Text(badge > 9 ? "9+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? SS.primary : .gray.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isSelected ? SS.primary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct AppTabBar: View {
    @Binding var selectedTab: WorkerTab
    var unreadMessageCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            tabItem(icon: "house.fill",      label: "Home",     tab: .home)
            tabItem(icon: "scope",           label: "Radar",    tab: .radar)
            tabItemWithBadge(icon: "envelope.fill", label: "Messages", tab: .messages, badge: unreadMessageCount)
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

    private func tabItemWithBadge(icon: String, label: String, tab: WorkerTab, badge: Int) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? SS.primary : .gray.opacity(0.5))
                    if badge > 0 {
                        Text(badge > 9 ? "9+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? SS.primary : .gray.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isSelected ? SS.primary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
