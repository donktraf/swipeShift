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
    /// "paid" | "pending" | "no_show" (nicht berechnet) | "under_review" (No-Show-Einspruch, Zahlung angehalten)
    var paymentState: String? = nil

    var isNoShow: Bool { paymentState == "no_show" }
    var isUnderReview: Bool { paymentState == "under_review" }
    /// Bezahlbar = noch offen und weder No-Show noch unter Pruefung
    var isPayable: Bool { !isPaid && !isNoShow && !isUnderReview }

    var totalEarned: Double { hoursWorked * hourlyRate }
}

// MARK: - JobPaymentView

struct JobPaymentView: View {
    let jobId: String
    let jobTitle: String
    let jobEmoji: String
    let jobLocation: String

    @State private var workers: [PayableWorker] = []
    @State private var isLoading    = false
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

    private var totalAmount:    Double { workers.reduce(0) { $0 + $1.totalEarned } }
    private var paidAmount:     Double { paidWorkers.reduce(0) { $0 + $1.totalEarned } }
    private var remainingAmount: Double { unpaidWorkers.reduce(0) { $0 + $1.totalEarned } }

    private var allPaid: Bool { unpaidWorkers.isEmpty }
    private var payableCount: Int { workers.filter { !$0.isNoShow && !$0.isUnderReview }.count }

    // MARK: - Body

    var body: some View {
        SubScreenShell(title: "Job Payments") {
            VStack(spacing: 20) {
                jobHeader
                summaryBar
                // Anwesenheit nach Schichtende (blendet sich vor Schichtende aus)
                AttendanceSectionView(jobId: jobId)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let err = errorMessage {
                    VStack(spacing: 12) {
                        Text(err).font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button("Retry") { Task { await loadPayments() } }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
                    }
                    .padding(.top, 40)
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
                    Spacer().frame(height: 20)
                }
            }
        }
        .task { await loadPayments() }
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
                Text("You are about to pay \(Money.format(w.totalEarned, fractionDigits: 2)) to \(w.name) for \(w.hoursWorked, specifier: "%.0f") hours.")
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
            Text("You are about to pay \(Money.format(remainingAmount, fractionDigits: 2)) to \(unpaidWorkers.count) worker\(unpaidWorkers.count == 1 ? "" : "s"). No-shows are not billed.")
        }
        // Pay remaining confirmation
        .alert("Pay Remaining Workers?", isPresented: $showPayRemainingConfirm) {
            Button("Confirm Payment", role: .none) {
                markRemainingPaid()
                showPayRemainingConfirm = false
            }
            Button("Cancel", role: .cancel) { showPayRemainingConfirm = false }
        } message: {
            Text("You are about to pay \(Money.format(remainingAmount, fractionDigits: 2)) to \(unpaidWorkers.count) remaining worker\(unpaidWorkers.count == 1 ? "" : "s").")
        }
    }

    // MARK: - Job Header

    private var jobHeader: some View {
        HStack(spacing: 14) {
            Text(jobEmoji)
                .font(.system(size: 28))
                .frame(width: 54, height: 54)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(jobTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    Text(jobLocation)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryCell(label: "Total", value: Money.format(totalAmount), color: .white)
            Divider().frame(height: 36).opacity(0.2)
            summaryCell(label: "Paid", value: Money.format(paidAmount), color: .green)
            Divider().frame(height: 36).opacity(0.2)
            summaryCell(label: "Remaining", value: Money.format(remainingAmount), color: remainingAmount > 0 ? .orange : .green)
        }
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func summaryCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Worker Section

    private func workerSection(title: String, workers: [PayableWorker], isPaid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(workers) { worker in
                workerRow(worker)
                if worker.id != workers.last?.id {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func workerRow(_ worker: PayableWorker) -> some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(worker.isPaid ? Color.green.opacity(0.12) : SS.primary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Text(worker.avatarEmoji)
                    .font(.system(size: 20))
            }
            .padding(.leading, 14)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(worker.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(worker.shiftDate) · \(worker.hoursWorked, specifier: "%.0f")h × \(Money.hourly(worker.hourlyRate))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Amount + action
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.format(worker.totalEarned, fractionDigits: 2))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                if worker.isNoShow {
                    Text("No-show — not billed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                } else if worker.isUnderReview {
                    Text("Under review")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else if worker.isPaid {
                    Text("Paid")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                } else {
                    Button {
                        workerToPay = worker
                    } label: {
                        Text("Pay")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(SS.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 14)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Pay Action Button

    @ViewBuilder
    private var payActionButton: some View {
        if allPaid && !heldWorkers.isEmpty && paidWorkers.isEmpty {
            EmptyView()
        } else if allPaid {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("All workers have been paid")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

        } else if paidWorkers.isEmpty {
            Button { showPayAllConfirm = true } label: {
                Text("Pay All Workers  ·  \(Money.format(totalAmount))")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(SSPrimaryButtonStyle())
            .padding(.horizontal, 16)

        } else {
            Button { showPayRemainingConfirm = true } label: {
                Text("Pay Remaining \(unpaidWorkers.count) Worker\(unpaidWorkers.count == 1 ? "" : "s")  ·  \(Money.format(remainingAmount))")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(SSPrimaryButtonStyle())
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Data & API

    private func loadPayments() async {
        isLoading = true
        errorMessage = nil
        do {
            workers = try await APIClient.shared.fetchJobPayments(jobId: jobId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func markPaid(id: String) {
        withAnimation {
            if let i = workers.firstIndex(where: { $0.id == id }) {
                workers[i].isPaid = true
            }
        }
        Task { try? await APIClient.shared.payWorker(jobId: jobId, applyId: id) }
    }

    private func markAllPaid() {
        withAnimation { for i in workers.indices where workers[i].isPayable { workers[i].isPaid = true } }
        Task { try? await APIClient.shared.payAllWorkers(jobId: jobId) }
    }

    private func markRemainingPaid() {
        let unpaidIds = workers.filter { $0.isPayable }.map(\.id)
        withAnimation {
            for i in workers.indices where workers[i].isPayable { workers[i].isPaid = true }
        }
        Task {
            for applyId in unpaidIds {
                try? await APIClient.shared.payWorker(jobId: jobId, applyId: applyId)
            }
        }
    }
}
