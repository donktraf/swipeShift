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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("You're confirmed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                    Text(item.jobTitle)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                    Text(whenText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text(item.company)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            HStack {
                if item.conversationId != nil {
                    Button(action: onOpenChat) {
                        Label("Open chat", systemImage: "bubble.left.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(SS.primary)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if more > 0 {
                    NavigationLink {
                        JobApplicationsView()
                    } label: {
                        Text("and \(more) more")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SS.primary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
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
