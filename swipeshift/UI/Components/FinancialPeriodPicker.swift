//
//  FinancialPeriodPicker.swift
//  swipeShift
//
//  Zeitraum-Auswahl fuer die Finanz-Uebersichten (Worker + Employer):
//  This Month / Last 3 Months / This Year / All Time / Custom Range (Kalender-Sheet).
//  Backend-Gegenstueck: swipeshift-backend/src/utils/period.js
//

import SwiftUI

// MARK: - Model

enum FinancialPeriodOption: String, CaseIterable, Identifiable {
    case thisMonth
    case last3Months
    case thisYear
    case allTime
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMonth:   return "This Month"
        case .last3Months: return "Last 3 Months"
        case .thisYear:    return "This Year"
        case .allTime:     return "All Time"
        case .custom:      return "Custom Range"
        }
    }
}

struct FinancialPeriod: Equatable {
    var option: FinancialPeriodOption = .thisMonth
    /// Nur bei `.custom` relevant (beide Tage inklusive)
    var customFrom: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    var customTo: Date = Date()

    static let `default` = FinancialPeriod()

    /// Query-Parameter fuer `GET /worker/financials` bzw. `GET /employer/financials`
    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "period", value: option.rawValue)]
        if option == .custom {
            items.append(URLQueryItem(name: "from", value: Self.apiDay.string(from: customFrom)))
            items.append(URLQueryItem(name: "to", value: Self.apiDay.string(from: customTo)))
        }
        return items
    }

    /// Text auf dem Picker-Button, bei Custom Range z.B. "Oct 5 – Oct 20, 2026"
    var label: String {
        guard option == .custom else { return option.label }
        let sameYear = Calendar.current.isDate(customFrom, equalTo: customTo, toGranularity: .year)
        let fromText = customFrom.formatted(sameYear ? .dateTime.month(.abbreviated).day()
                                                     : .dateTime.month(.abbreviated).day().year())
        let toText = customTo.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(fromText) – \(toText)"
    }

    /// Lokales Kalenderdatum als YYYY-MM-DD (Backend interpretiert es als ganzen Tag)
    private static let apiDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Picker (Capsule-Dropdown, fuer dunklen SubScreenShell-Hintergrund)

struct FinancialPeriodPicker: View {
    @Binding var period: FinancialPeriod
    @State private var showCustomRange = false

    var body: some View {
        Menu {
            ForEach(FinancialPeriodOption.allCases.filter { $0 != .custom }) { option in
                Button {
                    period.option = option
                } label: {
                    if period.option == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
            Divider()
            Button {
                showCustomRange = true
            } label: {
                Label(period.option == .custom ? "Custom Range ✓" : "Custom Range…", systemImage: "calendar")
            }
        } label: {
            HStack {
                Text(period.label)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.white.opacity(0.2)).clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Time period: \(period.label)")
        .sheet(isPresented: $showCustomRange) {
            CustomRangeSheet(initialFrom: period.customFrom, initialTo: period.customTo) { from, to in
                period = FinancialPeriod(option: .custom, customFrom: from, customTo: to)
            }
        }
    }
}

// MARK: - Custom Range Sheet (Kalender-Ansicht)

private struct CustomRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onApply: (Date, Date) -> Void

    private enum Edge: String, CaseIterable { case start = "Start", end = "End" }

    @State private var from: Date
    @State private var to: Date
    @State private var editing: Edge = .start

    /// Gleiches Limit wie das Backend (MAX_CUSTOM_DAYS ≈ 5 Jahre)
    private static let maxYears = 5

    init(initialFrom: Date, initialTo: Date, onApply: @escaping (Date, Date) -> Void) {
        _from = State(initialValue: initialFrom)
        _to = State(initialValue: initialTo)
        self.onApply = onApply
    }

    private var maxEnd: Date {
        Calendar.current.date(byAdding: .year, value: Self.maxYears, to: from) ?? from
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("", selection: $editing) {
                    ForEach(Edge.allCases, id: \.self) { edge in
                        Text("\(edge.rawValue): \(formatted(edge == .start ? from : to))").tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                Group {
                    if editing == .start {
                        DatePicker("Start", selection: $from, displayedComponents: .date)
                    } else {
                        DatePicker("End", selection: $to, in: from...maxEnd, displayedComponents: .date)
                    }
                }
                .datePickerStyle(.graphical)
                .tint(SS.primary)
                .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(from, to)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            // Start nach dem Ende verschoben → Ende mitziehen; Bereich zu lang → kuerzen
            .onChange(of: from) { _, newFrom in
                if to < newFrom { to = newFrom }
                if to > maxEnd { to = maxEnd }
            }
        }
        .presentationDetents([.large])
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
