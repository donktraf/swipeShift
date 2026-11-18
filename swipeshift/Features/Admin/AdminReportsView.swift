//
//  AdminReportsView.swift
//  swipeShift
//
//  Admin-Bereich: gemeldete Nutzer pruefen und moderieren. Nur sichtbar fuer Admin-Konten.
//

import SwiftUI

struct AdminReportsView: View {
    @State private var showClosed = false
    @State private var reports: [AdminReport] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        SubScreenShell(title: "Reports") {
            VStack(spacing: 16) {
                Picker("Status", selection: $showClosed) {
                    Text("Open").tag(false)
                    Text("Closed").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                content
                    .padding(.horizontal, 16)
            }
        }
        .task(id: showClosed) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let loadError {
            VStack(spacing: 10) {
                Text(loadError).font(.system(size: 13)).foregroundColor(.red).multilineTextAlignment(.center)
                Button("Try again") { Task { await load() } }.buttonStyle(SSPrimaryButtonStyle())
            }
            .padding(.vertical, 24)
        } else if reports.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 28)).foregroundColor(.secondary)
                Text(showClosed ? "No closed reports yet." : "No open reports. All clear.")
                    .font(.system(size: 14)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(reports) { report in
                    NavigationLink {
                        AdminReportDetailView(reportId: report.id) { Task { await load() } }
                    } label: { card(report) }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ r: AdminReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ChatAvatar(photoUrl: nil, emoji: r.reported.initial, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.reported.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text("\(r.reported.roleLabel) · \(r.reasonLabel)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    if showClosed {
                        pill(r.resolutionLabel ?? "Closed", color: .gray)
                    } else {
                        pill("\(r.openReportCount) report\(r.openReportCount == 1 ? "" : "s") · \(r.openReporterCount) reporter\(r.openReporterCount == 1 ? "" : "s")",
                             color: r.openReporterCount >= 3 ? .red : .orange)
                    }
                    if r.reported.restriction.isRestricted {
                        pill(r.reported.restriction.label, color: .red)
                    }
                }
                Text((showClosed ? (r.resolvedAt ?? r.createdAt) : r.createdAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: SS.cardRadius))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        do {
            reports = try await APIClient.shared.fetchAdminReports(closed: showClosed)
        } catch {
            loadError = error.localizedDescription
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
    @State private var isWorking = false
    @State private var actionError: String?

    var body: some View {
        SubScreenShell(title: "Report") {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let loadError {
                    VStack(spacing: 10) {
                        Text(loadError).font(.system(size: 13)).foregroundColor(.red).multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }.buttonStyle(SSPrimaryButtonStyle())
                    }
                } else if let detail {
                    body(detail)
                }
            }
            .padding(.horizontal, 16)
        }
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
        } message: { _ in
            Text("This closes all open reports against this user and notifies the reporters.")
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
        case .ban: return "Ban permanently?"
        case .dismiss: return "Dismiss report?"
        case nil: return ""
        }
    }

    private func confirmButton(_ a: AdminModerationAction) -> String {
        switch a {
        case .warn: return "Warn"
        case .suspend7: return "Suspend 7 days"
        case .suspend30: return "Suspend 30 days"
        case .ban: return "Ban permanently"
        case .dismiss: return "Dismiss"
        }
    }

    @ViewBuilder
    private func body(_ d: AdminReportDetail) -> some View {
        let r = d.report
        card {
            HStack(spacing: 12) {
                ChatAvatar(photoUrl: r.reported.photoUrl, emoji: r.reported.initial, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.reported.name).font(.system(size: 16, weight: .semibold))
                    Text("\(r.reported.roleLabel) · reported for \(r.reasonLabel.lowercased())")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Text(r.reported.restriction.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(r.reported.restriction.isRestricted ? .red : .green)
                }
                Spacer()
            }
        }

        section("Reporter notes (\(d.reports.count))") {
            ForEach(d.reports) { n in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(n.reporter.name) · \(AdminReport.label(for: n.reason))")
                        .font(.system(size: 13, weight: .semibold))
                    Text(n.details ?? "No details provided.")
                        .font(.system(size: 13)).foregroundColor(n.details == nil ? .secondary : .primary)
                    Text(n.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if n.id != d.reports.last?.id { Divider() }
            }
        }

        if let convo = d.conversation {
            section("Chat transcript (read-only)") {
                Text(([convo.jobTitle].compactMap { $0 } + convo.participants.map { "\($0.name) (\($0.roleLabel))" }).joined(separator: " · "))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if convo.messages.isEmpty {
                    Text("No messages.").font(.system(size: 13)).foregroundColor(.secondary)
                }
                ForEach(convo.messages) { msg in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(msg.isSystem ? "System" : (convo.participants.first { $0.id == msg.senderId }?.name ?? "User"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(msg.senderId == r.reported.id ? .red : .secondary)
                        Text(msg.text).font(.system(size: 13))
                        Text(msg.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }

        section("Moderation history") {
            if d.history.isEmpty {
                Text("No previous actions.").font(.system(size: 13)).foregroundColor(.secondary)
            }
            ForEach(d.history) { h in
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.actionLabel).font(.system(size: 13, weight: .semibold))
                    Text("\(h.admin?.name ?? "System") · \(h.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if let n = h.note { Text(n).font(.system(size: 12)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if r.status == "open" {
            section("Decision") {
                TextField("Internal note (optional, max 500 characters)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onChange(of: note) { _, v in if v.count > 500 { note = String(v.prefix(500)) } }
                actionButton("Warn", icon: "exclamationmark.triangle.fill", color: .orange, .warn)
                actionButton("Suspend 7 days", icon: "pause.circle.fill", color: .orange, .suspend7)
                actionButton("Suspend 30 days", icon: "pause.circle.fill", color: .red, .suspend30)
                actionButton("Ban permanently", icon: "nosign", color: .red, .ban)
                actionButton("Dismiss report", icon: "checkmark.circle.fill", color: .green, .dismiss)
            }
        } else if let label = r.resolutionLabel {
            card { Text("Closed: \(label)").font(.system(size: 14, weight: .semibold)) }
        }

        if r.reported.restriction.isRestricted {
            Button { showLiftConfirm = true } label: {
                Text("Lift restriction").font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundColor(SS.primary)
                    .background(SS.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isWorking)
        }

        if let actionError {
            Text(actionError).font(.system(size: 12)).foregroundColor(.red)
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, _ action: AdminModerationAction) -> some View {
        Button { pending = action } label: {
            HStack {
                Image(systemName: icon)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundColor(color)
            .padding(12)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isWorking)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: SS.cardRadius))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            card { VStack(alignment: .leading, spacing: 10) { content() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        do {
            detail = try await APIClient.shared.fetchAdminReport(id: reportId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func perform(_ action: AdminModerationAction) async {
        isWorking = true
        actionError = nil
        do {
            try await APIClient.shared.applyAdminAction(reportId: reportId, action: action, note: note)
            onChanged()
            dismiss()
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
            onChanged()
            await load()
        } catch {
            actionError = error.localizedDescription
        }
        isWorking = false
    }
}
