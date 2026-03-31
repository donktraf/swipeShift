//
//  FinancialOverviewView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Time Period

private enum TimePeriod: String, CaseIterable {
    case thisMonth    = "This Month"
    case last3Months  = "Last 3 Months"
    case thisYear     = "This Year"
    case allTime      = "All Time"
}

// MARK: - FinancialOverviewView

struct FinancialOverviewView: View {
    @State private var selectedPeriod: TimePeriod = .thisMonth

    // TODO: aus Backend laden (GET /users/:id/financials)
    private let upcomingEarnings: Double = 340
    private let completedEarnings: Double = 560
    private let paidOut: Double = 480

    private var total: Double { upcomingEarnings + completedEarnings + paidOut }

    var body: some View {
        SubScreenShell(title: "Financial Overview") {
            VStack(spacing: 20) {
                periodPicker
                    .padding(.horizontal, 16)

                summaryCards

                donutSection

                earningsList

                Spacer().frame(height: 20)
            }
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Menu {
            ForEach(TimePeriod.allCases, id: \.self) { p in
                Button(p.rawValue) { selectedPeriod = p }
            }
        } label: {
            HStack {
                Text(selectedPeriod.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 10) {
            FinancialStatCard(
                label: "Upcoming",
                amount: upcomingEarnings,
                color: .green,
                icon: "arrow.up.circle.fill"
            )
            FinancialStatCard(
                label: "Completed",
                amount: completedEarnings,
                color: SS.primary,
                icon: "checkmark.circle.fill"
            )
            FinancialStatCard(
                label: "Paid Out",
                amount: paidOut,
                color: .orange,
                icon: "eurosign.circle.fill"
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Donut Chart (Canvas)

    private var donutSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Custom donut via Canvas
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2 - 10
                    let innerRadius = radius * 0.6
                    let lineWidth = radius - innerRadius

                    let slices: [(Double, Color)] = [
                        (upcomingEarnings / total, .green),
                        (completedEarnings / total, SS.primary),
                        (paidOut / total, .orange),
                    ]

                    var startAngle = Angle.degrees(-90)
                    for (fraction, color) in slices {
                        let endAngle = startAngle + .degrees(360 * fraction)
                        var path = Path()
                        path.addArc(center: center, radius: radius - lineWidth / 2,
                                    startAngle: startAngle, endAngle: endAngle, clockwise: false)
                        ctx.stroke(path, with: .color(color),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        startAngle = endAngle
                    }
                }
                .frame(width: 160, height: 160)

                // Center label
                VStack(spacing: 2) {
                    Text("€\(Int(total))")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Gesamt")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            // Legend
            HStack(spacing: 20) {
                LegendItem(color: .green,   label: "Upcoming")
                LegendItem(color: SS.primary, label: "Completed")
                LegendItem(color: .orange,  label: "Paid Out")
            }
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Earnings List

    private var earningsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bevorstehende Jobs")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                EarningRow(title: "Bartender", company: "Club Tresor",
                           date: "Mar 28", amount: 144, status: .confirmed)
                EarningRow(title: "Event Staff", company: "Eventify GmbH",
                           date: "Mar 30", amount: 120, status: .confirmed)
                EarningRow(title: "Warehouse", company: "LogiCore",
                           date: "Apr 2", amount: 112, status: .applied)
            }
            .padding(.horizontal, 16)

            Button {
                // TODO: → Aufschlüsselung nach Job Status / Kategorie
            } label: {
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

// MARK: - Sub-Views

private struct FinancialStatCard: View {
    let label: String
    let amount: Double
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text("€\(Int(amount))")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

private struct EarningRow: View {
    let title: String
    let company: String
    let date: String
    let amount: Double
    let status: ApplicationStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(company) · \(date)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("€\(Int(amount))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Text(status == .confirmed ? "Confirmed" : "Pending")
                    .font(.system(size: 11))
                    .foregroundColor(status == .confirmed ? .green : .secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
