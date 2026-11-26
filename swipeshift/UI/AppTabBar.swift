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

// MARK: - Tab-Leisten-Abstand

extension DS {
    /// Platz, den die schwebende Pille am unteren Rand belegt (8 Abstand + 56 Pille) plus 16 Luft.
    static let tabBarInset: CGFloat = 80
}

extension View {
    /// Fuer ScrollViews, die bis zum unteren Rand laufen und unter der schwebenden Tab-Leiste weiterscrollen:
    /// das letzte Element bleibt frei scrollbar. Der Container muss dafuer die untere Safe Area ignorieren
    /// (siehe WorkerHomeView, Home-Tab).
    func dsTabBarInset() -> some View {
        contentMargins(.bottom, DS.tabBarInset, for: .scrollContent)
    }
}

// MARK: - Gemeinsame schwebende Pille

/// Ein Eintrag der Pille. `badge` > 0 zeigt den Unread-Punkt am Icon.
private struct DSTabItem<Tab: Hashable>: Identifiable {
    let tab: Tab
    let icon: String
    let label: String
    var badge: Int = 0
    var id: String { label }
}

/// Schwebende Pille: aktiver Tab mit Label + gefuellter Markenfarbe, gleitet per matchedGeometryEffect.
private struct DSFloatingTabBar<Tab: Hashable>: View {
    let items: [DSTabItem<Tab>]
    @Binding var selection: Tab

    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule()) // Milchglas: Inhalt scrollt verschwommen dahinter
        .overlay(Capsule().strokeBorder(DS.Color.border.opacity(0.6), lineWidth: 1))
        .shadow(color: DS.Color.shadowKey.opacity(0.10), radius: 15, x: 0, y: 8)
        .dsAnimation(.standard, value: selection)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Spacing.sm)
    }

    private func tabButton(_ item: DSTabItem<Tab>) -> some View {
        let isSelected = selection == item.tab
        return Button {
            guard !isSelected else { return }
            DS.Haptics.selection()
            selection = item.tab
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: item.icon)
                    .font(DS.Font.make(isSelected ? 17 : 19, .semibold, relativeTo: nil))
                    .overlay(alignment: .topTrailing) { badge(item.badge) }
                if isSelected {
                    Text(item.label)
                        .font(DS.Font.make(14, .bold, relativeTo: nil))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(isSelected ? DS.Color.primaryText : DS.Color.muted)
            .padding(.horizontal, isSelected ? DS.Spacing.md : 13)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                if isSelected {
                    Capsule()
                        .fill(DS.Color.primary.opacity(0.14)) // zarte Markierung statt voll blau
                        .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPressable)
        .accessibilityLabel(item.label)
        .accessibilityValue(item.badge > 0 ? "\(item.badge) unread" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func badge(_ count: Int) -> some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(DS.Font.make(10, .extrabold, relativeTo: nil))
                .foregroundStyle(DS.Color.onPrimary)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(DS.Color.danger, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Color.surface, lineWidth: 1.5))
                .offset(x: 9, y: -7)
        }
    }
}

// MARK: - EmployerTabBar
struct EmployerTabBar: View {
    @Binding var selectedTab: EmployerTab
    var unreadMessageCount: Int = 0

    var body: some View {
        DSFloatingTabBar(
            items: [
                DSTabItem(tab: .dashboard,  icon: "square.grid.2x2.fill", label: "Dashboard"),
                DSTabItem(tab: .jobs,       icon: "briefcase.fill",       label: "Jobs"),
                DSTabItem(tab: .applicants, icon: "person.2.fill",        label: "Applicants"),
                DSTabItem(tab: .messages,   icon: "envelope.fill",        label: "Messages", badge: unreadMessageCount),
                DSTabItem(tab: .profile,    icon: "person.fill",          label: "Profile"),
            ],
            selection: $selectedTab
        )
    }
}

// MARK: - AppTabBar (Worker)
struct AppTabBar: View {
    @Binding var selectedTab: WorkerTab
    var unreadMessageCount: Int = 0

    var body: some View {
        DSFloatingTabBar(
            items: [
                DSTabItem(tab: .home,     icon: "house.fill",              label: "Home"),
                DSTabItem(tab: .radar,    icon: "scope",                   label: "Radar"),
                DSTabItem(tab: .messages, icon: "envelope.fill",           label: "Messages", badge: unreadMessageCount),
                DSTabItem(tab: .swipe,    icon: "arrow.left.arrow.right",  label: "Swipe"),
                DSTabItem(tab: .profile,  icon: "person.fill",             label: "Profile"),
            ],
            selection: $selectedTab
        )
    }
}

#Preview("TabBar – Light") { TabBarPreview() }
#Preview("TabBar – Dark") { TabBarPreview().preferredColorScheme(.dark) }

private struct TabBarPreview: View {
    @State private var worker: WorkerTab = .messages
    @State private var employer: EmployerTab = .dashboard

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            AppTabBar(selectedTab: $worker, unreadMessageCount: 3)
            EmployerTabBar(selectedTab: $employer, unreadMessageCount: 12)
        }
        .padding(.vertical, DS.Spacing.xl)
        .dsBackground()
    }
}
