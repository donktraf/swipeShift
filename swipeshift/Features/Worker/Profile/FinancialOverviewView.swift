//
//  FinancialOverviewView.swift
//  swipeShift
//

import SwiftUI

// MARK: - FinancialOverviewView

struct FinancialOverviewView: View {
    @State private var period: FinancialPeriod = .default
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
        SubScreenShell(title: "Financial Overview", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                FinancialPeriodPicker(period: $period)

                if isLoading && financials == nil {
                    skeleton
                } else if let err = errorMessage {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(err).dsFont(.callout).foregroundStyle(DS.Color.muted)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xl)
                } else {
                    summaryCards
                    donutSection
                    stepToTargetSection
                    earningsList
                }
            }
        }
        .refreshable { await load() }
        .sheet(isPresented: $showGoalEditor) { GoalEditorSheet(goal: $incomeGoal) }
        // task(id:) bricht laufende Requests bei Zeitraum-Wechsel ab → keine veralteten Antworten
        .task(id: period) { await load() }
        .onChange(of: incomeGoal) { _, new in UserDefaults.standard.set(new, forKey: "incomeGoal") }
    }

    // MARK: - Skeleton

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    DSSkeletonBlock(height: 84, radius: DS.Radius.tile)
                }
            }
            DSSkeletonBlock(height: 220, radius: DS.Radius.card)
        }
        .accessibilityLabel("Loading financials")
    }

    // MARK: - Farben (Donut, Legende, Kacheln)

    private let upcomingTone: DS.Tone = .success
    private let completedTone: DS.Tone = .primary
    private let paidOutTone: DS.Tone = .warning

    // MARK: - Summary Cards

    private var summaryCards: some View {
        VStack(spacing: DS.Spacing.sm) {
            // Laufende Woche Mo–So, unabhaengig vom gewaehlten Zeitraum (nur wenn das Backend sie liefert)
            if let week = financials?.thisWeekEarnings {
                DSRow("This week", systemIcon: "calendar.badge.clock", showsDivider: false) {
                    Text(Money.format(week))
                        .font(DS.Font.make(20, .bold, relativeTo: .title3)).foregroundStyle(DS.Color.text)
                }
            }
            HStack(spacing: DS.Spacing.sm) {
                DSTile(label: "Upcoming",  value: Money.format(upcomingEarnings),  tone: upcomingTone)
                DSTile(label: "Completed", value: Money.format(completedEarnings), tone: completedTone)
                DSTile(label: "Paid Out",  value: Money.format(paidOut),           tone: paidOutTone)
            }
        }
    }

    // MARK: - Donut Chart

    private var donutSection: some View {
        DSCard {
            VStack(spacing: DS.Spacing.md) {
                ZStack {
                    Canvas { ctx, size in
                        guard total > 0 else { return }
                        let center      = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius      = min(size.width, size.height) / 2 - 10
                        let lineWidth   = radius * 0.4
                        let slices: [(Double, Color)] = [
                            (upcomingEarnings  / total, DS.Color.success),
                            (completedEarnings / total, DS.Color.primary),
                            (paidOut           / total, DS.Color.warning),
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
                        Text(Money.format(total))
                            .font(DS.Font.make(22, .bold, relativeTo: .title2)).foregroundStyle(DS.Color.text)
                        Text("Total").dsFont(.caption).foregroundStyle(DS.Color.muted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total \(Money.format(total)). Upcoming \(Money.format(upcomingEarnings)), completed \(Money.format(completedEarnings)), paid out \(Money.format(paidOut)).")

                HStack(spacing: DS.Spacing.lg) {
                    LegendItem(color: DS.Color.success, label: "Upcoming")
                    LegendItem(color: DS.Color.primary, label: "Completed")
                    LegendItem(color: DS.Color.warning, label: "Paid Out")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Earnings List

    private var earningsList: some View {
        DSSection("Jobs", ruled: false) {
            if let list = financials?.earningsList, !list.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    ForEach(EarningMonthGroup.make(from: list)) { group in
                        EarningMonthSection(group: group)
                    }
                    if let total = financials?.earningsTotal, total > list.count {
                        Text("Showing latest \(list.count) of \(total) jobs")
                            .dsFont(.caption).foregroundStyle(DS.Color.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, DS.Spacing.xs)
            } else {
                Text("No earnings in this period.")
                    .dsFont(.callout).foregroundStyle(DS.Color.muted)
                    .padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    // MARK: - Step to Target

    private var stepToTargetSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step to Target")
                            .dsFont(.headline).foregroundStyle(DS.Color.text)
                        Text("Goal: \(Money.format(incomeGoal))")
                            .dsFont(.caption).foregroundStyle(DS.Color.muted)
                    }
                    Spacer()
                    DSIconButton(systemName: "pencil", label: "Edit goal") { showGoalEditor = true }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Color.surface2)
                        Capsule()
                            .fill(progressToGoal >= 1 ? DS.Color.success : DS.Color.primary)
                            .frame(width: geo.size.width * progressToGoal)
                    }
                }
                .frame(height: 10)
                .dsAnimation(.standard, value: progressToGoal)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Goal progress")
                .accessibilityValue("\(Int(progressToGoal * 100)) percent")

                HStack {
                    Text("\(Money.format(total)) earned")
                        .dsFont(.caption).foregroundStyle(DS.Color.text2)
                    Spacer()
                    if gap > 0 {
                        Text("\(Money.format(gap)) to go")
                            .font(DS.Font.make(12, .semibold, relativeTo: .caption)).foregroundStyle(DS.Color.warning)
                    } else {
                        Label("Goal reached!", systemImage: "trophy.fill")
                            .font(DS.Font.make(12, .semibold, relativeTo: .caption)).foregroundStyle(DS.Color.success)
                    }
                }
            }
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; errorMessage = nil
        do {
            let result = try await APIClient.shared.fetchWorkerFinancials(period: period)
            guard !Task.isCancelled else { return }
            financials = result
        } catch {
            // Zeitraum gewechselt → alter Request abgebrochen, neuer laeuft bereits
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
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
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                DSTextField("Monthly income goal ($)", placeholder: "2000", text: $input)
                    .keyboardType(.decimalPad)
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.screenEdge)
            .dsBackground()
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
        .presentationDetents([.medium])
        .onAppear { input = "\(Int(goal))" }
    }
}

// MARK: - Sub-Views

private struct LegendItem: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).dsFont(.caption).foregroundStyle(DS.Color.text2)
        }
    }
}
