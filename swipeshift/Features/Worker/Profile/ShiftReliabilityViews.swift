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
        case .attended: return DS.Color.success
        case .late:     return DS.Color.warning
        case .noShow:   return DS.Color.danger
        }
    }
}

// MARK: - Cancel Shift

/// Button "Cancel shift" + Bestaetigung. Bei < 24 h bis Start steht der Hinweis auf die kurzfristige Stornierung im Dialog.
struct CancelShiftButton: View {
    let applyId: String
    let jobTitle: String
    let lateIfCancelledNow: Bool
    /// Gesetzt = nur diese eine Schicht absagen (bei mehreren gebuchten Schichten); nil = ganze Buchung
    var shiftId: String? = nil
    /// Beschriftung der Schicht im Dialog ("Mon, Apr 28, 18:00–23:00")
    var shiftLabel: String? = nil
    /// Einzelne Schicht ist die letzte gebuchte → Bewerbung wird zurueckgezogen
    var isLastShift: Bool = false
    /// Wird nach erfolgreicher Stornierung aufgerufen (Parameter: war kurzfristig)
    let onCancelled: (Bool) -> Void

    @State private var showConfirm = false
    @State private var isCancelling = false
    @State private var errorMessage: String?

    var body: some View {
        Button { showConfirm = true } label: {
            Text(isCancelling ? "Cancelling…" : (shiftLabel.map { "Cancel shift · \($0)" } ?? "Cancel shift"))
        }
        .buttonStyle(.ds(.destructiveSoft, size: .medium))
        .disabled(isCancelling)
        .alert("Cancel this shift?", isPresented: $showConfirm) {
            Button("Cancel shift", role: .destructive) { Task { await cancel() } }
            Button("Keep shift", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .alert("Could not cancel", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var confirmMessage: String {
        let what = shiftLabel.map { "The shift \($0) of \"\(jobTitle)\"" } ?? "\"\(jobTitle)\""
        var text = lateIfCancelledNow
            ? "\(what) starts in less than 24 hours. This counts as a late cancellation and employers can see it on your profile."
            : "\(what) will be removed from your calendar and the employer will be notified."
        if shiftId != nil && isLastShift { text += "\n\nThis is your last shift — your application will be withdrawn." }
        return text
    }

    @MainActor
    private func cancel() async {
        isCancelling = true
        do {
            let late: Bool
            if let shiftId {
                late = try await APIClient.shared.cancelSingleShift(applyId: applyId, shiftId: shiftId)
            } else {
                late = try await APIClient.shared.cancelShift(applyId: applyId)
            }
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
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: underReview ? "hourglass" : status.icon)
                        .foregroundStyle(underReview ? DS.Color.warning : status.color)
                    Text(underReview ? "Attendance: Under review (recorded: \(status.label))" : "Attendance: \(status.label)")
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(underReview ? DS.Color.warning : status.color)
                    if item.attendanceSource == "auto" {
                        Text("· recorded automatically").dsFont(.caption).foregroundStyle(DS.Color.muted)
                    }
                    Spacer(minLength: 0)
                    if item.canDispute == true {
                        Button("Dispute") { showDispute = true }
                            .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(DS.Color.primaryText)
                            .frame(minHeight: 44)
                    }
                }
                if let note = disputeNote {
                    Text(note).dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("The employer recorded \"\(status.label)\" for \(jobTitle). If this is wrong, tell us what happened. You can dispute an entry only once, within 14 days, and our team will review it.")
                    .dsFont(.body).foregroundStyle(DS.Color.text2)
                Label("Your note is shared with the employer and our team.", systemImage: "eye")
                    .dsFont(.caption).foregroundStyle(DS.Color.muted)

                DSTextEditor("Your note", placeholder: "What happened?", text: $note, minLines: 4, maxLines: 8, maxLength: Self.maxLength)
                if let errorMessage {
                    Text(errorMessage).dsFont(.caption).foregroundStyle(DS.Color.danger)
                }

                Button { Task { await submit() } } label: {
                    Text(isSending ? "Sending…" : "Send dispute")
                }
                .buttonStyle(.ds(.primary))
                .disabled(trimmed.isEmpty || isSending)
                Spacer()
            }
            .padding(DS.Spacing.screenEdge)
            .dsBackground()
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
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(DS.Color.primary)
                    Text("Your reliability").dsFont(.headline).foregroundStyle(DS.Color.text)
                    Spacer()
                }
                if let summary {
                    Text(summary.text).dsFont(.callout).foregroundStyle(DS.Color.text)
                    Text(summary.isNew
                         ? "Your show-up rate appears after 3 finished shifts. Employers see this on your applications."
                         : "Based on your finished shifts in the last 12 months. Employers see this on your applications.")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                    Text("Cancel at least 24 hours before a shift to avoid a late cancellation.")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                } else if failed {
                    Text("Could not load your reliability.").dsFont(.caption).foregroundStyle(DS.Color.muted)
                } else {
                    DSSkeletonBlock(height: 14)
                    DSSkeletonBlock(height: 12)
                }
            }
        }
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
            DSRow("Attendance", systemIcon: "checkmark.shield", showsDivider: false) {
                Text(review ? "Under review" : status.label)
                    .font(DS.Font.make(15, .semibold))
                    .foregroundStyle(review ? DS.Color.warning : status.color)
            }
        }
    }
}
