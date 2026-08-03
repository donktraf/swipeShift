//
//  FinancialOverviewView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Time Period

private enum TimePeriod: String, CaseIterable {
    case thisMonth   = "This Month"
    case last3Months = "Last 3 Months"
    case thisYear    = "This Year"
    case allTime     = "All Time"

    var apiKey: String {
        switch self {
        case .thisMonth:   return "thisMonth"
        case .last3Months: return "last3Months"
        case .thisYear:    return "thisYear"
        case .allTime:     return "allTime"
        }
    }
}

// MARK: - FinancialOverviewView

struct FinancialOverviewView: View {
    @State private var selectedPeriod: TimePeriod = .thisMonth
    @State private var financials: WorkerFinancialsDTO? = nil
    @State private var isLoading     = false
    @State private var errorMessage: String? = nil
    @State private var incomeGoal: Double = UserDefaults.standard.double(forKey: "incomeGoal") == 0
                                            ? 2000 : UserDefaults.standard.double(forKey: "incomeGoal")
    @State private var showGoalEditor = false

    private var upcomingEarnings:  Double { financials?.upcomingEarnings  ?? 0 }
    private var completedEarnings: Double { financials?.completedEarnings ?? 0 }
    private var paidOut:           Double { financials?.paidOut           ?? 0 }
    private var total:             Double { upcomingEarnings + completedEarnings + paidOut }
    private var progressToGoal:    Double { min(total / max(incomeGoal, 1), 1.0) }
    private var gap:               Double { max(incomeGoal - total, 0) }

    var body: some View {
        SubScreenShell(title: "Financial Overview") {
            VStack(spacing: 20) {
                periodPicker.padding(.horizontal, 16)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let err = errorMessage {
                    VStack(spacing: 12) {
                        Text(err).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button("Retry") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
                    }.padding(.top, 40)
                } else {
                    summaryCards
                    donutSection
                    stepToTargetSection
                    earningsList
                    Spacer().frame(height: 20)
                }
            }
        }
        .sheet(isPresented: $showGoalEditor) { GoalEditorSheet(goal: $incomeGoal) }
        .task { await load() }
        .onChange(of: selectedPeriod) { _, _ in Task { await load() } }
        .onChange(of: incomeGoal) { _, new in UserDefaults.standard.set(new, forKey: "incomeGoal") }
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
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.white.opacity(0.2)).clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 10) {
            FinancialStatCard(label: "Upcoming",  amount: upcomingEarnings,  color: .green,    icon: "arrow.up.circle.fill")
            FinancialStatCard(label: "Completed", amount: completedEarnings, color: SS.primary, icon: "checkmark.circle.fill")
            FinancialStatCard(label: "Paid Out",  amount: paidOut,           color: .orange,   icon: "eurosign.circle.fill")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Donut Chart

    private var donutSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Canvas { ctx, size in
                    guard total > 0 else { return }
                    let center      = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius      = min(size.width, size.height) / 2 - 10
                    let lineWidth   = radius * 0.4
                    let slices: [(Double, Color)] = [
                        (upcomingEarnings  / total, .green),
                        (completedEarnings / total, SS.primary),
                        (paidOut           / total, .orange),
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

                VStack(spacing: 2) {
                    Text("€\(Int(total))")
                        .font(.system(size: 22, weight: .bold)).foregroundColor(.primary)
                    Text("Total").font(.system(size: 12)).foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                LegendItem(color: .green,    label: "Upcoming")
                LegendItem(color: SS.primary, label: "Completed")
                LegendItem(color: .orange,   label: "Paid Out")
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
            Text("Jobs")
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 16)

            if let list = financials?.earningsList, !list.isEmpty {
                VStack(spacing: 8) {
                    ForEach(list) { item in
                        EarningRow(item: item)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                Text("No earnings in this period.")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Step to Target

    private var stepToTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Step to Target")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Goal: €\(Int(incomeGoal))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Button { showGoalEditor = true } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 8) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(progressToGoal >= 1 ? Color.green : SS.primary)
                            .frame(width: geo.size.width * progressToGoal)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("€\(Int(total)) earned")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                    if gap > 0 {
                        Text("€\(Int(gap)) to go")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                    } else {
                        Label("Goal reached!", systemImage: "trophy.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; errorMessage = nil
        do { financials = try await APIClient.shared.fetchWorkerFinancials(period: selectedPeriod.apiKey) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

// MARK: - Goal Editor Sheet

private struct GoalEditorSheet: View {
    @Binding var goal: Double
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly income goal (€)") {
                    TextField("2000", text: $input)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = Double(input), v > 0 { goal = v }
                        dismiss()
                    }
                }
            }
        }
        .onAppear { input = "\(Int(goal))" }
    }
}

// MARK: - Sub-Views

private struct FinancialStatCard: View {
    let label: String; let amount: Double; let color: Color; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            Text("€\(Int(amount))").font(.system(size: 20, weight: .bold)).foregroundColor(.primary)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct LegendItem: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
        }
    }
}

private struct EarningRow: View {
    let item: WorkerEarningItem
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.jobTitle).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                Text("\(item.company) · \(item.shiftText)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("€\(Int(item.amount))").font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                Text(item.status == "upcoming" ? "Upcoming" : "Completed")
                    .font(.system(size: 11))
                    .foregroundColor(item.status == "upcoming" ? .green : .secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
