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
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("Confirmed workers")
                    .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(DS.Color.muted)
                Spacer()
                if let averageRating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").foregroundStyle(DS.Color.warning)
                        Text(String(format: "%.1f avg", averageRating)).fontWeight(.semibold)
                            .foregroundStyle(DS.Color.text)
                    }
                    .dsFont(.caption)
                }
            }

            ForEach(workers) { worker in
                NavigationLink {
                    DetailedWorkerView(
                        applicant: applicant(for: worker),
                        onAccept: {}, onDecline: {},
                        jobId: jobId,
                        showActions: false
                    )
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        ApplicantAvatar(photoUrl: worker.photoUrl, size: 32, initials: DSAvatar.initials(from: worker.name))
                        Text(worker.name)
                            .font(DS.Font.make(14, .medium, relativeTo: .callout))
                            .foregroundStyle(DS.Color.text)
                        Spacer()
                        ApplicantRatingLabel(
                            average: worker.summary?.ratingAverage,
                            count: worker.summary?.reviewCount ?? 0
                        )
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Color.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
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
