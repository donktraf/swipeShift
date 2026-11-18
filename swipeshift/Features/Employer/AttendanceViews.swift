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
        if summary.isNew { return summary.noShows > 0 || summary.lateCancellations > 0 ? .orange : .secondary }
        if let rate = summary.showUpRate, rate >= 90, summary.noShows == 0 { return .green }
        if let rate = summary.showUpRate, rate >= 75 { return .orange }
        return .red
    }

    var body: some View {
        Label(summary.text, systemImage: "checkmark.shield")
            .font(.system(size: font, weight: .medium))
            .foregroundColor(tint)
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
                card(response)
            }
        }
        .task { await load() }
        .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func card(_ response: JobAttendanceResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record attendance")
                .font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
            Text(response.guidance)
                .font(.system(size: 12)).foregroundColor(.secondary)
            if let deadline = response.deadline, response.workers.contains(where: { $0.pending }) {
                Text("If you don't record anything by \(deadline.formatted(date: .abbreviated, time: .shortened)), workers count as showed up.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(response.workers) { worker in
                Divider()
                workerRow(worker)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: SS.cardRadius))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private func workerRow(_ worker: AttendanceWorker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(worker.name).font(.system(size: 14, weight: .semibold))
                Spacer()
                if worker.pending {
                    Text("Needs your input")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12)).clipShape(Capsule())
                } else if worker.attendanceSource == "auto" {
                    Text("Recorded automatically").font(.system(size: 11)).foregroundColor(.secondary)
                } else if worker.attendanceSource == "admin" {
                    Text("Decided by SwipeShift").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(AttendanceStatus.allCases) { status in
                    optionButton(status, worker: worker)
                }
            }
            if worker.disputeStatus == "pending" {
                Text("The worker disputed this entry\(worker.disputeNote.map { ": \"\($0)\"" } ?? ""). It is under review and can't be changed now.")
                    .font(.system(size: 11)).foregroundColor(.orange)
            } else if worker.disputeStatus == "resolved" {
                Text("The worker's dispute was reviewed.").font(.system(size: 11)).foregroundColor(.secondary)
            } else if !worker.canRecord {
                Text("The 48-hour window to record attendance has ended.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    private func optionButton(_ status: AttendanceStatus, worker: AttendanceWorker) -> some View {
        let selected = worker.status == status
        return Button {
            Task { await record(worker, status) }
        } label: {
            Label(status.label, systemImage: status.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .white : status.color)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(selected ? status.color : status.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!worker.canRecord || workingId == worker.applyId)
        .opacity(worker.canRecord ? 1 : 0.5)
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
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}

// MARK: - Screen

struct AttendanceScreen: View {
    let jobId: String
    let jobTitle: String
    var onChanged: () -> Void = {}

    var body: some View {
        SubScreenShell(title: "Attendance") {
            VStack(spacing: 16) {
                Text(jobTitle)
                    .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
                AttendanceSectionView(jobId: jobId, onChanged: onChanged)
            }
        }
    }
}
