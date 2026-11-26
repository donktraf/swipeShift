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
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    header
                    if entry.hasConflict { conflictWarning }
                    if entry.status == .cancelled { cancellationBox }
                    detailsSection
                    if let notes = entry.jobNotes { notesSection(notes) }
                    actions
                }
                .padding(DS.Spacing.screenEdge)
            }
            .dsBackground()
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
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: entry.logoEmoji, size: 50, shape: .roundedSquare)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(entry.title).dsFont(.headline).foregroundStyle(DS.Color.text)
                CalendarStatusBadge(status: entry.status)
            }
            Spacer()
        }
    }

    private var conflictWarning: some View {
        Label("This shift overlaps with another job in your calendar. Please check your schedule.",
              systemImage: "exclamationmark.triangle.fill")
            .font(DS.Font.make(13, .medium, relativeTo: .footnote))
            .foregroundStyle(DS.Color.warning)
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.warningSoft, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    private var cancellationBox: some View {
        Label(entry.cancellationReason ?? "This job was cancelled.", systemImage: "xmark.circle.fill")
            .font(DS.Font.make(13, .medium, relativeTo: .footnote))
            .foregroundStyle(DS.Color.danger)
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.dangerSoft, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    private var detailsSection: some View {
        DSSection("Details") {
            detailRow(icon: "calendar", label: "Date",
                      value: entry.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()), first: true)
            detailRow(icon: "clock", label: "Time", value: entry.timeLabel)
            detailRow(icon: "mappin.and.ellipse", label: "Location", value: entry.location)
            if let miles = entry.distanceMiles {
                detailRow(icon: "location", label: "Distance", value: String(format: "%.1f mi away", miles))
            }
            if let category = entry.category {
                detailRow(icon: "tag", label: "Category", value: category)
            }
            detailRow(icon: "building.2", label: "Employer", value: entry.company)
            detailRow(icon: "dollarsign.circle", label: "Pay", value: payValue)
            if entry.status == .completed, entry.attendance != nil {
                AttendanceInfoRow(attendance: entry.attendance, disputeStatus: entry.disputeStatus)
            }
            if let payment = entry.paymentStatus {
                detailRow(icon: payment == "paid" ? "checkmark.seal" : "hourglass",
                          label: "Payment", value: payment == "paid" ? "Paid" : "Pending payout")
            }
        }
    }

    /// Hinweise des Employers (Treffpunkt, mitbringen, ...)
    private func notesSection(_ notes: String) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Label("Notes from the employer", systemImage: "note.text")
                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(DS.Color.primaryText)
                Text(notes)
                    .dsFont(.body).foregroundStyle(DS.Color.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var payValue: String {
        guard let earnings = entry.earnings, earnings > 0 else { return entry.payText }
        return "\(entry.payText) · \(Money.format(earnings)) for this shift"
    }

    private func detailRow(icon: String, label: String, value: String, first: Bool = false) -> some View {
        DSRow(label, systemIcon: icon, showsDivider: !first) {
            Text(value)
                .font(DS.Font.make(15, .medium)).foregroundStyle(DS.Color.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private var actions: some View {
        VStack(spacing: DS.Spacing.xs) {
            Button(action: onViewJob) {
                Label("View Job Details", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.ds(.primary))

            if entry.canOpenChat {
                Button(action: onOpenChat) {
                    Label("Open Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.ds(.soft))
            }

            if entry.canCancel {
                CancelShiftButton(applyId: entry.applyId, jobTitle: entry.title, lateIfCancelledNow: entry.lateIfCancelledNow,
                                  shiftId: entry.shiftId, shiftLabel: (entry.shiftId == nil || entry.isLastShift) ? nil : entry.shiftText,
                                  isLastShift: entry.isLastShift) { _ in
                    onCancelled()
                    dismiss()
                }
            }
        }
    }
}
