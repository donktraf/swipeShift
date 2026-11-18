//
//  WorkerCalendarDetailSheet.swift
//  swipeShift
//
//  Detail-Sheet beim Tippen auf einen Kalender-Eintrag: Zeit, Ort, Arbeitgeber, Bezahlung,
//  Zahlungsstatus, Stornierungsgrund, Overlap-Warnung + "View Job Details" / "Open Chat".
//

import SwiftUI

// MARK: - Detail Sheet (Tippen auf Eintrag)

struct CalendarEntryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: CalendarEntry
    let onViewJob: () -> Void
    let onOpenChat: () -> Void
    /// Nach erfolgreichem Schicht-Storno (Kalender neu laden)
    var onCancelled: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if entry.hasConflict { conflictWarning }
                    if entry.status == .cancelled { cancellationBox }
                    detailsCard
                    if let notes = entry.jobNotes { notesCard(notes) }
                    actions
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Shift Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(entry.logoEmoji)
                .font(.system(size: 26))
                .frame(width: 50, height: 50)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.system(size: 17, weight: .bold))
                CalendarStatusBadge(status: entry.status)
            }
            Spacer()
        }
    }

    private var conflictWarning: some View {
        Label("This shift overlaps with another job in your calendar. Please check your schedule.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var cancellationBox: some View {
        Label(entry.cancellationReason ?? "This job was cancelled.", systemImage: "xmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow(icon: "calendar", label: "Date",
                      value: entry.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            Divider().padding(.leading, 44)
            detailRow(icon: "clock", label: "Time", value: entry.timeLabel)
            Divider().padding(.leading, 44)
            detailRow(icon: "mappin.and.ellipse", label: "Location", value: entry.location)
            if let miles = entry.distanceMiles {
                Divider().padding(.leading, 44)
                detailRow(icon: "location", label: "Distance", value: String(format: "%.1f mi away", miles))
            }
            if let category = entry.category {
                Divider().padding(.leading, 44)
                detailRow(icon: "tag", label: "Category", value: category)
            }
            Divider().padding(.leading, 44)
            detailRow(icon: "building.2", label: "Employer", value: entry.company)
            Divider().padding(.leading, 44)
            detailRow(icon: "dollarsign.circle", label: "Pay", value: payValue)
            if entry.status == .completed, entry.attendance != nil {
                Divider().padding(.leading, 44)
                AttendanceInfoRow(attendance: entry.attendance, disputeStatus: entry.disputeStatus)
            }
            if let payment = entry.paymentStatus {
                Divider().padding(.leading, 44)
                detailRow(icon: payment == "paid" ? "checkmark.seal" : "hourglass",
                          label: "Payment", value: payment == "paid" ? "Paid" : "Pending payout")
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Hinweise des Employers (Treffpunkt, mitbringen, ...)
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notes from the employer", systemImage: "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SS.primary)
            Text(notes)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var payValue: String {
        guard let earnings = entry.earnings, earnings > 0 else { return entry.payText }
        return "\(entry.payText) · \(Money.format(earnings)) for this shift"
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundColor(SS.primary).frame(width: 20)
            Text(label).font(.system(size: 14)).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onViewJob) {
                Label("View Job Details", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SSPrimaryButtonStyle())

            if entry.canOpenChat {
                Button(action: onOpenChat) {
                    Label("Open Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(SS.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            if entry.canCancel {
                CancelShiftButton(applyId: entry.id, jobTitle: entry.title, lateIfCancelledNow: entry.lateIfCancelledNow) { _ in
                    onCancelled()
                    dismiss()
                }
            }
        }
    }
}
