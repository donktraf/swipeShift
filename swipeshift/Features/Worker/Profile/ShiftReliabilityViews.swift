//
//  ShiftReliabilityViews.swift
//  swipeShift
//
//  Worker-Seite der Zuverlaessigkeit: "Cancel shift" (mit Warnung bei < 24 h), erfasste Anwesenheit mit
//  einmaligem Einspruch ("Dispute") und die eigene Zuverlaessigkeits-Karte fuer das Profil.
//

import SwiftUI

// MARK: - Farben

extension AttendanceStatus {
    var color: Color {
        switch self {
        case .attended: return .green
        case .late:     return .orange
        case .noShow:   return .red
        }
    }
}

// MARK: - Cancel Shift

/// Button "Cancel shift" + Bestaetigung. Bei < 24 h bis Start steht der Hinweis auf die kurzfristige Stornierung im Dialog.
struct CancelShiftButton: View {
    let applyId: String
    let jobTitle: String
    let lateIfCancelledNow: Bool
    /// Wird nach erfolgreicher Stornierung aufgerufen (Parameter: war kurzfristig)
    let onCancelled: (Bool) -> Void

    @State private var showConfirm = false
    @State private var isCancelling = false
    @State private var errorMessage: String?

    var body: some View {
        Button { showConfirm = true } label: {
            Text(isCancelling ? "Cancelling…" : "Cancel shift")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(isCancelling)
        .alert("Cancel this shift?", isPresented: $showConfirm) {
            Button("Cancel shift", role: .destructive) { Task { await cancel() } }
            Button("Keep shift", role: .cancel) {}
        } message: {
            Text(lateIfCancelledNow
                 ? "\"\(jobTitle)\" starts in less than 24 hours. This counts as a late cancellation and employers can see it on your profile."
                 : "\"\(jobTitle)\" will be removed from your calendar and the employer will be notified.")
        }
        .alert("Could not cancel", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func cancel() async {
        isCancelling = true
        do {
            let late = try await APIClient.shared.cancelShift(applyId: applyId)
            isCancelling = false
            onCancelled(late)
        } catch {
            isCancelling = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Erfasste Anwesenheit + Einspruch

/// "Attendance: No-show" mit Einspruch-Button (einmalig) bzw. Stand des Einspruchs
struct AttendanceStatusRow: View {
    let item: WorkerApplicationItem
    let onChanged: () -> Void

    @State private var showDispute = false

    var body: some View {
        if let status = item.attendanceStatus {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: underReview ? "hourglass" : status.icon).foregroundColor(underReview ? .orange : status.color)
                    Text(underReview ? "Attendance: Under review (recorded: \(status.label))" : "Attendance: \(status.label)")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(underReview ? .orange : status.color)
                    if item.attendanceSource == "auto" {
                        Text("· recorded automatically").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    if item.canDispute == true {
                        Button("Dispute") { showDispute = true }
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(SS.primary)
                    }
                }
                if let note = disputeNote {
                    Text(note).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.bottom, 10)
            .sheet(isPresented: $showDispute) {
                DisputeSheet(applyId: item.id, jobTitle: item.jobTitle, status: status) { onChanged() }
            }
        }
    }

    private var underReview: Bool { item.disputeStatus == "pending" }

    private var disputeNote: String? {
        switch item.disputeStatus {
        case "pending":
            return "Your dispute is under review. This entry does not count until it is decided."
        case "resolved":
            return item.disputeResolution == "changed" ? "Your dispute was reviewed and the entry was changed." : "Your dispute was reviewed and the entry stays."
        default:
            return nil
        }
    }
}

struct DisputeSheet: View {
    static let maxLength = 300

    let applyId: String
    let jobTitle: String
    let status: AttendanceStatus
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("The employer recorded \"\(status.label)\" for \(jobTitle). If this is wrong, tell us what happened. You can dispute an entry only once, within 14 days, and our team will review it.")
                    .font(.system(size: 14)).foregroundColor(.secondary)
                Label("Your note is shared with the employer and our team.", systemImage: "eye")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)

                TextEditor(text: $note)
                    .frame(height: 130)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: note) { _, new in
                        if new.count > Self.maxLength { note = String(new.prefix(Self.maxLength)) }
                    }
                HStack {
                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 12)).foregroundColor(.red)
                    }
                    Spacer()
                    Text("\(note.count)/\(Self.maxLength)").font(.system(size: 12)).foregroundColor(.secondary)
                }

                Button { Task { await submit() } } label: {
                    Text(isSending ? "Sending…" : "Send dispute").frame(maxWidth: .infinity)
                }
                .buttonStyle(SSPrimaryButtonStyle())
                .disabled(trimmed.isEmpty || isSending)
                Spacer()
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Dispute attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func submit() async {
        isSending = true; errorMessage = nil
        do {
            try await APIClient.shared.disputeAttendance(applyId: applyId, note: trimmed)
            isSending = false
            onSubmitted()
            dismiss()
        } catch {
            isSending = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Eigene Zuverlaessigkeit (Profil)

/// Zeigt dem Worker seinen eigenen Wert (letzte 12 Monate). Employer sehen ihn auf Bewerbungen, andere Worker nie.
struct WorkerReliabilityCard: View {
    @State private var summary: ReliabilitySummary?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundColor(SS.primary)
                Text("Your reliability").font(.system(size: 14, weight: .bold))
                Spacer()
            }
            if let summary {
                Text(summary.text).font(.system(size: 14, weight: .semibold))
                Text(summary.isNew
                     ? "Your show-up rate appears after 3 finished shifts. Employers see this on your applications."
                     : "Based on your finished shifts in the last 12 months. Employers see this on your applications.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Text("Cancel at least 24 hours before a shift to avoid a late cancellation.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else if failed {
                Text("Could not load your reliability.").font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: SS.cardRadius))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .task {
            do { summary = try await APIClient.shared.fetchWorkerReliability() }
            catch { failed = true }
        }
    }
}

/// Eine Zeile "Attendance: ..." fuer Detail-Ansichten (Kalender) — Showed up / Late / No-show / Under review
struct AttendanceInfoRow: View {
    let attendance: String?
    let disputeStatus: String?

    var body: some View {
        if let status = attendance.flatMap(AttendanceStatus.init(rawValue:)) {
            let review = disputeStatus == "pending"
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield").foregroundColor(SS.primary).frame(width: 20)
                Text("Attendance").font(.system(size: 14)).foregroundColor(.secondary)
                Spacer(minLength: 12)
                Text(review ? "Under review" : status.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(review ? .orange : status.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
        }
    }
}
