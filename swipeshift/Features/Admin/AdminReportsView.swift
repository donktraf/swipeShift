//
//  AdminReportsView.swift
//  swipeShift
//
//  Admin-Bereich: gemeldete Nutzer pruefen und moderieren. Nur sichtbar fuer Admin-Konten.
//

import SwiftUI
import Combine

/// Gemeinsame Fehleranzeige fuer die Admin-Screens.
private struct AdminErrorBlock: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text(message)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.danger)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.ds(.primary, size: .medium, fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
    }
}

/// Skeleton-Platzhalter fuer Karten-Listen.
private struct AdminCardSkeleton: View {
    var count: Int = 3

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(0..<count, id: \.self) { _ in
                DSCard {
                    HStack(spacing: DS.Spacing.sm) {
                        Circle().fill(DS.Color.surface2).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            DSSkeletonBlock(width: 140, height: 14)
                            DSSkeletonBlock(width: 200, height: 12)
                            DSSkeletonBlock(width: 100, height: 12)
                        }
                    }
                }
            }
        }
        .dsSkeleton(true)
    }
}

struct AdminReportsView: View {
    private enum Mode { case open, closed, reliability }

    @State private var mode: Mode = .open
    private var showClosed: Bool { mode == .closed }
    @State private var reports: [AdminReport] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @StateObject private var reliability = AdminReliabilityModel()

    var body: some View {
        SubScreenShell(title: "Reports") {
            VStack(spacing: DS.Spacing.md) {
                Picker("Status", selection: $mode) {
                    Text("Open").tag(Mode.open)
                    Text("Closed").tag(Mode.closed)
                    Text("Reliability").tag(Mode.reliability)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.screenEdge)

                content
                    .padding(.horizontal, DS.Spacing.screenEdge)
            }
        }
        .refreshable {
            if mode == .reliability { await reliability.load(showSkeleton: false) } else { await load(showSkeleton: false) }
        }
        .task(id: mode) {
            if mode == .reliability { await reliability.load(showSkeleton: reliability.data == nil) } else { await load() }
        }
        .onChange(of: mode) { _, _ in DS.Haptics.selection() }
    }

    @ViewBuilder
    private var content: some View {
        if mode == .reliability {
            AdminReliabilitySection(model: reliability)
        } else if isLoading {
            AdminCardSkeleton()
        } else if let loadError {
            AdminErrorBlock(message: loadError) { Task { await load() } }
        } else if reports.isEmpty {
            DSEmptyState(
                systemIcon: "checkmark.shield",
                title: showClosed ? "No closed reports" : "All clear",
                message: showClosed ? "No closed reports yet." : "No open reports. All clear."
            )
        } else {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(reports) { report in
                    NavigationLink {
                        AdminReportDetailView(reportId: report.id) { Task { await load(showSkeleton: false) } }
                    } label: { card(report) }
                    .buttonStyle(.dsPressable)
                    .simultaneousGesture(TapGesture().onEnded { DS.Haptics.light() })
                }
            }
        }
    }

    private func card(_ r: AdminReport) -> some View {
        DSCard {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                ChatAvatar(photoUrl: nil, emoji: r.reported.initial, size: 44)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(r.reported.name).dsFont(.headline).foregroundStyle(DS.Color.text).lineLimit(1)
                    Text("\(r.reported.roleLabel) · \(r.reasonLabel)")
                        .dsFont(.caption).foregroundStyle(DS.Color.text2)
                    HStack(spacing: DS.Spacing.xs) {
                        if showClosed {
                            DSBadge(r.resolutionLabel ?? "Closed", .completed)
                        } else {
                            DSBadge("\(r.openReportCount) report\(r.openReportCount == 1 ? "" : "s") · \(r.openReporterCount) reporter\(r.openReporterCount == 1 ? "" : "s")",
                                    .tone(r.openReporterCount >= 3 ? .danger : .warning))
                        }
                        if r.reported.isDeleted {
                            DSBadge(r.reported.isEmailBanned ? "Deleted account · email banned" : "Deleted account",
                                    r.reported.isEmailBanned ? .cancelled : .completed)
                        } else if r.reported.restriction.isRestricted {
                            DSBadge(r.reported.restriction.label, .cancelled)
                        }
                    }
                    Text((showClosed ? (r.resolvedAt ?? r.createdAt) : r.createdAt).formatted(date: .abbreviated, time: .shortened))
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.muted)
            }
        }
    }

    @MainActor
    private func load(showSkeleton: Bool = true) async {
        if showSkeleton { isLoading = true }
        loadError = nil
        do {
            reports = try await APIClient.shared.fetchAdminReports(closed: showClosed)
        } catch {
            if !(error is CancellationError) { loadError = error.localizedDescription }
        }
        isLoading = false
    }
}

// MARK: - Detail

struct AdminReportDetailView: View {
    let reportId: String
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var detail: AdminReportDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var note = ""
    @State private var pending: AdminModerationAction?
    @State private var showLiftConfirm = false
    @State private var showUnbanConfirm = false
    @State private var isWorking = false
    @State private var actionError: String?

    var body: some View {
        SubScreenShell(title: "Report") {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                if isLoading {
                    AdminCardSkeleton(count: 2)
                } else if let loadError {
                    AdminErrorBlock(message: loadError) { Task { await load() } }
                } else if let detail {
                    body(detail)
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
        }
        .refreshable { await load(showSkeleton: false) }
        .task { await load() }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { action in
            Button(confirmButton(action), role: action == .dismiss || action == .warn ? nil : .destructive) {
                Task { await perform(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            if action == .ban, detail?.report.reported.isDeleted == true {
                Text("This blocks the email address (including aliases) from registering again and closes all open reports.\(detail?.report.reported.emailVerified == false ? " This email address was never verified." : "")")
            } else {
                Text("This closes all open reports against this user and notifies the reporters.")
            }
        }
        .confirmationDialog("Unban email address?", isPresented: $showUnbanConfirm, titleVisibility: .visible) {
            Button("Unban email") { Task { await unbanEmail() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This email address (including aliases) can be used to register again. The deleted account stays deleted.")
        }
        .confirmationDialog("Lift restriction?", isPresented: $showLiftConfirm, titleVisibility: .visible) {
            Button("Lift restriction") { Task { await lift() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The user can sign in again and their jobs become visible.")
        }
    }

    private var confirmTitle: String {
        switch pending {
        case .warn: return "Send a warning?"
        case .suspend7: return "Suspend for 7 days?"
        case .suspend30: return "Suspend for 30 days?"
        case .ban: return detail?.report.reported.isDeleted == true ? "Ban email address?" : "Ban permanently?"
        case .dismiss: return "Dismiss report?"
        case nil: return ""
        }
    }

    private func confirmButton(_ a: AdminModerationAction) -> String {
        switch a {
        case .warn: return "Warn"
        case .suspend7: return "Suspend 7 days"
        case .suspend30: return "Suspend 30 days"
        case .ban: return detail?.report.reported.isDeleted == true ? "Ban email address" : "Ban permanently"
        case .dismiss: return "Dismiss"
        }
    }

    @ViewBuilder
    private func body(_ d: AdminReportDetail) -> some View {
        let r = d.report
        DSCard {
            HStack(spacing: DS.Spacing.sm) {
                ChatAvatar(photoUrl: r.reported.photoUrl, emoji: r.reported.initial, size: 48)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(r.reported.name).dsFont(.headline).foregroundStyle(DS.Color.text)
                    Text("\(r.reported.roleLabel) · reported for \(r.reasonLabel.lowercased())")
                        .dsFont(.caption).foregroundStyle(DS.Color.text2)
                    if r.reported.isDeleted {
                        let when = r.reported.deletedAt.map { " on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
                        DSBadge("Deleted account\(r.reported.deletedName.map { " (\($0))" } ?? "")\(when)", .completed)
                            .padding(.top, DS.Spacing.xxs)
                    } else {
                        DSBadge(r.reported.restriction.label, r.reported.restriction.isRestricted ? .cancelled : .upcoming)
                            .padding(.top, DS.Spacing.xxs)
                    }
                }
                Spacer(minLength: 0)
            }
        }

        DSSection("Reporter notes (\(d.reports.count))") {
            ForEach(d.reports) { n in
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("\(n.reporter.name) · \(AdminReport.label(for: n.reason))")
                        .dsFont(.callout).fontWeight(.semibold).foregroundStyle(DS.Color.text)
                    Text(n.details ?? "No details provided.")
                        .dsFont(.callout).foregroundStyle(n.details == nil ? DS.Color.muted : DS.Color.text)
                    Text(n.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.sm)
                if n.id != d.reports.last?.id { DSDivider() }
            }
        }

        if let convo = d.conversation {
            DSSection("Chat transcript (read-only)") {
                Text(([convo.jobTitle].compactMap { $0 } + convo.participants.map { "\($0.name) (\($0.roleLabel))" }).joined(separator: " · "))
                    .dsFont(.caption).foregroundStyle(DS.Color.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Spacing.xs)
                if convo.messages.isEmpty {
                    Text("No messages.").dsFont(.callout).foregroundStyle(DS.Color.muted)
                        .padding(.vertical, DS.Spacing.xs)
                }
                VStack(spacing: DS.Spacing.xs) {
                    ForEach(convo.messages) { msg in
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(msg.isSystem ? "System" : (convo.participants.first { $0.id == msg.senderId }?.name ?? "User"))
                                .dsFont(.caption).fontWeight(.semibold)
                                .foregroundStyle(msg.senderId == r.reported.id ? DS.Color.danger : DS.Color.text2)
                            Text(msg.text).dsFont(.callout).foregroundStyle(DS.Color.text)
                            Text(msg.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        }
                        .padding(DS.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    }
                }
                .padding(.bottom, DS.Spacing.sm)
            }
        }

        DSSection("Moderation history") {
            if d.history.isEmpty {
                Text("No previous actions.").dsFont(.callout).foregroundStyle(DS.Color.muted)
                    .padding(.vertical, DS.Spacing.sm)
            }
            ForEach(d.history) { h in
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(h.actionLabel).dsFont(.callout).fontWeight(.semibold).foregroundStyle(DS.Color.text)
                    Text("\(h.admin?.name ?? "System") · \(h.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                    if let n = h.note { Text(n).dsFont(.caption).foregroundStyle(DS.Color.text2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.sm)
                if h.id != d.history.last?.id { DSDivider() }
            }
        }

        if r.status == "open" {
            DSSection("Decision", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    DSTextEditor("Internal note", placeholder: "Optional, max 500 characters", text: $note,
                                 minLines: 2, maxLines: 4, maxLength: 500)
                    if r.reported.isDeleted {
                        Text("This account was deleted. You can dismiss the report\(r.reported.canBan == true ? " or ban the email address so it can't be used to register again." : ".")")
                            .dsFont(.caption).foregroundStyle(DS.Color.text2)
                        if r.reported.canBan == true {
                            actionButton("Ban email address", icon: "nosign", variant: .destructiveSoft, .ban)
                        }
                    } else {
                        actionButton("Warn", icon: "exclamationmark.triangle.fill", variant: .soft, .warn)
                    }
                    if r.reported.isAdmin != true && !r.reported.isDeleted {
                        actionButton("Suspend 7 days", icon: "pause.circle.fill", variant: .destructiveSoft, .suspend7)
                        actionButton("Suspend 30 days", icon: "pause.circle.fill", variant: .destructiveSoft, .suspend30)
                        actionButton("Ban permanently", icon: "nosign", variant: .destructiveSoft, .ban)
                    }
                    actionButton("Dismiss report", icon: "checkmark.circle.fill", variant: .secondary, .dismiss)
                }
            }
        } else if let label = r.resolutionLabel {
            DSCard { Text("Closed: \(label)").dsFont(.callout).fontWeight(.semibold).foregroundStyle(DS.Color.text) }
        }

        if r.reported.isEmailBanned {
            Button { DS.Haptics.light(); showUnbanConfirm = true } label: { Text("Unban email") }
                .buttonStyle(.ds(.soft, size: .medium))
                .disabled(isWorking)
        }

        if r.reported.restriction.isRestricted && !r.reported.isDeleted {
            Button { DS.Haptics.light(); showLiftConfirm = true } label: { Text("Lift restriction") }
                .buttonStyle(.ds(.soft, size: .medium))
                .disabled(isWorking)
        }

        if let actionError {
            Text(actionError).dsFont(.caption).foregroundStyle(DS.Color.danger)
        }
    }

    private func actionButton(_ title: String, icon: String, variant: DSButtonVariant, _ action: AdminModerationAction) -> some View {
        Button {
            DS.Haptics.warning()
            pending = action
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.ds(variant, size: .medium))
        .disabled(isWorking)
    }

    @MainActor
    private func load(showSkeleton: Bool = true) async {
        if showSkeleton { isLoading = true }
        loadError = nil
        do {
            detail = try await APIClient.shared.fetchAdminReport(id: reportId)
        } catch {
            if !(error is CancellationError) { loadError = error.localizedDescription }
        }
        isLoading = false
    }

    @MainActor
    private func perform(_ action: AdminModerationAction) async {
        isWorking = true
        actionError = nil
        do {
            try await APIClient.shared.applyAdminAction(reportId: reportId, action: action, note: note)
            DS.Haptics.success()
            onChanged()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
        isWorking = false
    }

    @MainActor
    private func unbanEmail() async {
        guard let id = detail?.report.reported.id else { return }
        isWorking = true
        actionError = nil
        do {
            try await APIClient.shared.unbanDeletedAccount(id: id)
            DS.Haptics.success()
            onChanged()
            await load()
        } catch {
            actionError = error.localizedDescription
        }
        isWorking = false
    }

    @MainActor
    private func lift() async {
        guard let id = detail?.report.reported.id else { return }
        isWorking = true
        actionError = nil
        do {
            try await APIClient.shared.liftAdminRestriction(userId: id)
            DS.Haptics.success()
            onChanged()
            await load()
        } catch {
            actionError = error.localizedDescription
        }
        isWorking = false
    }
}

// MARK: - Reliability (auffaellige Worker + Anwesenheits-Einsprueche)

@MainActor
final class AdminReliabilityModel: ObservableObject {
    @Published var data: AdminReliabilityResponse?
    @Published var isLoading = true
    @Published var loadError: String?

    func load(showSkeleton: Bool = true) async {
        if showSkeleton { isLoading = true }
        loadError = nil
        do { data = try await APIClient.shared.fetchAdminReliability() }
        catch { if !(error is CancellationError) { loadError = error.localizedDescription } }
        isLoading = false
    }
}

private extension AttendanceStatus {
    var badgeTone: DS.Tone {
        switch self {
        case .attended: return .success
        case .late: return .warning
        case .noShow: return .danger
        }
    }
}

/// Nur ein Hinweis fuer Admins — es gibt keine automatischen Einschraenkungen und keinen Einfluss auf Instant Match.
struct AdminReliabilitySection: View {
    @ObservedObject var model: AdminReliabilityModel
    @State private var resolving: AdminAttendanceDispute?
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if model.isLoading {
                AdminCardSkeleton(count: 2)
            } else if let loadError = model.loadError {
                AdminErrorBlock(message: loadError) { Task { await model.load() } }
            } else if let data = model.data {
                DSSection("Open disputes (\(data.disputes.count))", ruled: false) {
                    if data.disputes.isEmpty {
                        emptyText("No open disputes.")
                    } else {
                        VStack(spacing: DS.Spacing.sm) {
                            ForEach(data.disputes) { disputeCard($0) }
                        }
                        .padding(.top, DS.Spacing.xs)
                    }
                }

                DSSection("Conspicuous workers · last \(data.windowDays) days", ruled: false) {
                    Text("2 or more no-shows, or 3 or more late cancellations. This is a hint only, nothing is restricted automatically.")
                        .dsFont(.caption).foregroundStyle(DS.Color.text2)
                        .padding(.bottom, DS.Spacing.xs)
                    if data.flagged.isEmpty {
                        emptyText("No conspicuous workers.")
                    } else {
                        VStack(spacing: DS.Spacing.sm) {
                            ForEach(data.flagged) { flaggedCard($0) }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Decide dispute", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
            if let d = resolving {
                Button("Keep entry (\(d.status?.label ?? "as recorded"))") { Task { await resolve(d, uphold: true, attendance: nil) } }
                ForEach(AttendanceStatus.allCases.filter { $0 != d.status }) { status in
                    Button("Change to \(status.label)") { Task { await resolve(d, uphold: false, attendance: status) } }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("The worker is notified about the decision.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).dsFont(.callout).foregroundStyle(DS.Color.muted).padding(.vertical, DS.Spacing.xs)
    }

    private func flaggedCard(_ f: AdminFlaggedWorker) -> some View {
        DSCard {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                ChatAvatar(photoUrl: nil, emoji: f.worker.initial, size: 44)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(f.worker.name).dsFont(.headline).foregroundStyle(DS.Color.text).lineLimit(1)
                    HStack(spacing: DS.Spacing.xs) {
                        if f.noShows > 0 { DSBadge("\(f.noShows) no-show\(f.noShows == 1 ? "" : "s")", .cancelled) }
                        if f.lateCancellations > 0 { DSBadge("\(f.lateCancellations) late cancellation\(f.lateCancellations == 1 ? "" : "s")", .inProgress) }
                        if f.worker.restriction.isRestricted { DSBadge(f.worker.restriction.label, .cancelled) }
                    }
                    Text("\(f.finishedShifts) finished shift\(f.finishedShifts == 1 ? "" : "s") · \(f.late) late")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func disputeCard(_ d: AdminAttendanceDispute) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Text(d.worker.name).dsFont(.headline).foregroundStyle(DS.Color.text).lineLimit(1)
                    Spacer()
                    if let status = d.status { DSBadge(status.label, .tone(status.badgeTone)) }
                }
                Text("\(d.jobTitle) · \(d.company)").dsFont(.caption).foregroundStyle(DS.Color.text2)
                if let note = d.note {
                    Text("\"\(note)\"").dsFont(.callout).foregroundStyle(DS.Color.text)
                }
                if d.employerDeleted == true {
                    DSBadge("Employer account deleted", .inProgress)
                }
                Text("Disputed \(d.disputedAt.formatted(date: .abbreviated, time: .shortened))")
                    .dsFont(.caption).foregroundStyle(DS.Color.muted)
                Button("Decide") { DS.Haptics.light(); resolving = d }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .padding(.top, DS.Spacing.xxs)
            }
        }
    }

    @MainActor
    private func resolve(_ d: AdminAttendanceDispute, uphold: Bool, attendance: AttendanceStatus?) async {
        do {
            try await APIClient.shared.resolveAttendanceDispute(applyId: d.applyId, uphold: uphold, attendance: attendance)
            DS.Haptics.success()
            await model.load(showSkeleton: false)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
