//
//  JobStore.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

import Foundation
import Combine

/// `JobStore` ist der zentrale State-Container für alle Job-Daten in der App.
///
/// Aufgaben:
/// - hält die aktuelle Job-Liste (`jobs`), die die UI anzeigen soll
/// - lädt Jobs vom Backend (über `APIClient`)
/// - verarbeitet Swipe-Aktionen (apply / skip)
/// - speichert Filter-Infos wie `selectedLocation`
///
/// Views greifen **nur** auf den JobStore zu,
/// niemals direkt auf den APIClient.
final class JobStore: ObservableObject {

    // MARK: - State (für UI)

    /// Jobs, die aktuell in der UI angezeigt werden.
    @Published var jobs: [Job] = []

    /// Fehlertext für UI (z. B. Banner oder Inline-Text).
    @Published var errorMessage: String?

    /// Aktuell ausgewählte Location für Job-Fetch.
    /// Wenn `nil`, werden keine Jobs geladen.
    @Published var selectedLocation: String?

    // MARK: - Loading

    /// Lädt Jobs vom Backend basierend auf `selectedLocation`.
    ///
    /// Ablauf:
    /// 1) `selectedLocation` ist gesetzt
    /// 2) View ruft `loadJobs()`
    /// 3) Jobs werden gespeichert → UI aktualisiert sich automatisch
    @MainActor
    func loadJobs() async {
        guard let selectedLocation,
              !selectedLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            print("loadJobs called without selectedLocation, clearing jobs")
            jobs = []
            return
        }

        errorMessage = nil
        print("loadJobs for location:", selectedLocation)

        do {
            let result = try await APIClient.shared.fetchJobs(
                location: selectedLocation
            )

            jobs = result
            print("Jobs loaded:", jobs.count)

        } catch {
            errorMessage = error.localizedDescription
            print("loadJobs error:", error.localizedDescription)
        }
    }

    // MARK: - Actions (Swipe)

    /// Skippt einen Job (nicht interessiert).
    /// Backend wird informiert, Job wird lokal entfernt.
    @MainActor
    func skip(_ job: Job) async {
        errorMessage = nil

        do {
            try await APIClient.shared.skip(jobId: job.id)
            jobs.removeAll { $0.id == job.id }

        } catch {
            errorMessage = error.localizedDescription
            print("skip error:", error.localizedDescription)
        }
    }

    /// Bewirbt sich auf einen Job.
    /// Backend wird informiert, Job wird lokal entfernt.
    @MainActor
    func apply(to job: Job) async {
        errorMessage = nil

        do {
            try await APIClient.shared.apply(jobId: job.id)
            jobs.removeAll { $0.id == job.id }

        } catch {
            errorMessage = error.localizedDescription
            print("apply error:", error.localizedDescription)
        }
    }

    // MARK: - Helper

    /// Setzt die Location einmalig aus dem eingeloggten User.
    ///
    /// Zweck:
    /// - Beim ersten App-Start sofort Jobs laden können
    /// - Spätere manuelle Filter-Auswahl nicht überschreiben
    func setInitialLocationIfNeeded(from user: UserDTO) {
        if selectedLocation == nil {
            selectedLocation = user.location
        }
    }
}
