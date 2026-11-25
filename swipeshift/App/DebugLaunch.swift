//
//  DebugLaunch.swift
//  swipeShift
//
//  Entwickler-Werkzeug (nur DEBUG): App per Launch-Environment direkt auf einem Screen starten,
//  eingeloggt mit einem Debug-JWT. Wird von scripts/ui-snapshot.sh genutzt. Im Release-Build nicht kompiliert.
//
//    SS_DEBUG_TOKEN            JWT statt Keychain (wird nie in den Keychain geschrieben)
//    SS_DEBUG_SCREEN           z.B. worker.home, worker.jobDetail, employer.dashboard, chat, auth.login (siehe `handles`)
//    SS_DEBUG_JOB_ID           fuer worker.jobDetail
//    SS_DEBUG_CONVERSATION_ID  fuer chat (ohne ID: erste Konversation)
//    SS_DEBUG_APPEARANCE       light | dark
//

#if DEBUG
import SwiftUI

enum DebugLaunch {
    private static let env = ProcessInfo.processInfo.environment

    private static func value(_ key: String) -> String? {
        guard let v = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    static let screen: String? = value("SS_DEBUG_SCREEN")
    static let jobId: String? = value("SS_DEBUG_JOB_ID")
    static let conversationId: String? = value("SS_DEBUG_CONVERSATION_ID")

    /// auth.* Screens: bewusst ohne Token starten (auch ein evtl. vorhandener Keychain-Token wird ignoriert)
    static var isAuthScreen: Bool { screen?.hasPrefix("auth.") == true }

    /// Debug-Token (nil bei auth.* Screens)
    static var token: String? { isAuthScreen ? nil : value("SS_DEBUG_TOKEN") }

    /// true → Keychain weder lesen noch schreiben
    static var bypassesKeychain: Bool { isAuthScreen || value("SS_DEBUG_TOKEN") != nil }

    /// true, sobald irgendein SS_DEBUG_* Override aktiv ist (z.B. um Push-Dialoge zu unterdruecken)
    static var isActive: Bool { screen != nil || value("SS_DEBUG_TOKEN") != nil }

    static var colorScheme: ColorScheme? {
        switch value("SS_DEBUG_APPEARANCE")?.lowercased() {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}

/// Ziele, die per NavigationStack gepusht werden (gemeinsam fuer Worker- und Employer-Container)
enum DebugPushTarget: Identifiable, Hashable {
    case applications, calendar, financial, saved, settings, notifications, adminReports
    case employerCalendar, employerFinancial
    case chat(Conversation)

    var id: String {
        switch self {
        case .chat(let c): return "chat-\(c.id)"
        default: return "\(self)"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    @ViewBuilder func destination(isEmployer: Bool) -> some View {
        switch self {
        case .applications:      JobApplicationsView()
        case .calendar:          WorkerCalendarView()
        case .financial:         FinancialOverviewView()
        case .saved:             SavedView()
        case .settings:          AccountSettingsView()
        case .notifications:     NotificationsView()
        case .adminReports:      AdminReportsView()
        case .employerCalendar:  EmployerCalendarView()
        case .employerFinancial: EmployerFinancialView()
        case .chat(let c):       ChatView(conversation: c, isEmployerMode: isEmployer)
        }
    }

    /// Screens, die in beiden Containern gleich gepusht werden
    static func common(_ screen: String) -> DebugPushTarget? {
        switch screen {
        case "worker.notifications", "employer.notifications": return .notifications
        case "admin.reports": return .adminReports
        default: return nil
        }
    }

    /// Konversation fuer `chat` (per ID oder erste vorhandene); wartet kurz auf das Laden
    @MainActor static func chatTarget(messageStore: MessageStore) async -> DebugPushTarget? {
        for _ in 0..<20 {
            let all = messageStore.conversations
            if let id = DebugLaunch.conversationId {
                if let c = all.first(where: { $0.id == id }) { return .chat(c) }
            } else if let c = all.first {
                return .chat(c)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        print("DebugLaunch: Konversation nicht gefunden")
        return nil
    }
}

private struct DebugWorkerRouting: ViewModifier {
    @Binding var selectedTab: WorkerTab
    @Binding var navigateToAllJobs: Bool
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var messageStore: MessageStore
    @State private var pushed: DebugPushTarget?

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $pushed) { $0.destination(isEmployer: false) }
            .task { await route() }
    }

    @MainActor private func route() async {
        guard let screen = DebugLaunch.screen else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        switch screen {
        case "worker.home":         selectedTab = .home
        case "worker.radar":        selectedTab = .radar
        case "worker.messages":     selectedTab = .messages
        case "worker.swipe":        selectedTab = .swipe
        case "worker.profile":      selectedTab = .profile
        case "worker.jobList":      navigateToAllJobs = true
        case "worker.jobDetail":    if let id = DebugLaunch.jobId { jobStore.pendingDeepLinkJobId = id }
        case "worker.applications": pushed = .applications
        case "worker.calendar":     pushed = .calendar
        case "worker.financial":    pushed = .financial
        case "worker.saved":        pushed = .saved
        case "worker.settings":     pushed = .settings
        case "chat":
            selectedTab = .messages
            pushed = await DebugPushTarget.chatTarget(messageStore: messageStore)
        default:
            pushed = DebugPushTarget.common(screen)
        }
    }
}

private struct DebugEmployerRouting: ViewModifier {
    @Binding var selectedTab: EmployerTab
    @Binding var showPostJob: Bool
    @EnvironmentObject var messageStore: MessageStore
    @State private var pushed: DebugPushTarget?

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $pushed) { $0.destination(isEmployer: true) }
            .task { await route() }
    }

    @MainActor private func route() async {
        guard let screen = DebugLaunch.screen else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        switch screen {
        case "employer.dashboard":  selectedTab = .dashboard
        case "employer.jobs":       selectedTab = .jobs
        case "employer.applicants": selectedTab = .applicants
        case "employer.profile":    selectedTab = .profile
        case "employer.postJob":    showPostJob = true
        case "employer.calendar":   pushed = .employerCalendar
        case "employer.financial":  pushed = .employerFinancial
        case "employer.settings":   pushed = .settings
        case "chat":
            selectedTab = .messages
            pushed = await DebugPushTarget.chatTarget(messageStore: messageStore)
        default:
            pushed = DebugPushTarget.common(screen)
        }
    }
}

extension View {
    func debugWorkerRouting(selectedTab: Binding<WorkerTab>, navigateToAllJobs: Binding<Bool>) -> some View {
        modifier(DebugWorkerRouting(selectedTab: selectedTab, navigateToAllJobs: navigateToAllJobs))
    }

    func debugEmployerRouting(selectedTab: Binding<EmployerTab>, showPostJob: Binding<Bool>) -> some View {
        modifier(DebugEmployerRouting(selectedTab: selectedTab, showPostJob: showPostJob))
    }
}
#endif
