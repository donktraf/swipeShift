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

    /// Alle Jobs (für JobListView, Dashboard-Fallback).
    @Published var jobs: [Job] = []

    /// Nur für den Swipe-Tab — wird beim apply/skip geleert.
    /// Alle anderen Bereiche (Radar, Dashboard) teilen diesen Array NICHT.
    @Published var swipeJobs: [Job] = []

    @Published var nearbyJobs: [Job] = []

    // Dashboard-Sektionen (gefiltert vom Backend)
    @Published var recommendedJobs:  [Job] = []
    @Published var quickMoneyJobs:   [Job] = []
    @Published var startingSoonJobs: [Job] = []
    @Published var popularJobs:      [Job] = []

    /// Fehlertext für UI (z. B. Banner oder Inline-Text).
    @Published var errorMessage: String?

    /// Aktuell ausgewählte Location für Job-Fetch.
    /// Wenn `nil`, werden keine Jobs geladen.
    @Published var selectedLocation: String?

    /// IDs der vom Worker gespeicherten (gebookmarkten) Jobs.
    /// Wird zentral hier gehalten, damit `DashboardJobCard` an allen
    /// Verwendungsstellen (Dashboard-Sektionen, JobListView) denselben
    /// Saved-Status anzeigt und togglen kann.
    @Published var savedJobIds: Set<String> = []

    /// Verhindert wiederholtes Neuladen der Saved-IDs bei jedem `.task`-Aufruf.
    private var hasLoadedSavedJobIds = false

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
    
    // NEU in JobStore — unter loadJobs() hinzufügen
    @MainActor
    func loadJobsAll() async {
        errorMessage = nil
        do {
            let result = try await APIClient.shared.fetchJobs(location: nil)
            jobs = result
            print("Jobs loaded (all):", jobs.count)
        } catch {
            errorMessage = error.localizedDescription
            print("loadJobsAll error:", error.localizedDescription)
        }
    }
    
    /// Lädt Jobs speziell für den Swipe-Tab (eigener Array, unabhängig vom Rest).
    @MainActor
    func loadSwipeJobs() async {
        errorMessage = nil
        do {
            swipeJobs = try await APIClient.shared.fetchJobs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lädt alle 4 Dashboard-Sektionen parallel vom Backend.
    @MainActor
    func loadDashboardSections() async {
        errorMessage = nil
        async let recommended  = fetch(type: "recommended")
        async let quickMoney   = fetch(type: "quickMoney")
        async let startingSoon = fetch(type: "startingSoon")
        async let popular      = fetch(type: "popular")

        recommendedJobs  = (try? await recommended)  ?? []
        quickMoneyJobs   = (try? await quickMoney)   ?? []
        startingSoonJobs = (try? await startingSoon) ?? []
        popularJobs      = (try? await popular)      ?? []
    }

    private func fetch(type: String) async throws -> [Job] {
        try await APIClient.shared.fetchJobs(type: type)
    }

    @MainActor
    func loadNearbyJobs(lat: Double, lng: Double, radius: Double = 100) async {
        errorMessage = nil
        do {
            let result = try await APIClient.shared.fetchNearbyJobs(
                lat: lat,
                lng: lng,
                radius: radius
            )
            nearbyJobs = result
            print("Nearby jobs loaded:", nearbyJobs.count)
        } catch {
            errorMessage = error.localizedDescription
            print("loadNearbyJobs error:", error.localizedDescription)
        }
    }

    /// Lädt die IDs der gespeicherten Jobs einmalig vom Backend.
    /// Wird von `WorkerHomeTabView` und `JobListView` aufgerufen, damit
    /// `DashboardJobCard` den echten Bookmark-Status anzeigen kann.
    @MainActor
    func loadSavedJobIds() async {
        guard !hasLoadedSavedJobIds else { return }
        hasLoadedSavedJobIds = true
        if let saved = try? await APIClient.shared.fetchWorkerSaved() {
            savedJobIds = Set(saved.map { $0.jobId })
        }
    }

    /// Speichert/entspeichert einen Job und aktualisiert den lokalen Status optimistisch.
    @MainActor
    func toggleSaveJob(_ jobId: String) async {
        if savedJobIds.contains(jobId) {
            savedJobIds.remove(jobId)
            try? await APIClient.shared.unsaveJob(jobId: jobId)
        } else {
            savedJobIds.insert(jobId)
            try? await APIClient.shared.saveJob(jobId: jobId)
        }
    }

    // MARK: - Actions (Swipe)

    /// Skippt einen Job (nicht interessiert).
    /// Entfernt nur aus swipeJobs — Radar, Dashboard und andere Bereiche bleiben unberührt.
    @MainActor
    func skip(_ job: Job) async {
        errorMessage = nil
        do {
            try await APIClient.shared.skip(jobId: job.id)
            swipeJobs.removeAll { $0.id == job.id }
        } catch {
            errorMessage = error.localizedDescription
            print("skip error:", error.localizedDescription)
        }
    }

    /// Bewirbt sich auf einen Job.
    /// Entfernt nur aus swipeJobs — Radar, Dashboard und andere Bereiche bleiben unberührt.
    @MainActor
    func apply(to job: Job) async throws {
        errorMessage = nil
        try await APIClient.shared.apply(jobId: job.id)
        swipeJobs.removeAll { $0.id == job.id }
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
