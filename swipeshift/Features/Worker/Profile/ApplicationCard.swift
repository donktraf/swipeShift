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
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(item.logoEmoji)
                    .font(.system(size: 28)).frame(width: 48, height: 48)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.jobTitle)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    Text(item.company)
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    Text(metaLine)
                        .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.8))
                }
                Spacer()
                statusBadge
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            // Details
            HStack(spacing: 16) {
                Label(item.shiftText, systemImage: "calendar")
                Label(item.payText,   systemImage: "dollarsign.circle")
                Label(item.location,  systemImage: "mappin")
            }
            .font(.system(size: 12)).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .lineLimit(1)

            // Zahlungsstatus (nur abgeschlossene Jobs)
            if status == .completed, let payment = item.paymentStatus {
                Label(payment == "paid" ? "Paid" : "Payment pending",
                      systemImage: payment == "paid" ? "checkmark.seal.fill" : "hourglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(payment == "paid" ? .green : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }

            // Grund der Stornierung/Ablehnung (Employer-Angabe oder Standardtext vom Backend)
            if status == .cancelled, let reason = item.cancellationReason {
                Label(reason, systemImage: "xmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, item.lateCancellation == true ? 4 : 10)
            }
            if status == .cancelled, item.lateCancellation == true {
                Text("This counted as a late cancellation (less than 24 hours before the start).")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }

            // Vom Employer erfasste Anwesenheit (+ einmaliger Einspruch)
            if status == .completed {
                AttendanceStatusRow(item: item, onChanged: onChanged)
            }

            Divider().padding(.horizontal, 14)
            quickActions

            // Bestaetigte, noch nicht begonnene Schicht stornieren (< 24 h = kurzfristig, Warnung im Dialog)
            if status == .confirmed, item.canCancel == true {
                Divider().padding(.horizontal, 14)
                CancelShiftButton(applyId: item.id, jobTitle: item.jobTitle,
                                  lateIfCancelledNow: item.lateIfCancelledNow == true) { _ in onChanged() }
            }

            if status == .applied {
                Divider().padding(.horizontal, 14)
                Button {
                    showWithdrawAlert = true
                } label: {
                    Text(isWithdrawing ? "Withdrawing…" : "Withdraw Application")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
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
                Divider().padding(.horizontal, 14)
                Button { showRatingSheet = true } label: {
                    Label(hasReviewed ? "Review Submitted" : "Leave a Review",
                          systemImage: hasReviewed ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(hasReviewed ? .secondary : SS.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
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
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
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
        HStack(spacing: 0) {
            Button(action: onViewJob) {
                Label("View job", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(SS.primary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            if canChat {
                Divider().frame(height: 20)
                Button(action: onOpenChat) {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch status {
        case .confirmed: ("Confirmed", .green)
        case .applied:   ("Applied",   SS.primary)
        case .completed: ("Completed", .gray)
        case .cancelled: ("Cancelled", .red)
        }
        return Text(label)
            .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color).clipShape(Capsule())
    }
}
