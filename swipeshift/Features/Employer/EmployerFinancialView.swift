//
//  EmployerFinancialView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Farben (Kacheln, Balken, Legende, Breakdown) – identisch zur Worker-Finanzansicht

private enum FinanceTone {
    static let upcoming: DS.Tone  = .success
    static let completed: DS.Tone = .primary
    static let paidOut: DS.Tone   = .warning
}

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
        SubScreenShell(title: "Financial Overview", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Picker bleibt beim Laden sichtbar, damit der Zeitraum direkt wieder wechselbar ist
                FinancialPeriodPicker(period: $period)

                if isLoading && financials == nil {
                    skeleton
                } else if let f = financials {
                    summaryGrid(f)
                    feeSplitCard(f)
                    barChartSection(f)
                    jobListSection(f)
                    breakdownButton
                } else if loadFailed {
                    errorState
                } else {
                    emptyState
                }
            }
        }
        .refreshable { await load() }
        // task(id:) bricht laufende Requests bei Zeitraum-Wechsel ab → keine veralteten Antworten
        .task(id: period) { await load() }
        .sheet(isPresented: $showBreakdown) {
            if let f = financials { BreakdownSheet(financials: f) }
        }
    }

    // MARK: - Skeleton

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSSkeletonBlock(height: 84, radius: DS.Radius.tile)
                DSSkeletonBlock(height: 84, radius: DS.Radius.tile)
            }
            HStack(spacing: DS.Spacing.sm) {
                DSSkeletonBlock(height: 84, radius: DS.Radius.tile)
                DSSkeletonBlock(height: 84, radius: DS.Radius.tile)
            }
            DSSkeletonBlock(height: 180, radius: DS.Radius.card)
        }
        .accessibilityLabel("Loading financials")
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
            columns: [GridItem(.flexible(), spacing: DS.Spacing.sm), GridItem(.flexible(), spacing: DS.Spacing.sm)],
            spacing: DS.Spacing.sm
        ) {
            DSTile(label: "Total Spending (incl. fee)", value: Money.format(f.totalSpending), tone: .neutral)
            DSTile(label: "Upcoming (incl. fee)", value: Money.format(f.upcomingPayments), tone: FinanceTone.upcoming)
            DSTile(label: "Completed Jobs", value: "\(f.completedJobsCount)", tone: FinanceTone.completed)
            // Wireframe: Total Spending, Upcoming Payments, Completed Jobs, Paid Out
            // (Monthly Spend steht weiterhin auf dem Employer-Dashboard)
            DSTile(label: "Paid Out", value: Money.format(f.paidOut), tone: FinanceTone.paidOut)
        }
    }

    /// "Total Spending" = Lohn + Plattform-Gebuehr; hier die Aufteilung (Worker erhalten den vollen Lohn)
    @ViewBuilder
    private func feeSplitCard(_ f: EmployerFinancialsDTO) -> some View {
        if let wages = f.totalWages, let fees = f.totalFees {
            let percent = f.platformFeePercent ?? PlatformFees.defaultPlatformPercent
            DSSection("Spending split") {
                VStack(alignment: .leading, spacing: 0) {
                    splitRow("Worker wages", Money.format(wages, fractionDigits: 2))
                    splitRow("Platform fees (\(PlatformFees.percentLabel(percent)))", Money.format(fees, fractionDigits: 2))
                    splitRow("Total spending", Money.format(f.totalSpending, fractionDigits: 2), bold: true)
                    Text("Totals include the platform fee. Workers always receive the full hourly wage.")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
    }

    private func splitRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(DS.Font.make(14, bold ? .semibold : .regular, relativeTo: .callout))
            Spacer()
            Text(value).font(DS.Font.make(14, bold ? .bold : .semibold, relativeTo: .callout))
        }
        .foregroundStyle(bold ? DS.Color.text : DS.Color.text2)
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: 36)
        .overlay(alignment: .top) { DSDivider() }
    }

    // MARK: - Bar Chart

    private func barChartSection(_ f: EmployerFinancialsDTO) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.md) {
                    legendDot(DS.Color.success, "Upcoming")
                    legendDot(DS.Color.primary, "Completed")
                    legendDot(DS.Color.warning, "Paid Out")
                    Spacer()
                }

                if f.chartData.allSatisfy({ $0.upcoming + $0.completed + $0.paidOut == 0 }) {
                    Text("No data for the selected period.")
                        .dsFont(.callout).foregroundStyle(DS.Color.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DS.Spacing.xxl)
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
                                            barSegment(DS.Color.success, day.upcoming,  maxBarValue, geo.size.height)
                                            barSegment(DS.Color.primary, day.completed, maxBarValue, geo.size.height)
                                            barSegment(DS.Color.warning, day.paidOut,   maxBarValue, geo.size.height)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .frame(height: 100)
                                Text(index % labelEvery == 0 ? day.day : " ")
                                    .font(DS.Font.make(10, .medium, relativeTo: .caption2))
                                    .foregroundStyle(DS.Color.muted)
                                    .lineLimit(1).fixedSize()
                                    .frame(maxWidth: .infinity)
                            }
                            .opacity(total > 0 ? 1 : 0.3)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Daily spending chart")
                    .accessibilityValue("Upcoming \(Money.format(f.upcomingPayments)), paid out \(Money.format(f.paidOut))")
                }
            }
        }
    }

    private func barSegment(_ color: Color, _ value: Double, _ maxVal: Double, _ totalHeight: CGFloat) -> some View {
        let height = maxVal > 0 ? CGFloat(value / maxVal) * totalHeight : 0
        return Rectangle().fill(color).frame(height: max(height, value > 0 ? 2 : 0))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).dsFont(.caption).foregroundStyle(DS.Color.text2)
        }
    }

    // MARK: - Job Lists

    @ViewBuilder
    private func jobListSection(_ f: EmployerFinancialsDTO) -> some View {
        if !f.upcomingJobs.isEmpty {
            DSSection("Upcoming Payments", ruled: false) {
                VStack(spacing: DS.Spacing.xs) {
                    ForEach(f.upcomingJobs) { job in
                        FinancialJobRow(job: job)
                    }
                }
            }
        }

        if !f.completedJobsList.isEmpty {
            DSSection("Completed Jobs", ruled: false) {
                VStack(spacing: DS.Spacing.xs) {
                    ForEach(f.completedJobsList) { job in
                        FinancialJobRow(job: job)
                    }
                }
            }
        }

        if f.upcomingJobs.isEmpty && f.completedJobsList.isEmpty {
            Text("No jobs yet.")
                .dsFont(.callout).foregroundStyle(DS.Color.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DS.Spacing.lg)
        }
    }

    // MARK: - Breakdown Button

    private var breakdownButton: some View {
        Button { showBreakdown = true } label: {
            Label("View Breakdown", systemImage: "chart.bar.xaxis")
        }
        .buttonStyle(.ds(.secondary, size: .medium))
    }

    // MARK: - Empty / Error

    private var errorState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("Could not load financial data.")
                .dsFont(.callout).foregroundStyle(DS.Color.muted)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.xl)
    }

    private var emptyState: some View {
        DSEmptyState(
            systemIcon: "chart.bar",
            title: "No financial data yet",
            message: "Your earnings and spending will appear here once you start posting jobs."
        )
    }
}

// MARK: - FinancialJobRow

private struct FinancialJobRow: View {
    let job: FinancialJobDTO

    /// Backend-Status: upcoming | completed | paid (alle Worker bezahlt)
    private var statusLabel: String {
        switch job.status {
        case "paid":      return "Paid"
        case "completed": return "Done"
        default:          return "Upcoming"
        }
    }

    private var statusTone: DS.Tone {
        switch job.status {
        case "paid":      return FinanceTone.paidOut
        case "completed": return FinanceTone.completed
        default:          return FinanceTone.upcoming
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: job.logoEmoji, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).font(DS.Font.make(15, .semibold, relativeTo: .callout)).foregroundStyle(DS.Color.text)
                Text(job.shiftText).dsFont(.caption).foregroundStyle(DS.Color.text2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                Text(Money.format(job.amount)).font(DS.Font.make(16, .bold, relativeTo: .callout)).foregroundStyle(DS.Color.text)
                DSBadge(statusLabel, .tone(statusTone))
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .overlay(alignment: .bottom) { DSDivider() }
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
            // Total Spending enthaelt bereits Bezahltes → "Completed" hier nur der offene Teil,
            // sonst wuerde Paid Out doppelt in die Summe eingehen
            return [
                ("Upcoming",            financials.upcomingPayments,                          DS.Color.success),
                ("Completed (unpaid)",  max(0, financials.totalSpending - financials.paidOut), DS.Color.primary),
                ("Paid Out",            financials.paidOut,                                   DS.Color.warning)
            ].filter { $0.1 > 0 }
        } else {
            let colors: [Color] = [DS.Color.primary, DS.Color.success, DS.Color.warning, DS.Color.danger, DS.Color.text2, DS.Color.muted]
            return financials.byCategory.sorted { $0.value > $1.value }.enumerated().map { i, pair in
                (pair.key, pair.value, colors[i % colors.count])
            }
        }
    }
    private var totalAmount: Double { rows.reduce(0) { $0 + $1.1 } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(BreakdownMode.allCases, id: \.self) { m in
                            DSChip(m.rawValue, isSelected: mode == m) { mode = m }
                        }
                        Spacer(minLength: 0)
                    }

                    if rows.isEmpty {
                        Text("No data available.").dsFont(.callout).foregroundStyle(DS.Color.muted)
                            .padding(.vertical, DS.Spacing.xxl)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(rows, id: \.0) { (label, amount, color) in
                                breakdownRow(label: label, amount: amount, color: color)
                            }
                            HStack {
                                Text("Total").dsFont(.headline).foregroundStyle(DS.Color.text)
                                Spacer()
                                Text(Money.format(totalAmount))
                                    .font(DS.Font.make(16, .bold, relativeTo: .callout)).foregroundStyle(DS.Color.text)
                            }
                            .padding(.vertical, DS.Spacing.sm)
                            .overlay(alignment: .top) { DSDivider() }
                        }
                        .overlay(alignment: .bottom) { DSDivider() }
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs).padding(.bottom, DS.Spacing.xxl)
            }
            .dsBackground()
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
        HStack(spacing: DS.Spacing.sm) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).dsFont(.body).foregroundStyle(DS.Color.text)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.surface2).frame(height: 6)
                    Capsule().fill(color)
                        .frame(width: totalAmount > 0 ? geo.size.width * CGFloat(amount / totalAmount) : 0, height: 6)
                }
            }
            .frame(width: 80, height: 6)
            Text(Money.format(amount)).font(DS.Font.make(15, .semibold, relativeTo: .callout)).foregroundStyle(DS.Color.text)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { DSDivider() }
    }
}
