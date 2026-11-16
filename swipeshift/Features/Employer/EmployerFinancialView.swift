//
//  EmployerFinancialView.swift
//  swipeShift
//

import SwiftUI

// MARK: - EmployerFinancialView

struct EmployerFinancialView: View {
    @State private var financials: EmployerFinancialsDTO? = nil
    @State private var isLoading  = true
    @State private var loadFailed = false
    @State private var showBreakdown = false
    @State private var period: FinancialPeriod = .default

    private var maxBarValue: Double {
        financials?.chartData.map { $0.upcoming + $0.completed + $0.paidOut }.max() ?? 1
    }

    var body: some View {
        SubScreenShell(title: "Financial Overview") {
            VStack(spacing: 20) {
                // Picker bleibt beim Laden sichtbar, damit der Zeitraum direkt wieder wechselbar ist
                FinancialPeriodPicker(period: $period).padding(.horizontal, 16)

                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let f = financials {
                    summaryGrid(f).padding(.horizontal, 16)
                    barChartSection(f)
                    jobListSection(f)
                    breakdownButton
                    Spacer().frame(height: 20)
                } else if loadFailed {
                    errorState
                } else {
                    emptyState
                }
            }
        }
        // task(id:) bricht laufende Requests bei Zeitraum-Wechsel ab → keine veralteten Antworten
        .task(id: period) { await load() }
        .sheet(isPresented: $showBreakdown) {
            if let f = financials { BreakdownSheet(financials: f) }
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            let result = try await APIClient.shared.fetchEmployerFinancials(period: period)
            guard !Task.isCancelled else { return }
            financials = result
        } catch {
            // Zeitraum gewechselt → alter Request abgebrochen, neuer laeuft bereits
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            print("EmployerFinancialView: load error:", error)
            financials = nil
            loadFailed = true
        }
        isLoading = false
    }

    // MARK: - Summary Grid

    private func summaryGrid(_ f: EmployerFinancialsDTO) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            EmployerStatCard(label: "Total Spending",     value: "€\(Int(f.totalSpending))",    icon: "eurosign.circle.fill",   color: SS.primary)
            EmployerStatCard(label: "Upcoming Payments",  value: "€\(Int(f.upcomingPayments))", icon: "clock.fill",             color: .orange)
            EmployerStatCard(label: "Completed Jobs",     value: "\(f.completedJobsCount)",     icon: "checkmark.circle.fill",  color: .green)
            EmployerStatCard(label: "Monthly Spend",      value: "€\(Int(f.monthlySpend))",     icon: "calendar.circle.fill",   color: .teal)
        }
    }

    // MARK: - Bar Chart

    private func barChartSection(_ f: EmployerFinancialsDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                legendDot(.orange,   "Upcoming")
                legendDot(SS.primary, "Completed")
                legendDot(.teal,     "Paid Out")
                Spacer()
            }
            .padding(.horizontal, 4)

            if f.chartData.allSatisfy({ $0.upcoming + $0.completed + $0.paidOut == 0 }) {
                Text("No data for the selected period.")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                // Viele Balken (z.B. 30 Tage) → engerer Abstand, nur jedes n-te Label
                let barSpacing: CGFloat = f.chartData.count > 12 ? 2 : 6
                let labelEvery = max(1, Int((Double(f.chartData.count) / 8).rounded(.up)))
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(f.chartData.enumerated()), id: \.offset) { index, day in
                        let total = day.upcoming + day.completed + day.paidOut
                        VStack(spacing: 2) {
                            GeometryReader { geo in
                                VStack(spacing: 1) {
                                    Spacer(minLength: 0)
                                    VStack(spacing: 0) {
                                        barSegment(.orange,    day.upcoming,  maxBarValue, geo.size.height)
                                        barSegment(SS.primary, day.completed, maxBarValue, geo.size.height)
                                        barSegment(.teal,      day.paidOut,   maxBarValue, geo.size.height)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            .frame(height: 100)
                            Text(index % labelEvery == 0 ? day.day : " ")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                                .lineLimit(1).fixedSize()
                                .frame(maxWidth: .infinity)
                        }
                        .opacity(total > 0 ? 1 : 0.3)
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
        return Rectangle().fill(color).frame(height: max(height, value > 0 ? 2 : 0))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    // MARK: - Job Lists

    private func jobListSection(_ f: EmployerFinancialsDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !f.upcomingJobs.isEmpty {
                Text("Upcoming Payments")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 16)
                ForEach(f.upcomingJobs) { job in
                    FinancialJobCard(job: job)
                }
                .padding(.horizontal, 16)
            }

            if !f.completedJobsList.isEmpty {
                Text("Completed Jobs")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 16)
                ForEach(f.completedJobsList) { job in
                    FinancialJobCard(job: job)
                }
                .padding(.horizontal, 16)
            }

            if f.upcomingJobs.isEmpty && f.completedJobsList.isEmpty {
                Text("No jobs yet.")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
        }
    }

    // MARK: - Breakdown Button

    private var breakdownButton: some View {
        Button { showBreakdown = true } label: {
            Label("View Breakdown", systemImage: "chart.bar.xaxis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SS.primary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Empty / Error

    private var errorState: some View {
        VStack(spacing: 12) {
            Text("Could not load financial data.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            Button("Retry") { Task { await load() } }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar").font(.system(size: 48)).foregroundColor(.white.opacity(0.3))
            Text("No financial data yet").font(.system(size: 16, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            Text("Your earnings and spending will appear here once you start posting jobs.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - FinancialJobCard

private struct FinancialJobCard: View {
    let job: FinancialJobDTO

    var body: some View {
        HStack(spacing: 12) {
            Text(job.logoEmoji)
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(Color.gray.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                Text(job.shiftText).font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("€\(Int(job.amount))").font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                Text(job.status == "completed" ? "Done" : "Upcoming")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(job.status == "completed" ? Color.green : Color.orange)
                    .clipShape(Capsule())
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
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
                Spacer()
            }
            Text(value).font(.system(size: 22, weight: .bold)).foregroundColor(.primary)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
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
    let financials: EmployerFinancialsDTO

    private enum BreakdownMode: String, CaseIterable {
        case byStatus = "By Status"
        case byCategory = "By Category"
    }
    @State private var mode: BreakdownMode = .byStatus

    private var rows: [(String, Double, Color)] {
        if mode == .byStatus {
            return [
                ("Upcoming",  financials.upcomingPayments,   .orange),
                ("Completed", financials.totalSpending,      SS.primary),
                ("Paid Out",  financials.paidOut,            .teal),
            ].filter { $0.1 > 0 }
        } else {
            let colors: [Color] = [.purple, .blue, .orange, .green, .pink, .teal]
            return financials.byCategory.sorted { $0.value > $1.value }.enumerated().map { i, pair in
                (pair.key, pair.value, colors[i % colors.count])
            }
        }
    }
    private var totalAmount: Double { rows.reduce(0) { $0 + $1.1 } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Picker("", selection: $mode) {
                        ForEach(BreakdownMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 20)

                    if rows.isEmpty {
                        Text("No data available.").foregroundColor(.secondary).padding(.vertical, 32)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(rows, id: \.0) { (label, amount, color) in
                                breakdownRow(label: label, amount: amount, color: color)
                                if label != rows.last?.0 { Divider().padding(.leading, 16) }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)

                        HStack {
                            Text("Total").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("€\(Int(totalAmount))").font(.system(size: 15, weight: .bold))
                        }
                        .padding(.horizontal, 24).foregroundColor(.primary)
                    }
                }
                .padding(.top, 8).padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("View Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func breakdownRow(label: String, amount: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10).padding(.leading, 16)
            Text(label).font(.system(size: 14)).foregroundColor(.primary)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.12)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: totalAmount > 0 ? geo.size.width * CGFloat(amount / totalAmount) : 0, height: 6)
                }
            }
            .frame(width: 80, height: 6)
            Text("€\(Int(amount))").font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                .frame(width: 58, alignment: .trailing).padding(.trailing, 16)
        }
        .padding(.vertical, 14)
    }
}
