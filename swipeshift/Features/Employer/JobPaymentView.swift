//
//  JobPaymentView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Models

struct PayableWorker: Identifiable, Decodable {
    let id: String          // applyId
    let name: String
    let avatarEmoji: String
    let jobTitle: String
    let shiftDate: String
    let hoursWorked: Double
    let hourlyRate: Double
    var isPaid: Bool
    /// Gebuchte Schichten dieses Workers (Stunden/Betrag gelten nur dafuer); fehlt bei aelteren Backends
    var bookedShifts: [BookedShift]? = nil
    /// "paid" | "pending" | "no_show" (nicht berechnet) | "under_review" (No-Show-Einspruch, Zahlung angehalten)
    var paymentState: String? = nil

    var isNoShow: Bool { paymentState == "no_show" }
    var isUnderReview: Bool { paymentState == "under_review" }
    /// Bezahlbar = noch offen und weder No-Show noch unter Pruefung
    var isPayable: Bool { !isPaid && !isNoShow && !isUnderReview }

    /// Lohn, den der Worker erhaelt (voller Stundenlohn, keine Abzuege)
    var totalEarned: Double { hoursWorked * hourlyRate }

    /// Plattform-Gebuehr + Gesamtbetrag fuer den Employer (Backend: wage/fee/total; Fallback nur fuer aeltere Antworten)
    var wage: Double? = nil
    var fee: Double? = nil
    var total: Double? = nil
    var feeAmount: Double { fee ?? 0 }
    var totalCharged: Double { total ?? totalEarned }
}

struct JobPaymentSummary: Decodable {
    let feePercent: Double
    let wages: Double
    let fees: Double
    let total: Double
    let paidTotal: Double
    let remainingWages: Double
    let remainingFees: Double
    let remainingTotal: Double
}

struct JobPaymentsResponse: Decodable {
    let workers: [PayableWorker]
    var summary: JobPaymentSummary? = nil
}

// MARK: - JobPaymentView

struct JobPaymentView: View {
    let jobId: String
    let jobTitle: String
    let jobEmoji: String
    let jobLocation: String

    @State private var workers: [PayableWorker] = []
    @State private var summary: JobPaymentSummary? = nil
    @ObservedObject private var feeConfig = FeeConfig.shared
    @State private var isLoading    = false
    @State private var isPaying     = false          // blockiert Doppel-Zahlungen waehrend ein Request laeuft
    @State private var payError: String? = nil       // Servermeldung bei fehlgeschlagener Zahlung
    @State private var errorMessage: String? = nil

    // Confirmation state
    @State private var workerToPay: PayableWorker? = nil
    @State private var showPayAllConfirm = false
    @State private var showPayRemainingConfirm = false

    // MARK: - Computed

    private var unpaidWorkers: [PayableWorker] { workers.filter { $0.isPayable } }
    private var paidWorkers:   [PayableWorker] { workers.filter {  $0.isPaid } }
    /// No-Show (nicht berechnet) bzw. No-Show unter Einspruch (Zahlung angehalten)
    private var heldWorkers:   [PayableWorker] { workers.filter { $0.isNoShow || $0.isUnderReview } }

    // Alle Betraege inkl. Plattform-Gebuehr (Lohn + Gebuehr); Worker erhaelt davon nur den Lohn
    private var billedWorkers:  [PayableWorker] { workers.filter { !$0.isNoShow && !$0.isUnderReview } }
    private var totalAmount:    Double { PlatformFees.roundMoney(billedWorkers.reduce(0) { $0 + $1.totalCharged }) }
    private var paidAmount:     Double { PlatformFees.roundMoney(paidWorkers.reduce(0) { $0 + $1.totalCharged }) }
    private var remainingAmount: Double { PlatformFees.roundMoney(unpaidWorkers.reduce(0) { $0 + $1.totalCharged }) }
    private var remainingWages: Double { PlatformFees.roundMoney(unpaidWorkers.reduce(0) { $0 + $1.totalEarned }) }
    private var remainingFees:  Double { PlatformFees.roundMoney(unpaidWorkers.reduce(0) { $0 + $1.feeAmount }) }
    private var totalWages:     Double { PlatformFees.roundMoney(billedWorkers.reduce(0) { $0 + $1.totalEarned }) }
    private var totalFees:      Double { PlatformFees.roundMoney(billedWorkers.reduce(0) { $0 + $1.feeAmount }) }
    private var onHoldAmount:   Double { PlatformFees.roundMoney(workers.filter { $0.isUnderReview }.reduce(0) { $0 + $1.totalCharged }) }
    private var feePercent:     Double { summary?.feePercent ?? feeConfig.platformFeePercent }

    private var allPaid: Bool { unpaidWorkers.isEmpty }
    private var payableCount: Int { workers.filter { !$0.isNoShow && !$0.isUnderReview }.count }

    // MARK: - Body

    var body: some View {
        SubScreenShell(title: "Job Payments", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                jobHeader
                summaryBar
                if !billedWorkers.isEmpty { feeBreakdownBar }
                // Anwesenheit nach Schichtende (blendet sich vor Schichtende aus)
                AttendanceSectionView(jobId: jobId)

                if isLoading && workers.isEmpty {
                    skeleton
                } else if let err = errorMessage {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(err).dsFont(.callout).foregroundStyle(DS.Color.text2)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await loadPayments() } }
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xl)
                } else {
                    if !unpaidWorkers.isEmpty {
                        workerSection(title: "Pending Payment", workers: unpaidWorkers, isPaid: false)
                    }
                    if !heldWorkers.isEmpty {
                        workerSection(title: "Not billed / On hold", workers: heldWorkers, isPaid: false)
                    }
                    if !paidWorkers.isEmpty {
                        workerSection(title: "Paid", workers: paidWorkers, isPaid: true)
                    }
                    if payableCount > 0 { payActionButton }
                }
            }
        }
        .refreshable { await loadPayments(showSpinner: false) }
        .task {
            await feeConfig.refresh()
            await loadPayments()
        }
        .alert("Payment failed", isPresented: Binding(get: { payError != nil }, set: { if !$0 { payError = nil } })) {
            Button("OK", role: .cancel) { payError = nil }
        } message: {
            Text(payError ?? "")
        }
        // Pay single worker confirmation
        .alert("Pay \(workerToPay?.name ?? "")?", isPresented: Binding(
            get:  { workerToPay != nil },
            set:  { if !$0 { workerToPay = nil } }
        )) {
            Button("Confirm Payment", role: .none) {
                if let w = workerToPay { markPaid(id: w.id) }
                workerToPay = nil
            }
            Button("Cancel", role: .cancel) { workerToPay = nil }
        } message: {
            if let w = workerToPay {
                Text("You are about to pay \(Money.format(w.totalCharged, fractionDigits: 2)) for \(w.name): \(Money.format(w.totalEarned, fractionDigits: 2)) wages (\(w.hoursWorked, specifier: "%.0f") hours) + \(Money.format(w.feeAmount, fractionDigits: 2)) platform fee (\(PlatformFees.percentLabel(feePercent))). The worker receives the full wages.")
            }
        }
        // Pay all confirmation
        .alert("Pay All Workers?", isPresented: $showPayAllConfirm) {
            Button("Confirm Payment", role: .none) {
                markAllPaid()
                showPayAllConfirm = false
            }
            Button("Cancel", role: .cancel) { showPayAllConfirm = false }
        } message: {
            Text("You are about to pay \(Money.format(remainingAmount, fractionDigits: 2)) for \(unpaidWorkers.count) worker\(unpaidWorkers.count == 1 ? "" : "s"): \(Money.format(remainingWages, fractionDigits: 2)) wages + \(Money.format(remainingFees, fractionDigits: 2)) platform fee (\(PlatformFees.percentLabel(feePercent))). Workers receive the full wages. No-shows are not billed.")
        }
        // Pay remaining confirmation
        .alert("Pay Remaining Workers?", isPresented: $showPayRemainingConfirm) {
            Button("Confirm Payment", role: .none) {
                markRemainingPaid()
                showPayRemainingConfirm = false
            }
            Button("Cancel", role: .cancel) { showPayRemainingConfirm = false }
        } message: {
            Text("You are about to pay \(Money.format(remainingAmount, fractionDigits: 2)) for \(unpaidWorkers.count) remaining worker\(unpaidWorkers.count == 1 ? "" : "s"): \(Money.format(remainingWages, fractionDigits: 2)) wages + \(Money.format(remainingFees, fractionDigits: 2)) platform fee (\(PlatformFees.percentLabel(feePercent))).")
        }
    }

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSSkeletonBlock(height: 84, radius: DS.Radius.tile)
            DSSkeletonBlock(height: 64, radius: DS.Radius.card)
            DSSkeletonBlock(height: 64, radius: DS.Radius.card)
        }
        .accessibilityLabel("Loading payments")
    }

    // MARK: - Job Header

    private var jobHeader: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: jobEmoji, size: 54)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(jobTitle)
                    .dsFont(.title)
                    .foregroundStyle(DS.Color.text)
                Label(jobLocation, systemImage: "mappin.circle")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
            }
            Spacer()
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            DSTile(label: "Total", value: Money.format(totalAmount), tone: .primary)
            DSTile(label: "Paid", value: Money.format(paidAmount), tone: .success)
            DSTile(label: "Remaining", value: Money.format(remainingAmount), tone: remainingAmount > 0 ? .warning : .success)
        }
    }

    /// Job-Summen: Lohn (geht komplett an die Worker) + Plattform-Gebuehr = Gesamt
    private var feeBreakdownBar: some View {
        DSSection("Breakdown") {
            VStack(spacing: 0) {
                feeLine("Worker wages", Money.format(totalWages, fractionDigits: 2))
                feeLine("Platform fee (\(PlatformFees.percentLabel(feePercent)))", Money.format(totalFees, fractionDigits: 2))
                feeLine("Total incl. fee", Money.format(totalAmount, fractionDigits: 2), bold: true)
                if onHoldAmount > 0 {
                    feeLine("On hold (no-show under review, not billed yet)", Money.format(onHoldAmount, fractionDigits: 2))
                }
            }
        }
    }

    private func feeLine(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(DS.Font.make(14, bold ? .bold : .regular, relativeTo: .callout))
            Spacer(minLength: DS.Spacing.sm)
            Text(value).font(DS.Font.make(14, bold ? .bold : .semibold, relativeTo: .callout))
        }
        .foregroundStyle(bold ? DS.Color.text : DS.Color.text2)
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: 36)
        .overlay(alignment: .top) { DSDivider() }
    }

    // MARK: - Worker Section

    private func workerSection(title: String, workers: [PayableWorker], isPaid: Bool) -> some View {
        DSSection(title) {
            ForEach(workers) { worker in
                workerRow(worker)
            }
        }
    }

    private func workerRow(_ worker: PayableWorker) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: worker.avatarEmoji, size: 42, shape: .circle, tone: worker.isPaid ? .success : .primary)

            // Info
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(worker.name)
                    .font(DS.Font.make(15, .semibold, relativeTo: .callout))
                    .foregroundStyle(DS.Color.text)
                Text("\(worker.bookedShifts?.cardLabel ?? worker.shiftDate) · \(worker.hoursWorked, specifier: "%.1f")h × \(Money.hourly(worker.hourlyRate))")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
            }

            Spacer(minLength: DS.Spacing.xs)

            // Amount + action
            VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                Text(Money.format(worker.totalCharged, fractionDigits: 2))
                    .font(DS.Font.make(16, .bold, relativeTo: .callout))
                    .foregroundStyle(DS.Color.text)
                if !worker.isNoShow && worker.fee != nil {
                    Text("incl. \(Money.format(worker.feeAmount, fractionDigits: 2)) fee")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }

                if worker.isNoShow {
                    DSBadge("No-show — not billed", .cancelled)
                } else if worker.isUnderReview {
                    DSBadge("Under review", .tone(.warning))
                } else if worker.isPaid {
                    DSBadge("Paid", .tone(.success))
                } else {
                    Button {
                        workerToPay = worker
                    } label: {
                        Text("Pay")
                    }
                    .buttonStyle(.ds(.primary, size: .medium, fullWidth: false))
                    .disabled(isPaying)
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .overlay(alignment: .top) { DSDivider() }
    }

    // MARK: - Pay Action Button

    @ViewBuilder
    private var payActionButton: some View {
        if allPaid && !heldWorkers.isEmpty && paidWorkers.isEmpty {
            EmptyView()
        } else if allPaid {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                Text("All workers have been paid")
                    .dsFont(.headline)
            }
            .foregroundStyle(DS.Color.success)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(DS.Color.successSoft, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))

        } else if paidWorkers.isEmpty {
            Button { showPayAllConfirm = true } label: {
                Text("Pay All Workers  ·  \(Money.format(remainingAmount, fractionDigits: 2)) incl. fee")
            }
            .buttonStyle(.ds(.primary))
            .disabled(isPaying)

        } else {
            Button { showPayRemainingConfirm = true } label: {
                Text("Pay Remaining \(unpaidWorkers.count) Worker\(unpaidWorkers.count == 1 ? "" : "s")  ·  \(Money.format(remainingAmount, fractionDigits: 2)) incl. fee")
            }
            .buttonStyle(.ds(.primary))
            .disabled(isPaying)
        }
    }

    // MARK: - Data & API

    private func loadPayments(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        do {
            let response = try await APIClient.shared.fetchJobPayments(jobId: jobId)
            workers = response.workers
            summary = response.summary
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Fuehrt eine oder mehrere Zahlungs-Requests aus: kein Doppel-Tippen (isPaying), Serverfehler im Alert,
    /// danach immer neu laden, damit die Anzeige dem Serverstand entspricht (kein optimistisches "Paid").
    private func runPayment(_ requests: @escaping () async throws -> Void) {
        guard !isPaying else { return }
        isPaying = true
        Task {
            do {
                try await requests()
                DS.Haptics.success()
            } catch {
                payError = error.localizedDescription
            }
            await loadPayments(showSpinner: false)
            isPaying = false
        }
    }

    private func markPaid(id: String) {
        runPayment { try await APIClient.shared.payWorker(jobId: jobId, applyId: id) }
    }

    private func markAllPaid() {
        runPayment { try await APIClient.shared.payAllWorkers(jobId: jobId) }
    }

    private func markRemainingPaid() {
        let unpaidIds = workers.filter { $0.isPayable }.map(\.id)
        runPayment {
            for applyId in unpaidIds {
                try await APIClient.shared.payWorker(jobId: jobId, applyId: applyId)
            }
        }
    }
}
