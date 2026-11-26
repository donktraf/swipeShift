//
//  ApplicationCard.swift
//  swipeShift
//
//  Karte einer Bewerbung in JobApplicationsView: Bewerbungsdatum, Kategorie, Zahlungsstatus,
//  "View job" / "Chat", Withdraw bzw. Review je nach Status.
//

import SwiftUI

// MARK: - Application Card

struct ApplicationCard: View {
    let item:     WorkerApplicationItem
    let status:   ApplicationStatus
    let onWithdraw: () -> Void
    let onViewJob: () -> Void
    let onOpenChat: () -> Void
    /// Nach Schicht-Storno bzw. Einspruch: Liste neu laden
    var onChanged: () -> Void = {}

    @State private var showWithdrawAlert = false
    @State private var isWithdrawing     = false
    @State private var showRatingSheet   = false
    @State private var hasReviewed       = false

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // Header
                HStack(spacing: DS.Spacing.sm) {
                    DSAvatar(text: item.logoEmoji, size: 48, shape: .roundedSquare)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.jobTitle)
                            .dsFont(.headline).foregroundStyle(DS.Color.text)
                        Text(item.company)
                            .dsFont(.callout).foregroundStyle(DS.Color.text2)
                        Text(metaLine)
                            .dsFont(.caption).foregroundStyle(DS.Color.muted)
                    }
                    Spacer(minLength: DS.Spacing.xs)
                    statusBadge
                }

                DSDivider()

                // Details
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Label(item.bookedShifts?.cardLabel ?? item.shiftText, systemImage: "calendar")
                    Label(item.payText,   systemImage: "dollarsign.circle")
                    Label(item.location,  systemImage: "mappin")
                }
                .dsFont(.caption).foregroundStyle(DS.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

                // Zahlungsstatus (nur abgeschlossene Jobs)
                if status == .completed, let payment = item.paymentStatus {
                    Label(payment == "paid" ? "Paid" : "Payment pending",
                          systemImage: payment == "paid" ? "checkmark.seal.fill" : "hourglass")
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(payment == "paid" ? DS.Color.success : DS.Color.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Grund der Stornierung/Ablehnung (Employer-Angabe oder Standardtext vom Backend)
                if status == .cancelled, let reason = item.cancellationReason {
                    Label(reason, systemImage: "xmark.circle.fill")
                        .dsFont(.caption).foregroundStyle(DS.Color.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if status == .cancelled, item.lateCancellation == true {
                    Text("This counted as a late cancellation (less than 24 hours before the start).")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Vom Employer erfasste Anwesenheit (+ einmaliger Einspruch)
                if status == .completed {
                    AttendanceStatusRow(item: item, onChanged: onChanged)
                }

                quickActions

                // Bestaetigte, noch nicht begonnene Schicht(en) absagen (< 24 h = kurzfristig, Warnung im Dialog).
                // Mit gebuchten Schichten immer pro Schicht; ohne Schichtliste (Altbestand) die ganze Buchung.
                let booked = item.bookedShifts ?? []
                if status == .confirmed {
                    if booked.isEmpty {
                        if item.canCancel == true {
                            CancelShiftButton(applyId: item.id, jobTitle: item.jobTitle,
                                              lateIfCancelledNow: item.lateIfCancelledNow == true) { _ in onChanged() }
                        }
                    } else {
                        ForEach(booked.filter { $0.canCancel == true }) { shift in
                            CancelShiftButton(applyId: item.id, jobTitle: item.jobTitle,
                                              lateIfCancelledNow: shift.lateIfCancelledNow == true,
                                              shiftId: shift.id,
                                              shiftLabel: booked.count > 1 ? (shift.fullLabel.isEmpty ? shift.shortLabel : shift.fullLabel) : nil,
                                              isLastShift: booked.count == 1) { _ in onChanged() }
                        }
                    }
                }

                if status == .applied {
                    Button {
                        showWithdrawAlert = true
                    } label: {
                        Text(isWithdrawing ? "Withdrawing…" : "Withdraw Application")
                    }
                    .buttonStyle(.ds(.destructiveSoft, size: .medium))
                    .disabled(isWithdrawing)
                    .alert("Withdraw Application?", isPresented: $showWithdrawAlert) {
                        Button("Withdraw", role: .destructive) {
                            Task {
                                isWithdrawing = true
                                try? await APIClient.shared.withdrawApplication(applyId: item.id)
                                onWithdraw()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Your application for \(item.jobTitle) will be removed.")
                    }
                }

                if status == .completed {
                    Button { showRatingSheet = true } label: {
                        Label(hasReviewed ? "Review Submitted" : "Leave a Review",
                              systemImage: hasReviewed ? "star.fill" : "star")
                    }
                    .buttonStyle(.ds(.soft, size: .medium))
                    .disabled(hasReviewed)
                    .sheet(isPresented: $showRatingSheet) {
                        EmployerRatingSheet(
                            applyId:     item.id,
                            companyName: item.company,
                            jobTitle:    item.jobTitle
                        ) {
                            hasReviewed = true
                        }
                    }
                }
            }
        }
    }

    /// "Applied Nov 3 · Hospitality"
    private var metaLine: String {
        var parts = ["Applied \(item.appliedAt.formatted(ApplicationFormat.shortDate))"]
        if item.category != "—", !item.category.isEmpty { parts.append(item.category) }
        return parts.joined(separator: " · ")
    }

    /// "View job" immer, "Chat" nur nach Annahme und mit vorhandener Conversation
    private var canChat: Bool {
        item.conversationId != nil && (status == .confirmed || status == .completed)
    }

    private var quickActions: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button(action: onViewJob) {
                Label("View job", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.ds(.secondary, size: .medium))
            if canChat {
                Button(action: onOpenChat) {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.ds(.secondary, size: .medium))
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .confirmed: DSBadge("Confirmed", .upcoming)
        case .applied:   DSBadge("Applied", .tone(.primary))
        case .completed: DSBadge("Completed", .completed)
        case .cancelled: DSBadge("Cancelled", .cancelled)
        }
    }
}
