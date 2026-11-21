//
//  PlatformFees.swift
//  swipeShift
//
//  Plattform-Gebuehr: Servicegebuehr OBENDRAUF auf den Employer, der Worker bekommt immer den
//  vollen Stundenlohn. Rundung cent-genau wie das Backend (utils/fees.js: Math.round(x * 100)).
//

import Foundation
import Combine

enum PlatformFees {
    /// Fallback, falls GET /config (noch) nicht geladen ist — identisch zu den Backend-Defaults
    static let defaultPlatformPercent = 15.0
    static let defaultInstantPayoutPercent = 1.5

    static func roundMoney(_ amount: Double) -> Double {
        (amount * 100).rounded(.toNearestOrAwayFromZero) / 100
    }

    /// Gebuehr auf einen Lohnbetrag (je Worker-Schicht gerundet, danach multiplizieren)
    static func fee(for wage: Double, percent: Double) -> Double {
        roundMoney(wage * percent / 100)
    }

    /// "15 %" bzw. "1.5 %"
    static func percentLabel(_ percent: Double) -> String {
        let text = percent.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(percent))
            : String(format: "%g", (percent * 100).rounded() / 100)
        return "\(text) %"
    }

    /// Kostenaufstellung fuer den Employer
    struct Breakdown {
        let wages: Double
        let fees: Double
        var total: Double { PlatformFees.roundMoney(wages + fees) }
    }

    /// Je Schicht gerundet: wage = Stunden × Stundenlohn, fee = Gebuehr darauf, × Anzahl Worker
    static func breakdown(hours: Double, hourlyRate: Double, workers: Int, percent: Double) -> Breakdown {
        let wagePerWorker = roundMoney(max(0, hours) * max(0, hourlyRate))
        let feePerWorker  = fee(for: wagePerWorker, percent: percent)
        return Breakdown(wages: roundMoney(wagePerWorker * Double(workers)),
                         fees:  roundMoney(feePerWorker * Double(workers)))
    }
}

/// Aktuelle Satz-Konfiguration vom Backend (GET /config, oeffentlich, keine Secrets)
@MainActor
final class FeeConfig: ObservableObject {
    static let shared = FeeConfig()

    @Published private(set) var platformFeePercent = PlatformFees.defaultPlatformPercent
    @Published private(set) var instantPayoutFeePercent = PlatformFees.defaultInstantPayoutPercent

    func refresh() async {
        guard let cfg = try? await APIClient.shared.fetchAppConfig() else { return }
        platformFeePercent = cfg.platformFeePercent
        instantPayoutFeePercent = cfg.instantPayoutFeePercent
    }
}

struct AppConfigDTO: Decodable {
    let platformFeePercent: Double
    let instantPayoutFeePercent: Double
}
