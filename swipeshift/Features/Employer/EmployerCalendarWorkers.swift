//
//  EmployerCalendarWorkers.swift
//  swipeShift
//
//  Bestaetigte Worker einer Schicht im Arbeitgeber-Kalender: Name, Foto, Bewertung,
//  Tap → DetailedWorkerView, plus Durchschnittsbewertung des Teams.
//

import SwiftUI

struct EmployerCalendarWorkerDTO: Identifiable, Decodable {
    let applyId: String
    let userId: String
    let name: String
    let photoUrl: String?
    let summary: ApplicantSummary?

    var id: String { applyId }
}

struct CalendarShiftWorkersSection: View {
    let workers: [EmployerCalendarWorkerDTO]
    let averageRating: Double?
    // Job-Kontext fuer die Profilansicht ("Applying For")
    let jobId: String
    let jobTitle: String
    let payText: String
    let shiftText: String
    let location: String
    let logoEmoji: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Confirmed workers")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let averageRating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").foregroundColor(.yellow)
                        Text(String(format: "%.1f avg", averageRating)).fontWeight(.semibold)
                    }
                    .font(.system(size: 12))
                }
            }

            ForEach(workers) { worker in
                NavigationLink {
                    DetailedWorkerView(
                        applicant: applicant(for: worker),
                        onAccept: {}, onDecline: {},
                        showActions: false
                    )
                } label: {
                    HStack(spacing: 10) {
                        ApplicantAvatar(photoUrl: worker.photoUrl, size: 32)
                        Text(worker.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        ApplicantRatingLabel(
                            average: worker.summary?.ratingAverage,
                            count: worker.summary?.reviewCount ?? 0
                        )
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func applicant(for worker: EmployerCalendarWorkerDTO) -> Applicant {
        Applicant(
            applyId: worker.applyId, userId: worker.userId, appliedAt: nil, status: "accepted",
            job: ApplicantJob(id: jobId, title: jobTitle, payText: payText, shiftText: shiftText,
                              location: location, logoEmoji: logoEmoji),
            user: ApplicantUser(id: worker.userId, firstName: worker.name, lastName: nil,
                                location: nil, profilePhotoUrl: worker.photoUrl),
            summary: worker.summary
        )
    }
}
