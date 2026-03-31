//
//  EmployerFinancialView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Models

private enum FinancialPeriod: String, CaseIterable {
    case thisMonth   = "This Month"
    case last3Months = "Last 3 Months"
    case thisYear    = "This Year"
    case allTime     = "All Time"
}

private struct DailySpend: Identifiable {
    let id = UUID()
    let day: String        // "Mo", "Di" usw.
    let upcoming: Double
    let completed: Double
    let paidOut: Double
    var total: Double { upcoming + completed + paidOut }
}

private struct PaymentRow: Identifiable {
    let id = UUID()
    let workerName: String
    let jobTitle: String
    let hours: Double
    let hourlyRate: Double
    var total: Double { hours * hourlyRate }
    let isPaid: Bool
    let logoEmoji: String
    let shiftDate: String
}

private enum BreakdownMode: String, CaseIterable {
    case byStatus   = "By Status"
    case byCategory = "By Category"
}

// MARK: - EmployerFinancialView

struct EmployerFinancialView: View {
    @State private var selectedPeriod: FinancialPeriod = .thisMonth
    @State private var showBreakdown = false

    // TODO: aus Backend laden (GET /employer/financials)
    private let totalSpending:    Double = 3_840
    private let upcomingPayments: Double = 960
    private let completedJobs:    Int    = 12
    private let paidOut:          Double = 2_880

    private let chartData: [DailySpend] = mockChartData
    private let paymentRows: [PaymentRow] = mockPaymentRows

    private var maxBarValue: Double {
        chartData.map(\.total).max() ?? 1
    }

    var body: some View {
        SubScreenShell(title: "Financial Overview") {
            VStack(spacing: 20) {
                // Period Picker
                periodPicker
                    .padding(.horizontal, 16)

                // Summary Cards (2×2)
                summaryGrid
                    .padding(.horizontal, 16)

                // Bar Chart
                barChartSection

                // Payment List
                paymentListSection

                Spacer().frame(height: 20)
            }
        }
        .sheet(isPresented: $showBreakdown) {
            BreakdownSheet()
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Menu {
            ForEach(FinancialPeriod.allCases, id: \.self) { p in
                Button(p.rawValue) { selectedPeriod = p }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Text(selectedPeriod.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            EmployerStatCard(
                label: "Total Spending",
                value: "€\(Int(totalSpending))",
                icon: "eurosign.circle.fill",
                color: SS.primary
            )
            EmployerStatCard(
                label: "Upcoming Payments",
                value: "€\(Int(upcomingPayments))",
                icon: "clock.fill",
                color: .orange
            )
            EmployerStatCard(
                label: "Completed Jobs",
                value: "\(completedJobs)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            EmployerStatCard(
                label: "Paid Out",
                value: "€\(Int(paidOut))",
                icon: "arrow.up.circle.fill",
                color: .teal
            )
        }
    }

    // MARK: - Bar Chart

    private var barChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Legend
            HStack(spacing: 16) {
                legendDot(.orange,   "Upcoming")
                legendDot(SS.primary, "Completed")
                legendDot(.teal,     "Paid Out")
                Spacer()
            }
            .padding(.horizontal, 4)

            // Bars
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(chartData) { day in
                    VStack(spacing: 2) {
                        GeometryReader { geo in
                            VStack(spacing: 1) {
                                Spacer(minLength: 0)
                                // Stacked bars
                                VStack(spacing: 0) {
                                    barSegment(.orange,    day.upcoming,   maxBarValue, geo.size.height)
                                    barSegment(SS.primary, day.completed,  maxBarValue, geo.size.height)
                                    barSegment(.teal,      day.paidOut,    maxBarValue, geo.size.height)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .frame(height: 100)

                        Text(day.day)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private func barSegment(_ color: Color, _ value: Double, _ maxVal: Double, _ totalHeight: CGFloat) -> some View {
        let height = maxVal > 0 ? CGFloat(value / maxVal) * totalHeight : 0
        return Rectangle()
            .fill(color)
            .frame(height: max(height, value > 0 ? 2 : 0))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    // MARK: - Payment List

    private var paymentListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pending Payments")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(paymentRows.filter { !$0.isPaid }.count) open")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(paymentRows) { row in
                    PaymentRowCard(row: row)
                }
            }
            .padding(.horizontal, 16)

            // View Breakdown
            Button { showBreakdown = true } label: {
                Label("View Breakdown", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - PaymentRowCard

private struct PaymentRowCard: View {
    let row: PaymentRow

    var body: some View {
        HStack(spacing: 12) {
            Text(row.logoEmoji)
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(Color.gray.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.workerName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(row.jobTitle) · \(row.shiftDate)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(String(format: "%.1fh × €%.2f", row.hours, row.hourlyRate))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("€\(Int(row.total))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                if row.isPaid {
                    Text("Paid")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.green)
                        .clipShape(Capsule())
                } else {
                    Text("Pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - EmployerStatCard

private struct EmployerStatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Breakdown Sheet

private struct BreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: BreakdownMode = .byStatus

    private let byStatus: [(String, Double, Color)] = [
        ("Upcoming",  960,   .orange),
        ("Completed", 1_920, SS.primary),
        ("Paid Out",  2_880, .teal),
    ]
    private let byCategory: [(String, Double, Color)] = [
        ("Events",      1_540, .purple),
        ("Hospitality", 1_200, .blue),
        ("Logistics",     720, .orange),
        ("Retail",        380, .green),
    ]

    private var rows: [(String, Double, Color)] {
        mode == .byStatus ? byStatus : byCategory
    }
    private var totalAmount: Double { rows.reduce(0) { $0 + $1.1 } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Mode Toggle
                    Picker("", selection: $mode) {
                        ForEach(BreakdownMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    // Breakdown Rows
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.0) { (label, amount, color) in
                            breakdownRow(label: label, amount: amount, color: color)
                            if label != rows.last?.0 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // Total
                    HStack {
                        Text("Total")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("€\(Int(totalAmount))")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .padding(.horizontal, 24)
                    .foregroundColor(.primary)
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("View Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func breakdownRow(label: String, amount: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
                .padding(.leading, 16)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(amount / totalAmount), height: 6)
                }
            }
            .frame(width: 80, height: 6)

            Text("€\(Int(amount))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 58, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Mock Data

private let mockChartData: [DailySpend] = [
    DailySpend(day: "Mon", upcoming: 80,  completed: 200, paidOut: 160),
    DailySpend(day: "Tue", upcoming: 120, completed: 140, paidOut: 200),
    DailySpend(day: "Wed", upcoming: 60,  completed: 300, paidOut: 120),
    DailySpend(day: "Thu", upcoming: 200, completed: 180, paidOut: 240),
    DailySpend(day: "Fri", upcoming: 160, completed: 260, paidOut: 180),
    DailySpend(day: "Sat", upcoming: 220, completed: 320, paidOut: 280),
    DailySpend(day: "Sun", upcoming: 120, completed: 520, paidOut: 700),
]

private let mockPaymentRows: [PaymentRow] = [
    PaymentRow(workerName: "Jonas Weber",  jobTitle: "Event Staff",      hours: 8,  hourlyRate: 14.50, isPaid: false, logoEmoji: "🎪", shiftDate: "Mar 28"),
    PaymentRow(workerName: "Maria Schulz", jobTitle: "Bartender",        hours: 6,  hourlyRate: 16.00, isPaid: false, logoEmoji: "🍹", shiftDate: "Mar 28"),
    PaymentRow(workerName: "Lukas Bauer",  jobTitle: "Warehouse Worker", hours: 10, hourlyRate: 13.50, isPaid: true,  logoEmoji: "📦", shiftDate: "Mar 25"),
    PaymentRow(workerName: "Anna Müller",  jobTitle: "Cleaning Staff",   hours: 5,  hourlyRate: 13.00, isPaid: true,  logoEmoji: "🧹", shiftDate: "Mar 24"),
]
