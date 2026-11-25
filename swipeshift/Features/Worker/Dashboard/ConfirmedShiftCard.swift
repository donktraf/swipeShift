//
//  ConfirmedShiftCard.swift
//  swipeShift
//
//  "You're confirmed"-Karte im Worker-Home-Tab: naechste angenommene, noch nicht beendete Schicht.
//  Daten aus GET /worker/applications (displayStatus == "confirmed"). Wegtippen wird pro Apply-ID lokal gemerkt.
//

import SwiftUI
import Combine

// MARK: - Auswahl-Logik / Dismiss-Speicher (rein, ohne UI)

enum ConfirmedShiftLogic {
    /// UserDefaults-/AppStorage-Schluessel fuer weggetippte Apply-IDs (wird beim Abmelden geleert)
    static let dismissedKey = "dismissedConfirmedApplyIds"

    /// Komma-getrennte IDs → Set; leere/kaputte Eintraege werden ignoriert
    static func parseIds(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Fuegt eine ID hinzu und begrenzt die Liste (neueste bleiben), damit der Wert nicht endlos waechst
    static func appendId(_ id: String, to raw: String, limit: Int = 100) -> String {
        var ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty && $0 != id }
        ids.append(id)
        return ids.suffix(limit).joined(separator: ",")
    }

    /// Start der naechsten noch nicht beendeten gebuchten Schicht (Fallback: startTime der Bewerbung)
    static func nextShiftStart(of item: WorkerApplicationItem, now: Date) -> Date? {
        if let shifts = item.bookedShifts, !shifts.isEmpty {
            let upcoming = shifts
                .filter { ($0.endTime ?? $0.startTime ?? .distantFuture) > now }
                .compactMap { $0.startTime }
                .min()
            if let upcoming { return upcoming }
        }
        return item.startTime
    }

    /// Bestaetigt, nicht weggetippt, Schicht noch nicht vorbei; sortiert nach naechstem Start
    static func visible(_ items: [WorkerApplicationItem], dismissed: Set<String>, now: Date) -> [WorkerApplicationItem] {
        items
            .filter { $0.displayStatus == "confirmed" && !dismissed.contains($0.id) && ($0.endTime ?? $0.startTime ?? .distantFuture) > now }
            .sorted { (nextShiftStart(of: $0, now: now) ?? .distantFuture) < (nextShiftStart(of: $1, now: now) ?? .distantFuture) }
    }
}

// MARK: - Daten (gehoert WorkerHomeTabView, damit Laden/Timer/Chat-Navigation auch bei ausgeblendeter Karte leben)

@MainActor
final class ConfirmedShiftModel: ObservableObject {
    @Published private(set) var applications: [WorkerApplicationItem] = []

    func load() async {
        if let result = try? await APIClient.shared.fetchWorkerApplications() {
            applications = result
        }
    }

    func visible(dismissedRaw: String, now: Date) -> [WorkerApplicationItem] {
        ConfirmedShiftLogic.visible(applications, dismissed: ConfirmedShiftLogic.parseIds(dismissedRaw), now: now)
    }
}

// MARK: - View

struct ConfirmedShiftCard: View {
    let item: WorkerApplicationItem
    let more: Int
    let now: Date
    let onOpenChat: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("You're confirmed")
                    .font(DS.Font.make(12, .bold, relativeTo: .caption))
                    .textCase(.uppercase)
                    .tracking(0.72)
                    .opacity(0.85)
                Spacer(minLength: DS.Spacing.sm)
                Button {
                    DS.Haptics.light()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.Font.make(12, .extrabold, relativeTo: nil))
                        .frame(width: 28, height: 28)
                        .background(DS.Color.onPrimary.opacity(0.18), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
                .padding(.vertical, -8)
                .padding(.trailing, -8)
                .accessibilityLabel("Dismiss")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.jobTitle)
                    .font(DS.Font.make(18, .extrabold, relativeTo: .headline))
                    .lineLimit(2)
                Text("\(whenText) · \(item.company)")
                    .font(DS.Font.make(14, .medium, relativeTo: .callout))
                    .opacity(0.9)
            }

            HStack {
                if item.conversationId != nil {
                    Button(action: onOpenChat) {
                        Label("Open chat", systemImage: "bubble.left.fill")
                            .font(DS.Font.make(14, .bold, relativeTo: .callout))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(DS.Color.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.dsPressable)
                }
                Spacer()
                if more > 0 {
                    NavigationLink {
                        JobApplicationsView()
                    } label: {
                        Text("and \(more) more")
                            .font(DS.Font.make(13, .bold, relativeTo: .footnote))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                }
            }
        }
        .foregroundStyle(DS.Color.onPrimary)
        .padding(DS.Spacing.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.primary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, DS.Spacing.screenEdge)
    }

    /// Datum/Uhrzeit der naechsten gebuchten Schicht
    private var whenText: String {
        if let shift = item.bookedShifts?.first(where: { ($0.endTime ?? $0.startTime ?? .distantFuture) > now }),
           let date = shift.date, let range = shift.timeRange {
            return "\(date) · \(range)"
        }
        if let start = ConfirmedShiftLogic.nextShiftStart(of: item, now: now) {
            return start.formatted(date: .abbreviated, time: .shortened)
        }
        return item.shiftText
    }
}
