//
//  AttendanceViews.swift
//  swipeShift
//
//  Employer-Seite der Zuverlaessigkeit:
//   - ReliabilityLabel: "96% showed up · 1 late · 0 late cancellations" bzw. "New" (Bewerberkarte, Worker-Profil)
//   - AttendanceSectionView: nach Schichtende je angenommenem Worker "Showed up" / "Late" / "No-show" erfassen
//     (48-h-Fenster; ohne Eintrag zaehlt die Schicht automatisch als "showed up")
//   - AttendanceScreen: eigener Screen dafuer (Jobkarte → "Record attendance")
//

import SwiftUI

// MARK: - Reliability Label

struct ReliabilityLabel: View {
    let summary: ReliabilitySummary
    var font: CGFloat = 12

    private var tint: Color {
        if summary.isNew { return summary.noShows > 0 || summary.lateCancellations > 0 ? DS.Color.warning : DS.Color.muted }
        if let rate = summary.showUpRate, rate >= 90, summary.noShows == 0 { return DS.Color.success }
        if let rate = summary.showUpRate, rate >= 75 { return DS.Color.warning }
        return DS.Color.danger
    }

    var body: some View {
        Label(summary.text, systemImage: "checkmark.shield")
            .font(DS.Font.make(font, .semibold, relativeTo: .caption))
            .foregroundStyle(tint)
            .lineLimit(2)
    }
}

// MARK: - Attendance Section

struct AttendanceSectionView: View {
    let jobId: String
    /// Wird nach jeder erfolgreichen Erfassung aufgerufen (z.B. Jobliste aktualisieren)
    var onChanged: () -> Void = {}

    @State private var response: JobAttendanceResponse?
    @State private var workingId: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let response, response.ended, !response.workers.isEmpty {
                section(response)
            }
        }
        .task { await load() }
        .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func section(_ response: JobAttendanceResponse) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Record attendance")
                .dsFont(.headline).foregroundStyle(DS.Color.text)
            Text(response.guidance)
                .dsFont(.caption).foregroundStyle(DS.Color.text2)
            if let deadline = response.deadline, response.workers.contains(where: { $0.pending }) {
                Text("If you don't record anything by \(deadline.formatted(date: .abbreviated, time: .shortened)), workers count as showed up.")
                    .dsFont(.caption).foregroundStyle(DS.Color.text2)
            }
            ForEach(response.workers) { worker in
                DSDivider()
                workerRow(worker)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workerRow(_ worker: AttendanceWorker) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text(worker.name).font(DS.Font.make(15, .semibold, relativeTo: .callout))
                    .foregroundStyle(DS.Color.text)
                Spacer()
                if worker.pending {
                    DSBadge("Needs your input", .tone(.warning))
                } else if worker.attendanceSource == "auto" {
                    Text("Recorded automatically").dsFont(.caption).foregroundStyle(DS.Color.muted)
                } else if worker.attendanceSource == "admin" {
                    Text("Decided by SwipeShift").dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
            }
            HStack(spacing: DS.Spacing.xs) {
                ForEach(AttendanceStatus.allCases) { status in
                    optionButton(status, worker: worker)
                }
            }
            if worker.disputeStatus == "pending" {
                Text("The worker disputed this entry\(worker.disputeNote.map { ": \"\($0)\"" } ?? ""). It is under review and can't be changed now.")
                    .dsFont(.caption).foregroundStyle(DS.Color.warning)
            } else if worker.disputeStatus == "resolved" {
                Text("The worker's dispute was reviewed.").dsFont(.caption).foregroundStyle(DS.Color.muted)
            } else if !worker.canRecord {
                Text("The 48-hour window to record attendance has ended.")
                    .dsFont(.caption).foregroundStyle(DS.Color.muted)
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    private func optionButton(_ status: AttendanceStatus, worker: AttendanceWorker) -> some View {
        let selected = worker.status == status
        return Button {
            Task { await record(worker, status) }
        } label: {
            Label(status.label, systemImage: status.icon)
                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                .foregroundStyle(selected ? DS.Color.onPrimary : status.color)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? status.color : status.tone.soft,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.dsPressable)
        .disabled(!worker.canRecord || workingId == worker.applyId)
        .opacity(worker.canRecord ? 1 : 0.5)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @MainActor
    private func load() async {
        do { response = try await APIClient.shared.fetchJobAttendance(jobId: jobId) }
        catch { /* Abschnitt bleibt einfach ausgeblendet */ }
    }

    @MainActor
    private func record(_ worker: AttendanceWorker, _ status: AttendanceStatus) async {
        guard worker.status != status else { return }
        workingId = worker.applyId
        defer { workingId = nil }
        do {
            try await APIClient.shared.recordAttendance(applyId: worker.applyId, status: status)
            DS.Haptics.selection()
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}

private extension AttendanceStatus {
    var tone: DS.Tone {
        switch self {
        case .attended: return .success
        case .late:     return .warning
        case .noShow:   return .danger
        }
    }
}

// MARK: - Screen

struct AttendanceScreen: View {
    let jobId: String
    let jobTitle: String
    var onChanged: () -> Void = {}

    var body: some View {
        SubScreenShell(title: "Attendance", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text(jobTitle)
                    .dsFont(.title).foregroundStyle(DS.Color.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AttendanceSectionView(jobId: jobId, onChanged: onChanged)
            }
        }
    }
}
